#!/bin/bash

# Import-Only Tree Shaking テスト
# billing-processor に notification-service を import だけして使わない場合の挙動をテスト

set -e

echo "=== Import-Only Tree Shaking Test ==="
echo "Testing if importing but not using a module affects bundle size and deployment"
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

# 現在のbilling-processorの状態を確認
get_current_state() {
    log "Getting current billing-processor state..."
    
    local func="sample-billing-processor-optimized"
    
    # 現在のハッシュとサイズを取得
    local current_hash=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSha256' --output text 2>/dev/null || echo "N/A")
    local current_size=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSize' --output text 2>/dev/null || echo "N/A")
    
    echo "Current state:"
    echo "  Function: $func"
    echo "  Hash: ${current_hash:0:16}..."
    echo "  Size: $current_size bytes"
    echo
    
    # 状態をファイルに保存
    echo "$func,$current_hash,$current_size" > /tmp/billing_state_before.csv
}

# notification-serviceの内容を確認
analyze_notification_service() {
    log "Analyzing notification-service.ts structure..."
    
    local file="src/services/notification-service.ts"
    
    echo "=== notification-service.ts Analysis ==="
    echo "File: $file"
    echo
    
    # 副作用のチェック
    echo "Side effects detection:"
    if grep -n "^const\|^let\|^var\|console\." "$file" | head -5; then
        warning "Found potential side effects (top-level statements)"
    else
        success "No obvious side effects detected"
    fi
    echo
    
    # exportされる関数の確認
    echo "Exported functions:"
    grep -n "^export" "$file" || echo "  No exports found"
    echo
    
    # importされる依存関係
    echo "Dependencies:"
    grep -n "^import" "$file" || echo "  No imports found"
    echo
}

# billing-processorにimport文を追加（使用はしない）
add_import_only() {
    log "Adding import-only statement to billing-processor..."
    
    local file="src/lambda/billing-processor/index.ts"
    
    # バックアップ作成
    cp "$file" "${file}.backup"
    
    # 現在のimport文を確認
    echo "Current imports in billing-processor:"
    grep "^import" "$file"
    echo
    
    # すでにnotification-serviceがimportされているかチェック
    if grep -q "notification-service" "$file"; then
        warning "notification-service already imported in $file"
        return 0
    fi
    
    # 既存のimportの後に新しいimport文を追加
    sed -i.tmp '3a\
// === IMPORT-ONLY TEST: 使用しないが import だけ ===\
import { sendUserNotification } from '"'"'../../services/notification-service'"'"';\
// sendUserNotification は使用しない（import のみ）
' "$file"
    
    rm "${file}.tmp" 2>/dev/null || true
    
    success "Added import-only statement"
    echo "Added lines:"
    echo "  import { sendUserNotification } from '../../services/notification-service';"
    echo "  // sendUserNotification は使用しない（import のみ）"
    echo
    
    # 変更後のimport文を表示
    echo "Updated imports:"
    grep -A2 -B1 "notification-service" "$file"
    echo
}

# CDKによるバンドル分析
analyze_bundle_generation() {
    log "Analyzing bundle generation with CDK..."
    
    # CDKでsynthを実行してバンドル生成を確認
    echo "Generating CDK template and bundles..."
    cdk synth --quiet > /tmp/template_after_import.json
    
    # バンドル生成過程での出力をキャプチャ
    echo "Building project to see esbuild output..."
    npm run build 2>&1 | tee /tmp/build_output.log
    
    # esbuildの警告やエラーをチェック
    echo
    echo "=== esbuild Analysis ==="
    if grep -i "warning\|error" /tmp/build_output.log; then
        warning "Found warnings/errors in build output"
    else
        success "Clean build output"
    fi
    echo
}

# CDK差分の確認
check_cdk_diff() {
    log "Checking CDK diff after adding import-only..."
    
    cdk diff > /tmp/cdk_diff_import_only.txt 2>&1 || true
    
    echo "=== CDK Diff Results ==="
    
    # billing-processorの変更をチェック
    if grep -q "BillingProcessorOptimized" /tmp/cdk_diff_import_only.txt; then
        warning "CDK detected changes in BillingProcessorOptimized"
        echo "Change details:"
        grep -A5 -B5 "BillingProcessorOptimized" /tmp/cdk_diff_import_only.txt || true
    else
        success "No changes detected in BillingProcessorOptimized"
    fi
    echo
    
    echo "Full CDK diff:"
    cat /tmp/cdk_diff_import_only.txt
    echo
}

# 実際にデプロイして結果を確認
test_deployment() {
    log "Testing actual deployment behavior..."
    
    read -p "Proceed with deployment to test actual bundle size change? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Skipping deployment test"
        return 0
    fi
    
    # デプロイ実行
    cdk deploy --require-approval never
    
    # 少し待機
    sleep 5
    
    # 新しい状態を取得
    local func="sample-billing-processor-optimized"
    local new_hash=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSha256' --output text 2>/dev/null || echo "ERROR")
    local new_size=$(aws lambda get-function --function-name "$func" --query 'Configuration.CodeSize' --output text 2>/dev/null || echo "ERROR")
    
    # 結果比較
    echo "=== Deployment Results ==="
    echo "Function,Before_Hash,After_Hash,Before_Size,After_Size,Hash_Changed,Size_Changed" > /tmp/import_test_results.csv
    
    while IFS=',' read -r func old_hash old_size; do
        local hash_changed="No"
        local size_changed="No"
        
        if [ "$old_hash" != "$new_hash" ]; then
            hash_changed="Yes"
        fi
        
        if [ "$old_size" != "$new_size" ]; then
            size_changed="Yes"
        fi
        
        echo "${func},${old_hash:0:16}...,${new_hash:0:16}...,${old_size},${new_size},${hash_changed},${size_changed}" >> /tmp/import_test_results.csv
        
    done < /tmp/billing_state_before.csv
    
    column -t -s',' /tmp/import_test_results.csv
    echo
}

