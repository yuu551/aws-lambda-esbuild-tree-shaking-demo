#!/bin/bash

# Lambda関数の検証用テストスクリプト
# 各パターンの動作確認とパフォーマンス比較

set -e

echo "=== Lambda Functions Test Script ==="
echo "Testing different bundling patterns for performance comparison"
echo

# 設定
STACK_NAME="SampleStack"
REGION=${AWS_DEFAULT_REGION:-us-east-1}

# カラー出力用
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ユーティリティ関数
log() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Lambda関数の情報を取得
get_function_info() {
    local function_name=$1
    echo "Getting info for $function_name..."
    
    # 関数の存在確認
    if ! aws lambda get-function --function-name "$function_name" --region "$REGION" >/dev/null 2>&1; then
        error "Function $function_name not found. Please deploy the stack first."
        return 1
    fi
    
    # コードサイズの取得
    local config=$(aws lambda get-function --function-name "$function_name" --region "$REGION" --query 'Configuration')
    local code_size=$(echo "$config" | jq -r '.CodeSize')
    local memory_size=$(echo "$config" | jq -r '.MemorySize')
    local runtime=$(echo "$config" | jq -r '.Runtime')
    
    echo "  Code Size: ${code_size} bytes"
    echo "  Memory: ${memory_size} MB"
    echo "  Runtime: ${runtime}"
    
    return 0
}

# Lambda関数を呼び出してレスポンス時間を測定
test_function_performance() {
    local function_name=$1
    local test_payload=$2
    local iterations=${3:-3}
    
    log "Testing $function_name performance ($iterations iterations)..."
    
    local total_duration=0
    local total_billed_duration=0
    local cold_start_duration=0
    
    for i in $(seq 1 $iterations); do
        echo "  Iteration $i/$iterations..."
        
        # Lambda関数を呼び出し
        local response=$(aws lambda invoke \
            --function-name "$function_name" \
            --payload "$test_payload" \
            --region "$REGION" \
            --cli-binary-format raw-in-base64-out \
            /tmp/response_${function_name}_${i}.json 2>&1)
        
        # レスポンス時間の抽出
        if echo "$response" | jq -e '.ExecutedVersion' >/dev/null 2>&1; then
            local duration=$(echo "$response" | jq -r '.Duration // 0')
            local billed_duration=$(echo "$response" | jq -r '.BilledDuration // 0')
            
            echo "    Duration: ${duration}ms, Billed: ${billed_duration}ms"
            
            total_duration=$((total_duration + ${duration%.*}))
            total_billed_duration=$((total_billed_duration + ${billed_duration%.*}))
            
            # 初回実行をコールドスタートとして記録
            if [ $i -eq 1 ]; then
                cold_start_duration=${duration%.*}
            fi
        else
            error "Failed to invoke $function_name on iteration $i"
            echo "$response"
        fi
        
        # レスポンス内容の確認
        if [ -f "/tmp/response_${function_name}_${i}.json" ]; then
            local status_code=$(jq -r '.statusCode // "unknown"' "/tmp/response_${function_name}_${i}.json")
            if [ "$status_code" = "200" ]; then
                success "Function executed successfully"
            else
                warning "Function returned status: $status_code"
                cat "/tmp/response_${function_name}_${i}.json"
            fi
        fi
        
        # ウォームアップのために少し待機
        if [ $i -lt $iterations ]; then
            sleep 2
        fi
    done
    
    # 平均値の計算
    local avg_duration=$((total_duration / iterations))
    local avg_billed_duration=$((total_billed_duration / iterations))
    
    echo "  Results:"
    echo "    Cold Start: ${cold_start_duration}ms"
    echo "    Average Duration: ${avg_duration}ms"
    echo "    Average Billed Duration: ${avg_billed_duration}ms"
    echo
    
    # 結果をファイルに保存
    echo "${function_name},${cold_start_duration},${avg_duration},${avg_billed_duration}" >> /tmp/performance_results.csv
}

# メイン処理
main() {
    log "Starting Lambda function tests..."
    
    # 結果ファイルの初期化
    echo "FunctionName,ColdStart,AvgDuration,AvgBilledDuration" > /tmp/performance_results.csv
    
    # テスト用ペイロード
    local test_payload_function_a='{"records":[{"id":"test1"},{"id":"test2"}],"userId":"test-user-123"}'
    local test_payload_function_b='{"userId":"test-user-123","message":"Test notification message"}'
    local test_payload_billing='{"userId":"test-user-123","billingPeriod":"2024-01"}'
    
    echo "=== Function Information ==="
    
    # 各関数の情報を取得
    local functions=(
        "sample-function-a-all-external"
        "sample-function-a-specific-external"
        "sample-billing-processor-optimized"
        "sample-function-b-with-layer"
        "sample-function-a-no-optimization"
        "sample-function-a-full-bundle"
        "sample-function-a-without-aws-sdk-exclusion"
    )
    
    for func in "${functions[@]}"; do
        echo "--- $func ---"
        get_function_info "$func" || continue
        echo
    done
    
    echo "=== Performance Tests ==="
    
    # パフォーマンステスト実行
    test_function_performance "sample-function-a-all-external" "$test_payload_function_a" 3
    test_function_performance "sample-function-a-specific-external" "$test_payload_function_a" 3
    test_function_performance "sample-billing-processor-optimized" "$test_payload_billing" 3
    test_function_performance "sample-function-b-with-layer" "$test_payload_function_b" 3
    test_function_performance "sample-function-a-no-optimization" "$test_payload_function_a" 3
    test_function_performance "sample-function-a-full-bundle" "$test_payload_function_a" 3
    test_function_performance "sample-function-a-without-aws-sdk-exclusion" "$test_payload_function_a" 3
    
    echo "=== Test Results Summary ==="
    
    if [ -f "/tmp/performance_results.csv" ]; then
        column -t -s',' /tmp/performance_results.csv
        echo
        success "Performance results saved to /tmp/performance_results.csv"
    fi
    
    # バンドルサイズ比較
    echo "=== Bundle Size Comparison ==="
    
    for func in "${functions[@]}"; do
        echo -n "$func: "
        local info=$(aws lambda get-function --function-name "$func" --region "$REGION" --query 'Configuration.CodeSize' --output text 2>/dev/null || echo "N/A")
        echo "${info} bytes"
    done
    
    echo
    success "All tests completed!"
    echo
    warning "Note: To compare bundle sizes effectively:"
    echo "  1. Check the AWS Lambda Console for detailed package information"
    echo "  2. Compare cold start times between different bundling patterns"
    echo "  3. Monitor memory usage in CloudWatch"
}

# 引数チェック
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--help]"
    echo
    echo "This script tests the deployed Lambda functions with different bundling patterns:"
    echo "  - All external packages (with layer)"
    echo "  - Specific external packages (with layer)"
    echo "  - Tree shaking only (no layer)"
    echo "  - Function with notification service"
    echo
    echo "Prerequisites:"
    echo "  - AWS CLI configured"
    echo "  - jq installed"
    echo "  - CDK stack deployed (run: npm run build-layer && cdk deploy)"
    echo
    exit 0
fi

# 依存関係のチェック
command -v aws >/dev/null 2>&1 || { error "AWS CLI is not installed"; exit 1; }
command -v jq >/dev/null 2>&1 || { error "jq is not installed"; exit 1; }

# メイン処理実行
main