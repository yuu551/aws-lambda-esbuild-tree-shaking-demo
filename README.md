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
| `--packages: external` | 1,087 bytes | 98.3% 削減（レイヤー使用） |
| Tree shaking のみ | 8,044 bytes | 87.5% 削減（レイヤーなし） |

## 🔍 レイヤー使用 vs レイヤーなしの詳細解説

### Lambda レイヤーとは？
Lambda レイヤーは、複数の Lambda 関数で共有できるライブラリやランタイムコードを含む ZIP アーカイブです。外部依存関係（node_modules）を Lambda 関数本体から分離し、再利用可能にします。

### レイヤー使用パターン（`--packages: external`）

#### 仕組み
```typescript
// CDK での設定例
bundling: {
  esbuildArgs: { '--packages': 'external' },  // 全ての外部パッケージをバンドルから除外
  externalModules: ['@aws-sdk/*'],           // AWS SDK も除外（ランタイムに含まれる）
}
```

#### 実際の構成
```
Lambda 関数パッケージ:
├── index.js (1,087 bytes)    # 自作コードのみ
└── （外部モジュールは含まれない）

Lambda レイヤー:
└── nodejs/
    └── node_modules/
        ├── lodash/           # 共有ライブラリ
        ├── date-fns/         # 共有ライブラリ
        └── dynamoose/        # 共有ライブラリ
```

#### メリット
- **デプロイサイズ削減**: 各 Lambda 関数は 1KB 程度に
- **デプロイ速度向上**: アップロードするコードが小さい
- **共有による効率化**: 複数の関数で同じライブラリを再利用
- **コールドスタート改善**: 関数本体が軽量

#### デメリット
- **レイヤー管理の複雑さ**: バージョン管理が必要
- **デプロイ順序の考慮**: レイヤーを先にデプロイ
- **サイズ制限**: レイヤーは最大 5 個、合計 250MB まで

### レイヤーなしパターン（Tree shaking のみ）

#### 仕組み
```typescript
// CDK での設定例
bundling: {
  externalModules: ['@aws-sdk/*'],  // AWS SDK のみ除外
  esbuildArgs: {
    '--tree-shaking': 'true',      // 未使用コードを削除
    '--minify': true,              // コードを最小化
  }
}
```

#### 実際の構成
```
Lambda 関数パッケージ:
├── index.js (8,044 bytes)    # 自作コード + 使用している外部モジュールのみ
└── （未使用のモジュールは tree shaking で除外）
```

#### メリット
- **シンプルな構成**: レイヤー管理不要
- **独立性**: 各関数が必要なものだけを含む
- **バージョン管理が容易**: package.json で完結

#### デメリット
- **デプロイサイズ増加**: 各関数に依存関係が含まれる
- **重複**: 同じライブラリが複数の関数に含まれる可能性

### 実例：billing-processor の場合

```typescript
// src/lambda/billing-processor/index.ts
import { BillingService } from '../../services/billing-service';
// notification-service は import していない！

export const handler = async (event: any) => {
  const billingService = new BillingService();
  // 請求処理のみ実行
};
```

**Tree shaking の効果**:
- `notification-service.ts` とその依存関係（SNS クライアント等）は含まれない
- `billing-service.ts` と必要な依存関係のみバンドルされる
- 結果: 8KB の軽量な関数に

### どちらを選ぶべきか？

| 状況 | 推奨パターン | 理由 |
|------|------------|------|
| 大規模プロジェクト（10+ 関数） | レイヤー使用 | 共有効率が高い |
| 小規模プロジェクト（〜5 関数） | レイヤーなし | 管理がシンプル |
| 頻繁なデプロイ | レイヤー使用 | デプロイ時間短縮 |
| 関数ごとに依存関係が異なる | レイヤーなし | 柔軟性が高い |
| マイクロサービス | レイヤーなし | 独立性を保てる |

## 📈 実際のデプロイ結果と詳細分析

### デプロイされる Lambda 関数一覧