# 結果分析
analyze_import_only_results() {
    log "Analyzing import-only tree shaking results..."
    
    echo "=== Import-Only Tree Shaking Analysis ==="
    echo
    
    # 結果ファイルが存在する場合
    if [ -f "/tmp/import_test_results.csv" ]; then
        local hash_changed=$(tail -1 /tmp/import_test_results.csv | cut -d',' -f6)
        local size_changed=$(tail -1 /tmp/import_test_results.csv | cut -d',' -f7)
        local old_size=$(tail -1 /tmp/import_test_results.csv | cut -d',' -f4)
        local new_size=$(tail -1 /tmp/import_test_results.csv | cut -d',' -f5)
        
        echo "Results Summary:"
        echo "1. Import without usage test:"
        echo "   └─ Hash changed: $hash_changed"
        echo "   └─ Size changed: $size_changed"
        echo "   └─ Size: $old_size → $new_size bytes"
        echo
        
        # Tree Shakingの効果判定
        if [ "$hash_changed" = "Yes" ] && [ "$size_changed" = "Yes" ]; then
            if [ "$new_size" -gt "$old_size" ]; then
                error "Bundle size INCREASED - Tree shaking failed!"
                echo "   → notification-service was included despite not being used"
                echo "   → This suggests the module has side effects"
            else
                warning "Hash changed but size decreased - unexpected behavior"
            fi
        elif [ "$hash_changed" = "Yes" ] && [ "$size_changed" = "No" ]; then
            success "Size unchanged despite import - Tree shaking partially worked!"
            echo "   → notification-service code was not included"
            echo "   → Hash changed due to import statement modification"
        elif [ "$hash_changed" = "No" ]; then
            error "No changes detected - CDK optimization issue or test setup problem"
        fi
    else
        warning "No deployment test results available"
    fi
    
    echo
    echo "Key Findings:"
    echo "- Tree shaking with import-only: $([ -f "/tmp/import_test_results.csv" ] && echo "$(tail -1 /tmp/import_test_results.csv | cut -d',' -f7 | sed 's/No/✅ Effective/;s/Yes/❌ Failed/')" || echo "❓ Not tested")"
    echo "- Side effect detection: $(grep -q "^const\|console\." src/services/notification-service.ts && echo "⚠️ Has side effects" || echo "✅ Pure module")"
    echo "- CDK rebuild trigger: $([ -f "/tmp/cdk_diff_import_only.txt" ] && grep -q "BillingProcessorOptimized" /tmp/cdk_diff_import_only.txt && echo "✅ Detected changes" || echo "❌ No changes")"
}

# ファイル復元
restore_files() {
    log "Restoring original files..."
    
    local file="src/lambda/billing-processor/index.ts"
    if [ -f "${file}.backup" ]; then
        mv "${file}.backup" "$file"
        success "Restored $file"
    fi
    
    echo
    warning "To fully revert deployed changes, run: cdk deploy"
}

# メイン処理
main() {
    echo "Testing Tree Shaking behavior with import-only statements"
    echo "Scenario: Import notification-service in billing-processor but don't use it"
    echo "Expected: Tree shaking should exclude the unused code"
    echo "Timestamp: $(date)"
    echo
    
    # 現在の状態を記録
    get_current_state
    
    # notification-serviceの分析
    analyze_notification_service
    
    # import文を追加
    add_import_only
    
    # バンドル生成の分析
    analyze_bundle_generation
    
    # CDK差分確認
    check_cdk_diff
    
    # デプロイテスト
    test_deployment
    
    # 結果分析
    analyze_import_only_results
    
    # クリーンアップ確認
    echo
    read -p "Restore original files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_files
    fi
    
    success "Import-only tree shaking test completed!"
    echo
    echo "Results saved to:"
    echo "  - /tmp/import_test_results.csv"
    echo "  - /tmp/cdk_diff_import_only.txt"
    echo "  - /tmp/build_output.log"
}

# ヘルプ表示
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--help]"
    echo
    echo "Tests tree shaking effectiveness when importing but not using modules:"
    echo "  - Adds import statement for notification-service to billing-processor"
    echo "  - Tests if unused import affects bundle size"
    echo "  - Analyzes side effects impact on tree shaking"
    echo "  - Verifies CDK's deployment decision logic"
    echo
    echo "Expected outcomes:"
    echo "  1. Pure modules: Should be tree-shaken out (no size increase)"
    echo "  2. Modules with side effects: Will be included (size increase)"
    echo "  3. CDK: Should detect file changes and trigger rebuild"
    echo
    echo "Prerequisites:"
    echo "  - CDK stack deployed"
    echo "  - AWS CLI configured"
    echo "  - npm run build working"
    echo
    exit 0
fi

# メイン処理実行
main