#!/bin/bash

# レイヤー構築スクリプト
# 外部モジュールを含む共有レイヤーを作成

set -e

echo "Building shared dependencies layer..."

# レイヤーディレクトリの準備
LAYER_DIR="layers/shared-dependencies/nodejs"
rm -rf $LAYER_DIR
mkdir -p $LAYER_DIR

# package.json の作成
cat > $LAYER_DIR/package.json << 'EOF'
{
  "name": "shared-dependencies",
  "version": "1.0.0",
  "description": "Shared dependencies for Lambda functions",
  "private": true,
  "dependencies": {
    "lodash": "^4.17.21",
    "date-fns": "^3.0.0",
    "dynamoose": "^3.2.0"
  }
}
EOF

# 依存関係のインストール
cd $LAYER_DIR
npm install --production

# 不要なファイルの削除
echo "Cleaning up unnecessary files..."
find . -name "*.md" -o -name "*.txt" -o -name ".git*" -o -name "*.map" -o -name "test" -o -name "tests" -o -name "example" -o -name "examples" | xargs rm -rf

# レイヤーのサイズを確認
echo "Layer size:"
du -sh .

echo "Layer build completed!"

# レイヤー用のpackage.jsonをルートに保存（CDKで参照用）
cd ../../../
cp layers/shared-dependencies/nodejs/package.json layers/shared-dependencies/package.json

echo "Build script completed successfully!"