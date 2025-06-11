#!/bin/bash

# Lambda関数修正時のデプロイ影響テストスクリプト
# 共有コードの修正が各パターンにどう影響するかを検証

set -e

echo "=== Lambda Modification Impact Test ==="
echo "Testing how code changes affect different bundling patterns"
echo

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 現在のバンドルサイズを記録
record_current_sizes() {
    log "Recording current bundle sizes..."
    
    local functions=(
        "sample-function-a-all-external"
        "sample-function-a-specific-external" 
        "sample-function-a-no-optimization"
        "sample-function-a-full-bundle"
    )
    
    echo "FunctionName,Size" > /tmp/sizes_before.csv
    
    for func in "${functions[@]}"; do
        local size=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSize' --output text 2>/dev/null || echo "0")
        echo "${func},${size}" >> /tmp/sizes_before.csv
        echo "  $func: ${size} bytes"
    done
    
    echo
}

# コードの軽微な修正を行う
make_minor_change() {
    log "Making minor change to shared repository code..."
    
    # user-repository.ts にコメントを追加（機能に影響しない変更）
    local repo_file="src/repositories/user-repository.ts"
    
    if [ ! -f "$repo_file" ]; then
        error "Repository file not found: $repo_file"
        return 1
    fi
    
    # バックアップ作成
    cp "$repo_file" "${repo_file}.backup"
    
    # ファイルの最後にコメントを追加
    echo "" >> "$repo_file"
    echo "// Minor change added at $(date) for testing deployment impact" >> "$repo_file"
    echo "// This change should not affect tree-shaking but will trigger redeployment" >> "$repo_file"
    
    success "Minor change added to $repo_file"
}

# 機能的な変更を行う
make_functional_change() {
    log "Making functional change to shared service code..."
    
    local service_file="src/services/billing-service.ts"
    
    if [ ! -f "$service_file" ]; then
        error "Service file not found: $service_file"
        return 1
    fi
    
    # バックアップ作成
    cp "$service_file" "${service_file}.backup"
    
    # 新しい関数を追加（billing-processorが使わない機能）
    cat >> "$service_file" << 'EOF'

// 新しい機能: ユーザー使用量分析（billing-processorでは使用しない）
export const analyzeUserUsage = async (userId: string): Promise<{
  totalRequests: number;
  averageResponseTime: number;
  usagePattern: string;
}> => {
  console.log(`Analyzing usage for user ${userId}`);
  
  // 重い処理をシミュレート
  const heavyCalculation = Array.from({length: 1000}, (_, i) => i * Math.random()).reduce((a, b) => a + b, 0);
  
  return {
    totalRequests: Math.floor(heavyCalculation % 10000),
    averageResponseTime: Math.floor(heavyCalculation % 500),
    usagePattern: heavyCalculation > 500000 ? 'heavy' : 'light',
  };
};

// もう一つの新機能: 使用量レポート生成
export const generateUsageReport = async (userId: string, period: string): Promise<string> => {
  const usage = await analyzeUserUsage(userId);
  
  return `Usage Report for ${userId} (${period}):
- Total Requests: ${usage.totalRequests}
- Avg Response Time: ${usage.averageResponseTime}ms
- Usage Pattern: ${usage.usagePattern}
Generated at: ${new Date().toISOString()}`;
};
EOF
    
    success "Functional change added to $service_file"
}

# CDK デプロイを実行
deploy_changes() {
    log "Deploying changes..."
    
    # まずビルド
    npm run build
    
    # デプロイ実行
    cdk deploy --require-approval never
    
    success "Changes deployed"
}

# デプロイ後のサイズを記録
record_new_sizes() {
    log "Recording new bundle sizes after deployment..."
    
    # 少し待機（Lambda更新の完了を待つ）
    sleep 10
    
    local functions=(
        "sample-function-a-all-external"
        "sample-function-a-specific-external"
        "sample-function-a-no-optimization" 
        "sample-function-a-full-bundle"
    )
    
    echo "FunctionName,Size" > /tmp/sizes_after.csv
    
    for func in "${functions[@]}"; do
        local size=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSize' --output text 2>/dev/null || echo "0")
        echo "${func},${size}" >> /tmp/sizes_after.csv
        echo "  $func: ${size} bytes"
    done
    
    echo
}

