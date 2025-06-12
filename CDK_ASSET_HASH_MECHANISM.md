# CDK のアセット・ハッシュメカニズム詳細解説

## 📖 公式ドキュメントからの重要な情報

### CDK のアセット管理の仕組み

AWS CDK の公式ドキュメント「[Assets and the AWS CDK](https://docs.aws.amazon.com/cdk/v2/guide/assets.html)」から：

> **The AWS CDK generates a source hash for assets. This can be used at construction time to determine whether the contents of an asset have changed.**

> **By default, the AWS CDK creates a copy of the asset in the cloud assembly directory, which defaults to `cdk.out`, under the source hash.**

### Lambda 関数のコード管理

「[class AssetCode](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_lambda.AssetCode.html)」の API リファレンスによると、AssetCode は Lambda 関数のローカルディレクトリからのコードを管理し、バンドリング処理を経てアセットとして扱われます。

## 🔄 ハッシュ生成のタイミングとプロセス

### 実際のメカニズム

```bash
# CDK の内部処理フロー
1. esbuild bundling
   └─ src/lambda/billing-processor/ → bundled.js

2. Asset hash generation  
   └─ SHA256(bundled.js) → "a1b2c3d4e5f6..."

3. CloudFormation template generation
   └─ CodeSha256: "a1b2c3d4e5f6..." 

4. Deployment decision
   └─ if (new_hash !== old_hash) deploy()
```

### デプロイ判定ロジック

| 段階 | 処理内容 | 判定基準 |
|------|----------|----------|
| **ソースファイル変更** | TypeScript ファイルの編集 | ❌ 直接的な判定要素ではない |
| **バンドリング実行** | esbuild による最適化・Tree Shaking | ⚙️ 中間処理 |
| **最終バンドル生成** | 最適化済み JavaScript ファイル | ✅ **これがハッシュ計算の対象** |
| **ハッシュ比較** | SHA256 ハッシュの比較 | ✅ **デプロイ判定の決定要素** |

## 🎯 import-only 実験結果の理由

### import 文追加による影響分析

```typescript
// === import 追加前の bundled.js ===
export const handler = async (event) => {
  // billing-service のロジックのみ
  const billingResult = calculateUserBilling(userId, period);
  return { statusCode: 200, body: JSON.stringify(billingResult) };
};

// === import 追加後の bundled.js (Tree Shaking適用後) ===
export const handler = async (event) => {
  // notification-service は使用されていないため除外される
  // billing-service のロジックのみ (前回と同じ内容)
  const billingResult = calculateUserBilling(userId, period);
  return { statusCode: 200, body: JSON.stringify(billingResult) };
};
```

### ハッシュ値の比較結果

```bash
# ハッシュ計算結果
SHA256(bundled_before.js) = "a1b2c3d4e5f6789..."
SHA256(bundled_after.js)  = "a1b2c3d4e5f6789..."  # 同じ値！

# CDK の判定結果
new_hash === old_hash → Lambda 関数の更新なし
```

## 💡 重要なポイント

### CDK が優秀な理由

1. **ソースレベルではなく成果物レベルでの判定**
   - ソースファイルが変更されても、最終的なバンドルが同じなら更新しない
   - 無駄なデプロイを回避

2. **Tree Shaking との組み合わせ**
   - esbuild の Tree Shaking が効果的に動作
   - 未使用コードは最終バンドルに含まれない
   - 結果として同一のハッシュ値が生成される

3. **開発者フレンドリーな設計**
   - import 文のリファクタリングや整理が安全
   - 実際に使用されないコードの追加・削除がデプロイに影響しない

### 実証実験の価値

今回の実験により以下が実証されました：

- ✅ **esbuild の Tree Shaking は期待通りに動作**
- ✅ **CDK のハッシュベース判定は最適化後のコンテンツベース**
- ✅ **副作用のない import は最終バンドルに影響しない**

## 🔬 実験で使用したスクリプト

この知見を得るために以下のテストスクリプトを作成しました：

- `scripts/test-import-only-tree-shaking.sh`: import のみを追加して Tree Shaking の効果をテスト
- `scripts/test-dependency-isolation.sh`: 依存関係の分離効果をテスト
- `scripts/test-bundle-content-analysis.sh`: バンドル内容の詳細分析

## 📚 参考リンク

- [Assets and the AWS CDK](https://docs.aws.amazon.com/cdk/v2/guide/assets.html)
- [class AssetCode · AWS CDK](https://docs.aws.amazon.com/cdk/api/v2/docs/aws-cdk-lib.aws_lambda.AssetCode.html)
- [Cloud assemblies](https://docs.aws.amazon.com/cdk/v2/guide/deploy.html#deploy-how-synth-assemblies)

## 🎯 結論

**CDK は ソースファイルの変更ではなく、バンドル後の最終ファイルのハッシュ でデプロイを判定する**

これにより：
- Tree Shaking で除去されたコードは一切影響しない
- 開発者は安心してコードのリファクタリングや整理を行える
- 無駄なデプロイが回避され、CI/CD の効率が向上する
- 大規模な Lambda アプリケーションでも効率的な開発が可能

この仕組みを理解することで、より効果的な AWS CDK と esbuild を使った Lambda 開発が実現できます。