#!/bin/bash

# バンドル内容詳細分析スクリプト
# esbuild の出力を直接確認して Tree Shaking の効果を分析

set -e

echo "=== Bundle Content Analysis ==="
echo "Analyzing actual bundle contents to understand tree shaking behavior"
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

# esbuild を直接実行してバンドル内容を確認
analyze_direct_bundle() {
    log "Running esbuild directly to analyze bundle content..."
    
    # 一時的なビルドディレクトリを作成
    mkdir -p /tmp/bundle-analysis
    
    # 現在の billing-processor を直接 esbuild でバンドル
    echo "Building current billing-processor with esbuild..."
    npx esbuild src/lambda/billing-processor/index.ts \
        --bundle \
        --platform=node \
        --target=node20 \
        --external:@aws-sdk/* \
        --external:aws-sdk \
        --tree-shaking=true \
        --minify=false \
        --sourcemap=false \
        --outfile=/tmp/bundle-analysis/billing_before.js
    
    # バンドルサイズを記録
    local size_before=$(wc -c < /tmp/bundle-analysis/billing_before.js)
    echo "Bundle size before import: $size_before bytes"
    
    # バンドル内容の分析
    echo
    echo "=== Bundle Content Analysis (Before Import) ==="
    echo "Searching for notification-related code:"
    if grep -i "notification\|sns" /tmp/bundle-analysis/billing_before.js; then
        warning "Found notification-related code in bundle"
    else
        success "No notification-related code found"
    fi
    echo
}

# import文を追加してバンドル分析
test_with_import() {
    log "Adding import statement and re-analyzing..."
    
    local file="src/lambda/billing-processor/index.ts"
    
    # バックアップ作成
    cp "$file" "${file}.backup"
    
    # import文を追加
    sed -i.tmp '3a\
import { sendUserNotification } from '"'"'../../services/notification-service'"'"';\
// TEST: Import but not use
' "$file"
    rm "${file}.tmp" 2>/dev/null || true
    
    # 変更後のファイル内容を確認
    echo "Modified file imports:"
    grep "^import" "$file"
    echo
    
    # 再度 esbuild でバンドル
    echo "Building modified billing-processor with esbuild..."
    npx esbuild src/lambda/billing-processor/index.ts \
        --bundle \
        --platform=node \
        --target=node20 \
        --external:@aws-sdk/* \
        --external:aws-sdk \
        --tree-shaking=true \
        --minify=false \
        --sourcemap=false \
        --outfile=/tmp/bundle-analysis/billing_after.js
    
    # バンドルサイズを記録
    local size_after=$(wc -c < /tmp/bundle-analysis/billing_after.js)
    echo "Bundle size after import: $size_after bytes"
    
    # サイズ比較
    local size_diff=$((size_after - size_before))
    echo "Size difference: $size_diff bytes"
    echo
    
    # バンドル内容の詳細分析
    echo "=== Bundle Content Analysis (After Import) ==="
    echo "Searching for notification-related code:"
    if grep -i "notification\|sns" /tmp/bundle-analysis/billing_after.js; then
        warning "Found notification-related code in bundle"
        echo
        echo "Notification-related lines:"
        grep -n -i "notification\|sns" /tmp/bundle-analysis/billing_after.js | head -10
    else
        success "No notification-related code found - Tree shaking worked!"
    fi
    echo
    
    # バンドルの差分確認
    echo "=== Bundle Diff Analysis ==="
    if diff /tmp/bundle-analysis/billing_before.js /tmp/bundle-analysis/billing_after.js > /tmp/bundle-analysis/bundle_diff.txt; then
        success "Bundles are identical - Perfect tree shaking!"
        echo "No differences found between before and after bundles"
    else
        warning "Bundles differ - analyzing differences..."
        echo "Number of different lines: $(wc -l < /tmp/bundle-analysis/bundle_diff.txt)"
        echo
        echo "Sample differences (first 20 lines):"
        head -20 /tmp/bundle-analysis/bundle_diff.txt
    fi
    echo
}

# 副作用のあるコードで実験
test_with_side_effects() {
    log "Testing with explicit side effects..."
    
    # notification-service に明確な副作用を追加
    local file="src/services/notification-service.ts"
    cp "$file" "${file}.backup"
    
    # ファイルの先頭に副作用を追加
    sed -i.tmp '1i\
// EXPLICIT SIDE EFFECT FOR TESTING\
console.log("NOTIFICATION SERVICE LOADED - THIS IS A SIDE EFFECT");\
const GLOBAL_COUNTER = Math.random();
' "$file"
    rm "${file}.tmp" 2>/dev/null || true
    
    echo "Added explicit side effects to notification-service.ts"
    echo "Side effects added:"
    head -3 "$file"
    echo
    
    # 再度バンドル
    echo "Building with explicit side effects..."
    npx esbuild src/lambda/billing-processor/index.ts \
        --bundle \
        --platform=node \
        --target=node20 \
        --external:@aws-sdk/* \
        --external:aws-sdk \
        --tree-shaking=true \
        --minify=false \
        --sourcemap=false \
        --outfile=/tmp/bundle-analysis/billing_side_effects.js
    
    local size_side_effects=$(wc -c < /tmp/bundle-analysis/billing_side_effects.js)
    echo "Bundle size with side effects: $size_side_effects bytes"
    
    # 副作用のあるコードが含まれるかチェック
    echo
    echo "=== Side Effects Analysis ==="
    if grep -i "NOTIFICATION SERVICE LOADED\|GLOBAL_COUNTER" /tmp/bundle-analysis/billing_side_effects.js; then
        warning "Side effects found in bundle - tree shaking failed as expected"
    else
        error "Side effects not found - unexpected behavior!"
    fi
}

# CDK の実際のバンドル生成を確認
analyze_cdk_bundle() {
    log "Analyzing CDK's actual bundle generation..."
    
    # CDK のバンドル出力ディレクトリを確認
    if [ -d "cdk.out" ]; then
        echo "CDK output directory contents:"
        find cdk.out -name "*.js" -type f | head -5
        
        # billing-processor のアセットを見つける
        local billing_asset=$(find cdk.out -name "*.js" -exec grep -l "billing-processor\|BillingService" {} \; | head -1)
        if [ -n "$billing_asset" ]; then
            echo
            echo "Found billing-processor asset: $billing_asset"
            local cdk_size=$(wc -c < "$billing_asset")
            echo "CDK bundle size: $cdk_size bytes"
            
            # CDK バンドルでもnotification関連を検索
            echo
            echo "CDK bundle notification analysis:"
            if grep -i "notification\|sns" "$billing_asset"; then
                warning "Notification code found in CDK bundle"
            else
                success "No notification code in CDK bundle"
            fi
        else
            warning "Could not find billing-processor asset in CDK output"
        fi
    else
        warning "CDK output directory not found. Run 'cdk synth' first."
    fi
}

# ファイル復元
restore_files() {
    log "Restoring original files..."
    
    for file in src/lambda/billing-processor/index.ts src/services/notification-service.ts; do
        if [ -f "${file}.backup" ]; then
            mv "${file}.backup" "$file"
            echo "  Restored $file"
        fi
    done
    
    success "Original files restored"
}

# メイン処理
main() {
    echo "Analyzing bundle content to understand tree shaking behavior"
    echo "This will help explain why Hash didn't change despite import addition"
    echo "Timestamp: $(date)"
    echo
    
    # Step 1: 現在の状態でバンドル分析
    analyze_direct_bundle
    
    # Step 2: import文追加後の分析
    test_with_import
    
    # Step 3: 明確な副作用での実験
    read -p "Test with explicit side effects? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        test_with_side_effects
    fi
    
    # Step 4: CDK の実際のバンドルを確認
    analyze_cdk_bundle
    
    # 結果サマリー
    echo
    echo "=== Analysis Summary ==="
    if [ -f "/tmp/bundle-analysis/billing_before.js" ] && [ -f "/tmp/bundle-analysis/billing_after.js" ]; then
        local size_before=$(wc -c < /tmp/bundle-analysis/billing_before.js)
        local size_after=$(wc -c < /tmp/bundle-analysis/billing_after.js)
        local size_diff=$((size_after - size_before))
        
        echo "Direct esbuild results:"
        echo "  Before import: $size_before bytes"
        echo "  After import: $size_after bytes"
        echo "  Difference: $size_diff bytes"
        
        if [ "$size_diff" -eq 0 ]; then
            success "Tree shaking completely eliminated unused imports!"
            echo "  → This explains why CDK Hash didn't change"
            echo "  → esbuild generated identical output"
        else
            warning "Bundle size changed - tree shaking was not perfect"
            echo "  → This should have caused CDK Hash to change"
        fi
    fi
    
    echo
    echo "Files saved to /tmp/bundle-analysis/ for further inspection"
    
    # クリーンアップ
    read -p "Restore original files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        restore_files
    fi
}

# メイン処理実行
main