# 結果比較
compare_results() {
    log "Comparing results..."
    
    echo "=== Bundle Size Comparison ==="
    echo "Function Name                     | Before | After  | Change | Impact"
    echo "----------------------------------|--------|--------|--------|--------"
    
    while IFS=',' read -r func size_after; do
        if [ "$func" = "FunctionName" ]; then continue; fi
        
        local size_before=$(grep "^$func," /tmp/sizes_before.csv | cut -d',' -f2)
        local change=$((size_after - size_before))
        local impact=""
        
        if [ $change -eq 0 ]; then
            impact="None"
        elif [ $change -gt 0 ]; then
            impact="+${change} bytes"
        else
            impact="${change} bytes"
        fi
        
        printf "%-33s | %6s | %6s | %6s | %s\n" "$func" "$size_before" "$size_after" "$change" "$impact"
        
    done < /tmp/sizes_after.csv
    
    echo
    echo "=== Analysis ==="
    
    # 分析結果
    local external_change=$(grep "sample-function-a-all-external" /tmp/sizes_after.csv | cut -d',' -f2)
    local external_before=$(grep "sample-function-a-all-external" /tmp/sizes_before.csv | cut -d',' -f2)
    
    local full_change=$(grep "sample-function-a-full-bundle" /tmp/sizes_after.csv | cut -d',' -f2)
    local full_before=$(grep "sample-function-a-full-bundle" /tmp/sizes_before.csv | cut -d',' -f2)
    
    echo "Key Findings:"
    echo "1. External packages pattern: $((external_change - external_before)) bytes change"
    echo "2. Full bundle pattern: $((full_change - full_before)) bytes change"
    
    if [ $((full_change - full_before)) -gt $((external_change - external_before)) ]; then
        echo "3. ✅ External packages pattern is more resilient to changes"
        echo "4. ✅ Tree shaking effectiveness confirmed"
    else
        echo "3. ⚠️  Unexpected result - investigate further"
    fi
}

# ファイルの復元
restore_files() {
    log "Restoring original files..."
    
    for file in src/repositories/user-repository.ts src/services/billing-service.ts; do
        if [ -f "${file}.backup" ]; then
            mv "${file}.backup" "$file"
            echo "  Restored $file"
        fi
    done
    
    success "Files restored"
}

# メイン処理
main() {
    echo "This script demonstrates the impact of code changes on different bundling patterns"
    echo "Timestamp: $(date)"
    echo
    
    # 現在のサイズを記録
    record_current_sizes
    
    # 変更タイプの選択
    echo "Select change type:"
    echo "1) Minor change (comment only)"
    echo "2) Functional change (new unused functions)"
    echo "3) Both changes"
    echo
    read -p "Enter choice (1-3): " choice
    
    case $choice in
        1)
            make_minor_change
            ;;
        2)
            make_functional_change
            ;;
        3)
            make_minor_change
            make_functional_change
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
    
    # デプロイ実行
    deploy_changes
    
    # 新しいサイズを記録
    record_new_sizes
    
    # 結果比較
    compare_results
    
    # クリーンアップの確認
    echo
    read -p "Restore original files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_files
        echo
        warning "To fully revert, run: cdk deploy"
    fi
    
    success "Modification impact test completed!"
}

# ヘルプ表示
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--help]"
    echo
    echo "Tests the impact of code modifications on different bundling patterns:"
    echo "  - Minor changes (comments)"
    echo "  - Functional changes (new unused code)"
    echo "  - Bundle size comparison"
    echo "  - Tree shaking effectiveness"
    echo
    echo "Prerequisites:"
    echo "  - CDK stack already deployed"
    echo "  - AWS CLI configured"
    echo
    exit 0
fi

# メイン処理実行
main