| 関数名 | 実際のサイズ | メモリ | 説明 |
|--------|-------------|--------|------|
| `sample-function-a-all-external` | **1,087 bytes** | 512 MB | 全外部モジュール除外（レイヤー使用） |
| `sample-function-a-specific-external` | **1,087 bytes** | 512 MB | 特定モジュール除外（レイヤー使用） |
| `sample-billing-processor-optimized` | **8,044 bytes** | 256 MB | Tree shaking のみ（レイヤーなし） |
| `sample-function-b-with-layer` | **1,138 bytes** | 512 MB | 通知機能付き（レイヤー使用） |
| `sample-function-a-no-optimization` | **64,802 bytes** | 512 MB | 最適化なし（ベースライン） |
| `sample-function-a-full-bundle` | **64,802 bytes** | 512 MB | 全てバンドル（最悪ケース） |
| `sample-function-a-without-aws-sdk-exclusion` | **TBD** | 512 MB | @aws-sdk/* 除外なし（検証用） |

### 🎯 Tree Shaking の依存性分離効果

#### 実証実験: notification-service.ts を変更した場合

```bash
# オプション1を選択して、notification-service.tsに処理追加 & デプロイ影響分析
npm run test-dependency-isolation
```

**結果:**
```
=== Deployment Impact Analysis ===
Function                            Changed
sample-billing-processor-optimized  No     ✅ Tree shaking が効いている！
sample-function-b-with-layer        Yes    ✅ 期待通り（通知機能を使用）
sample-function-a-all-external      No     ✅ 影響なし
```

### 💡 何がデプロイされるのか？

#### 1. レイヤー使用時（1,087 bytes の関数）

**Lambda 関数パッケージの中身:**
```javascript
// index.js (バンドル後)
// 自作コードのみが含まれる
import { handler } from './handler';
import { validateInput } from './utils';
// 外部ライブラリ（lodash, date-fns）への参照はあるが、
// 実体はレイヤーから読み込まれる
```

**Lambda レイヤーの中身:**
```
SharedDependenciesLayer/
└── nodejs/
    └── node_modules/
        ├── lodash/          (600KB)
        ├── date-fns/        (350KB)
        └── dynamoose/       (450KB)
        合計: 約1.4MB
```

#### 2. Tree Shaking のみ（8,044 bytes の関数）

**Lambda 関数パッケージの中身:**
```javascript
// index.js (バンドル後)
// 自作コード + 実際に使用している部分のみ
import { format } from 'date-fns';  // 使用する関数のみ含まれる
import { get } from 'lodash';       // 使用する関数のみ含まれる
// notification-service は含まれない（import していないため）
```

#### 3. 最適化なし（64,802 bytes の関数）

**Lambda 関数パッケージの中身:**
```javascript
// index.js (バンドル後)
// 全てが含まれる
- 自作コード全て
- lodash 全体 (600KB -> minify後)
- date-fns 全体 (350KB -> minify後)
- 使っていない notification-service も含まれる可能性
```

### 🚀 パフォーマンスへの影響

| メトリクス | レイヤー使用 | Tree Shaking のみ | 最適化なし |
|-----------|------------|----------------|-----------|
| コールドスタート | 最速 (〜200ms) | 速い (〜250ms) | 遅い (〜400ms) |
| デプロイ時間 | 10秒 | 15秒 | 30秒 |
| メモリ使用量 | 最小 | 小 | 大 |
| 管理の複雑さ | 中 | 低 | 最低 |

### 🔧 実装のポイント

1. **レイヤーを使う場合は必ず `--packages: external` を指定**
   ```typescript
   esbuildArgs: { '--packages': 'external' }
   ```

2. **Tree Shaking を最大限活用するには**
   - 名前付きインポートを使用: `import { format } from 'date-fns'`
   - デフォルトインポートを避ける: `import * as _ from 'lodash'` ❌

3. **依存性の変更を追跡するには**
   - CDK のハッシュ値を確認
   - CloudFormation の変更セットを確認

## 🚀 実装パターン

### パターン1: 全外部モジュール除外
```typescript
bundling: {
  esbuildArgs: { '--packages': 'external' },
  externalModules: ['@aws-sdk/*'],
}
```

### パターン2: 特定モジュール除外
```typescript
bundling: {
  externalModules: ['@aws-sdk/*', 'lodash', 'date-fns'],
}
```

### パターン3: Tree shaking 最適化
```typescript
bundling: {
  esbuildArgs: { '--tree-shaking': 'true' },
  externalModules: ['@aws-sdk/*'],
}
```

## 🔬 依存性分離の検証

```bash
# 未参照コード変更による影響範囲テスト
./scripts/test-dependency-isolation.sh

# 結果例:
# billing-processor updated: No ✅
# function-b updated: Yes (expected)
```

Tree shaking により、未参照コードの変更は該当 Lambda の再デプロイを引き起こしません。

## 📦 使用方法

### 前提条件

```bash
# 必要なツール
npm install -g aws-cdk
aws configure  # AWS認証情報設定
```

### デプロイと検証

```bash
# 1. 依存関係インストール
npm install

# 2. 共有レイヤー構築
npm run build-layer

# 3. 統合デプロイ・テスト実行
npm run deploy-and-test

# 4. 依存性分離検証
npm run test-dependency-isolation
```

### クリーンアップ

```bash
npm run cleanup
```

## 🛠 プロジェクト構成
あくまでサンプルコードです。
何も具体的になビジネスロジックなどはありません。

```
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
```

