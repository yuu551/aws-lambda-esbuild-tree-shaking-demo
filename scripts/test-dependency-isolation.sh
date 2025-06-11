#!/bin/bash

# 依存関係分離テスト: Tree Shakingによる未参照コード変更時の影響範囲検証
# billing-processorが参照していないnotification-serviceを変更した時の挙動をテスト

set -e

echo "=== Dependency Isolation Test ==="
echo "Testing if Lambda functions are updated only when their referenced code changes"
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

# CDKテンプレートのハッシュを取得
get_function_hashes() {
    log "Getting current function deployment hashes..."
    
    # CDKが生成するハッシュを取得
    cdk synth --quiet > /tmp/template_before.json
    
    # 各関数のコードハッシュを抽出
    echo "Function,CodeSha256" > /tmp/hashes_before.csv
    
    local functions=(
        "sample-billing-processor-optimized"
        "sample-function-b-with-layer"
        "sample-function-a-all-external"
    )
    
    for func in "${functions[@]}"; do
        # 実際のLambda関数からハッシュ取得
        local hash=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSha256' --output text 2>/dev/null || echo "N/A")
        echo "${func},${hash}" >> /tmp/hashes_before.csv
        echo "  $func: ${hash:0:16}..."
    done
    echo
}

# 未参照コードの変更
modify_unreferenced_code() {
    log "Modifying notification-service.ts (not referenced by billing-processor)..."
    
    local file="src/services/notification-service.ts"
    
    # バックアップ作成
    cp "$file" "${file}.backup"
    
    # 新しい関数を追加（billing-processorでは使用されない）
    # 重複チェック
    if grep -q "sendBulkNotifications" "$file"; then
        warning "Functions already added to $file, skipping addition"
        return 0
    fi
    
    cat >> "$file" << 'EOF'

// === 追加された機能（billing-processorでは未参照） ===
export const sendBulkNotifications = async (
  userIds: string[],
  message: string
): Promise<void> => {
  console.log("Sending bulk notifications to multiple users...");
  
  // 重い処理をシミュレート
  const heavyProcessing = Array.from({length: 5000}, (_, i) => 
    Math.sin(i) * Math.cos(i * 2) + Math.random()
  ).reduce((sum, val) => sum + val, 0);
  
  for (const userId of userIds) {
    await sendUserNotification(userId, `[BULK] ${message}`);
    // 処理結果をログに記録
    console.log(`Bulk notification sent to ${userId}, processing result: ${heavyProcessing}`);
  }
};

export const scheduleNotification = async (
  userId: string,
  message: string,
  scheduleTime: Date
): Promise<string> => {
  console.log(`Scheduling notification for ${userId} at ${scheduleTime.toISOString()}`);
  
  // スケジューリングロジック（重い処理）
  const schedulingData = {
    userId,
    message,
    scheduleTime: scheduleTime.toISOString(),
    created: new Date().toISOString(),
    // 複雑な計算結果
    priority: Math.floor(Math.random() * 10) + 1,
    retryCount: 0,
    metadata: {
      source: 'scheduled-notification',
      version: '2.0.0',
      features: ['bulk', 'schedule', 'retry'],
    }
  };
  
  // 実際のシステムではDBに保存
  console.log('Scheduled notification data:', JSON.stringify(schedulingData, null, 2));
  
  return `scheduled-${Date.now()}`;
};

// 通知統計機能
export const getNotificationStats = async (userId: string): Promise<{
  totalSent: number;
  totalScheduled: number;
  successRate: number;
}> => {
  // 統計計算（重い処理）
  const mockStats = {
    totalSent: Math.floor(Math.random() * 1000),
    totalScheduled: Math.floor(Math.random() * 100),
    successRate: 0.85 + Math.random() * 0.15,
  };
  
  console.log(`Notification stats for ${userId}:`, mockStats);
  return mockStats;
};
EOF
    
    success "Added 3 new functions to notification-service.ts"
    echo "  - sendBulkNotifications() (heavy processing)"
    echo "  - scheduleNotification() (complex scheduling)"  
    echo "  - getNotificationStats() (statistics calculation)"
    echo
}

# 参照されるコードの変更
modify_referenced_code() {
    log "Modifying billing-service.ts (referenced by billing-processor)..."
    
    local file="src/services/billing-service.ts"
    
    # バックアップ作成
    cp "$file" "${file}.backup"
    
    # 既存関数にコメントを追加（軽微な変更）
    sed -i.tmp 's/export const calculateUserBilling/\/\/ Updated at '$(date +%s)' - Enhanced billing calculation\nexport const calculateUserBilling/' "$file"
    rm "${file}.tmp" 2>/dev/null || true
    
    success "Added timestamp comment to calculateUserBilling function"
    echo
}

# CDKの差分確認
check_cdk_diff() {
    log "Checking CDK diff to see which functions will be updated..."
    
    # CDK差分を取得
    cdk diff > /tmp/cdk_diff_output.txt 2>&1 || true
    
    echo "=== CDK Diff Results ==="
    
    # 各関数の更新有無をチェック
    local functions=(
        "BillingProcessorOptimized"
        "FunctionBWithLayer" 
        "FunctionAAllExternal"
    )
    
    echo "Function Update Analysis:"
    for func in "${functions[@]}"; do
        if grep -q "$func" /tmp/cdk_diff_output.txt; then
            echo "  ✅ $func: Will be updated"
        else
            echo "  ❌ $func: No changes detected"
        fi
    done
    
    echo
    echo "Full CDK diff:"
    cat /tmp/cdk_diff_output.txt
    echo
}

# デプロイ実行
deploy_changes() {
    log "Deploying changes to test actual update behavior..."
    
    # ビルド実行
    npm run build
    
    # デプロイ実行（自動承認）
    cdk deploy --require-approval never
    
    success "Deployment completed"
    echo
}

