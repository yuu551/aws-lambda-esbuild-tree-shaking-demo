# AWS Lambda esbuild Tree Shaking Demo

  AWS CDK と esbuild を使用した Lambda 関数の最適化パターンを実証するサンプルプロジェクトです。

  ## 🎯 目的

  - `--packages: external` による外部モジュール除外の実装方法
  - Tree shaking による依存性分離効果の検証
  - 複数のバンドリングパターンの性能比較
  - 大規模 Lambda アプリケーションの密結合緩和手法

  ## 📊 検証結果

  | パターン | バンドルサイズ | 説明 |
  |---------|---------------|------|
  | 最適化なし | 64,802 bytes | ベースライン（全モジュール込み） |
  | `--packages: external` | 1,087 bytes | **98.3% 削減**（レイヤー使用） |
  | Tree shaking のみ | 8,044 bytes | 87.5% 削減（レイヤーなし） |

  ## 🚀 実装パターン

  ### パターン1: 全外部モジュール除外
  ```typescript
  bundling: {
    esbuildArgs: { '--packages': 'external' },
    externalModules: ['@aws-sdk/*'],
  }

  パターン2: 特定モジュール除外

  bundling: {
    externalModules: ['@aws-sdk/*', 'lodash', 'date-fns'],
  }

  パターン3: Tree shaking 最適化

  bundling: {
    esbuildArgs: { '--tree-shaking': 'true' },
    externalModules: ['@aws-sdk/*'],
  }

  🔬 依存性分離の検証

  # 未参照コード変更による影響範囲テスト
  ./scripts/test-dependency-isolation.sh

  # 結果例:
  # billing-processor updated: No ✅
  # function-b updated: Yes (expected)

  Tree shaking により、未参照コードの変更は該当 Lambda の再デプロイを引き起こしません。

  📦 使用方法

  前提条件

  # 必要なツール
  npm install -g aws-cdk
  aws configure  # AWS認証情報設定

  デプロイと検証

  # 1. 依存関係インストール
  npm install

  # 2. 共有レイヤー構築
  npm run build-layer

  # 3. 統合デプロイ・テスト実行
  npm run deploy-and-test

  # 4. 依存性分離検証
  npm run test-dependency-isolation

  クリーンアップ

  npm run cleanup

  🛠 プロジェクト構成

  ├── src/
  │   ├── lambda/                    # Lambda 関数
  │   │   ├── billing-processor/     # 課金処理（notification-service 未使用）
  │   │   ├── function-a/            # 基本機能テスト用
  │   │   └── function-b/            # 通知機能（notification-service 使用）
  │   ├── services/                  # ビジネスロジック
  │   │   ├── billing-service.ts     # 課金サービス
  │   │   └── notification-service.ts # 通知サービス
  │   └── repositories/              # データアクセス層
  ├── layers/
  │   └── shared-dependencies/       # 共有外部モジュール
  ├── scripts/                       # 検証スクリプト群
  └── lib/                          # CDK スタック定義