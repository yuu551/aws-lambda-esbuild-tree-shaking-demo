#!/bin/bash

# 統合デプロイ・テストスクリプト
# レイヤー構築からデプロイ、テストまでを一連で実行

set -e

echo "=== CDK Lambda Bundling Verification Suite ==="
echo "Complete deployment and testing workflow"
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

# 前提条件のチェック
check_prerequisites() {
    log "Checking prerequisites..."
    
    local missing_deps=()
    
    command -v npm >/dev/null 2>&1 || missing_deps+=("npm")
    command -v cdk >/dev/null 2>&1 || missing_deps+=("aws-cdk")
    command -v aws >/dev/null 2>&1 || missing_deps+=("aws-cli")
    command -v jq >/dev/null 2>&1 || missing_deps+=("jq")
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        error "Missing dependencies: ${missing_deps[*]}"
        echo "Please install the missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            echo "  - $dep"
        done
        exit 1
    fi
    
    # AWS認証情報の確認
    if ! aws sts get-caller-identity >/dev/null 2>&1; then
        error "AWS credentials not configured. Run 'aws configure' first."
        exit 1
    fi
    
    success "All prerequisites satisfied"
}

# パッケージの依存関係インストール
install_dependencies() {
    log "Installing package dependencies..."
    
    if [ ! -f "package.json" ]; then
        error "package.json not found. Run this script from the CDK project root."
        exit 1
    fi
    
    npm install
    success "Dependencies installed"
}

# 共有レイヤーの構築
build_layer() {
    log "Building shared dependencies layer..."
    
    if [ ! -f "scripts/build-layer.sh" ]; then
        error "build-layer.sh script not found"
        exit 1
    fi
    
    ./scripts/build-layer.sh
    success "Shared layer built successfully"
}

# CDKのブートストラップ（必要に応じて）
bootstrap_cdk() {
    local region=${AWS_DEFAULT_REGION:-us-east-1}
    local account=$(aws sts get-caller-identity --query Account --output text)
    
    log "Checking CDK bootstrap status..."
    
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$region" >/dev/null 2>&1; then
        warning "CDK not bootstrapped in region $region"
        log "Bootstrapping CDK..."
        cdk bootstrap "aws://$account/$region"
        success "CDK bootstrapped"
    else
        log "CDK already bootstrapped"
    fi
}

# CDKスタックのデプロイ
deploy_stack() {
    log "Deploying CDK stack..."
    
    # CDKの合成
    log "Synthesizing CDK stack..."
    cdk synth
    
    # デプロイ実行
    log "Deploying to AWS..."
    cdk deploy --require-approval never
    
    success "Stack deployed successfully"
}

# デプロイ後の待機
wait_for_deployment() {
    log "Waiting for Lambda functions to be ready..."
    sleep 30
    success "Deployment stabilized"
}

# テスト実行
run_tests() {
    log "Running performance tests..."
    
    if [ ! -f "scripts/test-lambda-functions.sh" ]; then
        error "test-lambda-functions.sh script not found"
        exit 1
    fi
    
    ./scripts/test-lambda-functions.sh
    success "Tests completed"
}

# スタックの削除（オプション）
cleanup_stack() {
    if [ "$1" = "--cleanup" ]; then
        warning "Cleaning up deployed resources..."
        read -p "Are you sure you want to delete the stack? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            cdk destroy --force
            success "Stack destroyed"
        else
            log "Cleanup cancelled"
        fi
    fi
}

# メイン処理
main() {
    local start_time=$(date +%s)
    
    echo "Starting deployment and testing process..."
    echo "Timestamp: $(date)"
    echo
    
    # 各ステップの実行
    check_prerequisites
    install_dependencies
    build_layer
    bootstrap_cdk
    deploy_stack
    wait_for_deployment
    run_tests
    
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo
    echo "=== Summary ==="
    success "All steps completed successfully!"
    echo "Total time: ${duration} seconds"
    echo
    
    echo "What was tested:"
    echo "  ✓ Pattern 1: --packages external (all external modules in layer)"
    echo "  ✓ Pattern 2: Specific external modules only"
    echo "  ✓ Pattern 3: Tree shaking optimization (no layer)"
    echo "  ✓ Performance comparison between patterns"
    echo
    
    echo "Next steps:"
    echo "  1. Check performance results in /tmp/performance_results.csv"
    echo "  2. Review AWS Lambda Console for detailed metrics"
    echo "  3. Monitor CloudWatch for cold start patterns"
    echo
    
    warning "Don't forget to clean up resources when done:"
    echo "  ./scripts/deploy-and-test.sh --cleanup"
}

# ヘルプ表示
if [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
    echo "Usage: $0 [--cleanup] [--help]"
    echo
    echo "Complete CDK Lambda bundling verification workflow:"
    echo "  1. Check prerequisites"
    echo "  2. Install dependencies"
    echo "  3. Build shared layer"
    echo "  4. Bootstrap CDK (if needed)"
    echo "  5. Deploy stack"
    echo "  6. Run performance tests"
    echo
    echo "Options:"
    echo "  --cleanup  Delete the deployed stack after confirmation"
    echo "  --help     Show this help message"
    echo
    echo "Prerequisites:"
    echo "  - Node.js and npm"
    echo "  - AWS CDK CLI"
    echo "  - AWS CLI (configured)"
    echo "  - jq"
    echo
    exit 0
fi

# クリーンアップオプションの処理
cleanup_stack "$1"

# メイン処理実行（クリーンアップ以外の場合）
if [ "$1" != "--cleanup" ]; then
    main
fi