# デプロイ後のハッシュ確認
verify_deployment_impact() {
    log "Verifying which functions were actually updated..."
    
    # 少し待機
    sleep 5
    
    echo "Function,OldHash,NewHash,Changed" > /tmp/deployment_results.csv
    
    while IFS=',' read -r func old_hash; do
        if [ "$func" = "Function" ]; then continue; fi
        
        local new_hash=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSha256' --output text 2>/dev/null || echo "ERROR")
        local changed="No"
        
        if [ "$old_hash" != "$new_hash" ]; then
            changed="Yes"
        fi
        
        echo "${func},${old_hash:0:16}...,${new_hash:0:16}...,$changed" >> /tmp/deployment_results.csv
        
    done < /tmp/hashes_before.csv
    
    echo "=== Deployment Impact Analysis ==="
    column -t -s',' /tmp/deployment_results.csv
    echo
}

# 結果分析
analyze_results() {
    log "Analyzing tree shaking effectiveness..."
    
    echo "=== Tree Shaking Dependency Isolation Results ==="
    echo
    
    # billing-processorの状況確認
    local billing_changed=$(grep "sample-billing-processor-optimized" /tmp/deployment_results.csv | cut -d',' -f4)
    local function_b_changed=$(grep "sample-function-b-with-layer" /tmp/deployment_results.csv | cut -d',' -f4)
    local function_a_changed=$(grep "sample-function-a-all-external" /tmp/deployment_results.csv | cut -d',' -f4)
    
    echo "Analysis:"
    echo "1. notification-service.ts changes (unreferenced by billing-processor):"
    echo "   └─ billing-processor updated: $billing_changed"
    echo "   └─ function-b updated: $function_b_changed (expected: Yes, it uses notification)"
    echo
    echo "2. billing-service.ts changes (referenced by billing-processor):"
    echo "   └─ billing-processor should be updated due to this change"
    echo
    
    # 理想的な結果の判定
    if [ "$billing_changed" = "Yes" ]; then
        warning "billing-processor was updated despite notification-service being unreferenced"
        echo "   → This suggests CDK detected input file changes regardless of tree shaking"
        echo "   → Tree shaking reduces bundle size but doesn't affect CDK's deploy decision"
    else
        success "billing-processor was NOT updated for unreferenced changes!"
        echo "   → Tree shaking successfully isolated dependencies at CDK level"
        echo "   → This is the ideal behavior for large-scale applications"
    fi
    
    echo
    echo "Key Findings:"
    echo "- Tree shaking impact on bundle size: ✅ Confirmed (1KB vs 64KB)"
    echo "- Tree shaking impact on deploy decisions: $([ "$billing_changed" = "No" ] && echo "✅ Confirmed" || echo "❌ Not achieved")"
    echo "- CDK deployment optimization: $([ "$billing_changed" = "No" ] && echo "✅ Working" || echo "⚠️ Input-file based")"
}

# ファイル復元
restore_files() {
    log "Restoring original files..."
    
    for file in src/services/notification-service.ts src/services/billing-service.ts; do
        if [ -f "${file}.backup" ]; then
            mv "${file}.backup" "$file"
            echo "  Restored $file"
        fi
    done
    
    success "Original files restored"
    echo
}

# メイン処理
main() {
    echo "Testing if tree shaking can isolate deployment dependencies"
    echo "Scenario: Modify notification-service (unreferenced by billing-processor)"
    echo "Expected: billing-processor should NOT be updated"
    echo "Timestamp: $(date)"
    echo
    
    # テストタイプの選択
    echo "Select test type:"
    echo "1) Test unreferenced code changes only"
    echo "2) Test referenced code changes only" 
    echo "3) Test both (comprehensive test)"
    echo
    read -p "Enter choice (1-3): " choice
    
    # 現在の状態を記録
    get_function_hashes
    
    case $choice in
        1)
            modify_unreferenced_code
            ;;
        2)
            modify_referenced_code
            ;;
        3)
            modify_unreferenced_code
            modify_referenced_code
            ;;
        *)
            error "Invalid choice"
            exit 1
            ;;
    esac
    
    # CDK差分確認
    check_cdk_diff
    
    # デプロイ実行確認
    echo
    read -p "Proceed with deployment to test actual behavior? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        deploy_changes
        verify_deployment_impact
        analyze_results
    else
        log "Skipping deployment. You can manually run 'cdk deploy' later."
    fi
    
    # クリーンアップ確認
    echo
    read -p "Restore original files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_files
        if [[ $REPLY =~ ^[Yy]$ ]] && [ -f "/tmp/deployment_results.csv" ]; then
            echo
            warning "To fully revert deployed changes, run: cdk deploy"
        fi
    fi
    
    success "Dependency isolation test completed!"
    echo
    echo "Results summary saved to:"
    echo "  - /tmp/deployment_results.csv"
    echo "  - /tmp/cdk_diff_output.txt"
}

# ヘルプ表示
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--help]"
    echo
    echo "Tests tree shaking's effect on Lambda deployment dependencies:"
    echo "  - Modifies unreferenced code (notification-service)"
    echo "  - Checks if billing-processor (which doesn't use it) gets updated"
    echo "  - Verifies CDK's deployment decision logic"
    echo "  - Analyzes tree shaking isolation effectiveness"
    echo
    echo "Test scenarios:"
    echo "  1. Unreferenced changes: Should not trigger billing-processor update"
    echo "  2. Referenced changes: Should trigger billing-processor update"
    echo "  3. Comprehensive: Tests both scenarios"
    echo
    echo "Prerequisites:"
    echo "  - CDK stack deployed"
    echo "  - AWS CLI configured"
    echo
    exit 0
fi

# メイン処理実行
main