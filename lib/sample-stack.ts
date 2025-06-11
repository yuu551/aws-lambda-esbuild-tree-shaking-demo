import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as iam from 'aws-cdk-lib/aws-iam';
import { NodejsFunction } from 'aws-cdk-lib/aws-lambda-nodejs';
import * as path from 'path';

export class SampleStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // DynamoDB テーブルの作成
    const usersTable = new dynamodb.Table(this, 'UsersTable', {
      tableName: 'sample-users-table',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY, // 開発環境用
    });

    const logsTable = new dynamodb.Table(this, 'LogsTable', {
      tableName: 'sample-logs-table',
      partitionKey: { name: 'id', type: dynamodb.AttributeType.STRING },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // SNS トピックの作成
    const notificationTopic = new sns.Topic(this, 'NotificationTopic', {
      topicName: 'sample-notifications',
    });

    // 共有レイヤーの定義
    const sharedDependenciesLayer = new lambda.LayerVersion(this, 'SharedDependenciesLayer', {
      code: lambda.Code.fromAsset(path.join(__dirname, '../layers/shared-dependencies')),
      compatibleRuntimes: [lambda.Runtime.NODEJS_20_X],
      compatibleArchitectures: [lambda.Architecture.ARM_64],
      description: '外部モジュール（lodash, date-fns, dynamoose）を含む共有レイヤー',
    });

    // Lambda 環境変数
    const commonEnv = {
      USERS_TABLE: usersTable.tableName,
      TABLE_NAME: logsTable.tableName,
      NOTIFICATION_TOPIC_ARN: notificationTopic.topicArn,
    };

    // パターン1: 全ての外部パッケージを除外（--packages: external）
    const functionAWithAllExternal = new NodejsFunction(this, 'FunctionAAllExternal', {
      functionName: 'sample-function-a-all-external',
      entry: path.join(__dirname, '../src/lambda/function-a/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      layers: [sharedDependenciesLayer],
      environment: commonEnv,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: {
        esbuildArgs: {
          '--packages': 'external',      // 全ての外部パッケージを除外
          '--tree-shaking': 'true',      // tree shaking を有効化
          '--minify': true,              // コード最小化
          '--target': 'node20',          // ターゲットランタイム
          '--platform': 'node',          // プラットフォーム指定
        },
        // AWS SDK v3 は Lambda ランタイムに含まれているため除外
        externalModules: [
          '@aws-sdk/*',
          'aws-sdk',
        ],
      },
    });

    // パターン2: 特定のモジュールのみ除外
    const functionAWithSpecificExternal = new NodejsFunction(this, 'FunctionASpecificExternal', {
      functionName: 'sample-function-a-specific-external',
      entry: path.join(__dirname, '../src/lambda/function-a/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      layers: [sharedDependenciesLayer],
      environment: commonEnv,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: {
        // 特定のモジュールのみ除外（externalModulesで指定）
        externalModules: [
          '@aws-sdk/*',     // AWS SDK は Lambda ランタイムに含まれる
          'aws-sdk',        // v2も念のため除外
          'lodash',         // レイヤーに配置
          'date-fns',       // レイヤーに配置
          'dynamoose',      // レイヤーに配置（使用していないが例として）
        ],
        esbuildArgs: {
          '--tree-shaking': 'true',
          '--minify': true,
          '--target': 'node20',
          '--platform': 'node',
        },
      },
    });

    // パターン3: Tree Shaking のみ（バンドルサイズ最適化）
    const billingProcessorOptimized = new NodejsFunction(this, 'BillingProcessorOptimized', {
      functionName: 'sample-billing-processor-optimized',
      entry: path.join(__dirname, '../src/lambda/billing-processor/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      environment: commonEnv,
      timeout: cdk.Duration.seconds(30),
      memorySize: 256, // 請求処理は軽量なので少なめに設定
      bundling: {
        // 外部モジュールもバンドルに含める（レイヤー不要）
        externalModules: [
          '@aws-sdk/*',     // AWS SDK のみ除外
          'aws-sdk',
        ],
        esbuildArgs: {
          '--tree-shaking': 'true',      // 未使用コードの除去
          '--minify': true,              // 最小化
          '--target': 'node20',
          '--platform': 'node',
          '--keep-names': 'true',        // デバッグ用（エラー時に関数名を保持）
        },
        // notification-service はimportしていないので、tree shakingで自動的に除外される
      },
    });

    // Function B（通知機能あり）も作成
    const functionBWithLayer = new NodejsFunction(this, 'FunctionBWithLayer', {
      functionName: 'sample-function-b-with-layer',
      entry: path.join(__dirname, '../src/lambda/function-b/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      layers: [sharedDependenciesLayer],
      environment: {
        ...commonEnv,
        TOPIC_ARN: notificationTopic.topicArn,
      },
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: {
        esbuildArgs: {
          '--packages': 'external',
          '--tree-shaking': 'true',
          '--minify': true,
          '--target': 'node20',
          '--platform': 'node',
        },
        externalModules: [
          '@aws-sdk/*',
          'aws-sdk',
        ],
      },
    });

    // パターン4: 最適化なし（比較用ベースライン）
    const functionANoOptimization = new NodejsFunction(this, 'FunctionANoOptimization', {
      functionName: 'sample-function-a-no-optimization',
      entry: path.join(__dirname, '../src/lambda/function-a/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      environment: commonEnv,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: {
        // 最小限の設定のみ（AWS SDKのみ除外）
        externalModules: [
          '@aws-sdk/*',
          'aws-sdk',
        ],
        // esbuildArgs は最小限（minifyやtree-shakingなし）
        esbuildArgs: {
          '--target': 'node20',
          '--platform': 'node',
        },
      },
    });

    // パターン5: 完全に何もしない（全てバンドル）
    const functionAFullBundle = new NodejsFunction(this, 'FunctionAFullBundle', {
      functionName: 'sample-function-a-full-bundle',
      entry: path.join(__dirname, '../src/lambda/function-a/index.ts'),
      runtime: lambda.Runtime.NODEJS_20_X,
      architecture: lambda.Architecture.ARM_64,
      environment: commonEnv,
      timeout: cdk.Duration.seconds(30),
      memorySize: 512,
      bundling: {
        // AWS SDK以外は何も除外しない = 全てバンドル
        externalModules: [
          '@aws-sdk/*',
          'aws-sdk',
        ],
        // 最低限の設定のみ
        esbuildArgs: {
          '--target': 'node20',
          '--platform': 'node',
        },
      },
    });

    // 権限の付与
    usersTable.grantReadWriteData(functionAWithAllExternal);
    usersTable.grantReadWriteData(functionAWithSpecificExternal);
    usersTable.grantReadWriteData(billingProcessorOptimized);
    usersTable.grantReadWriteData(functionBWithLayer);
    usersTable.grantReadWriteData(functionANoOptimization);
    usersTable.grantReadWriteData(functionAFullBundle);
    
    logsTable.grantWriteData(functionAWithAllExternal);
    logsTable.grantWriteData(functionAWithSpecificExternal);
    logsTable.grantWriteData(functionANoOptimization);
    logsTable.grantWriteData(functionAFullBundle);
    
    notificationTopic.grantPublish(functionBWithLayer);

    // バンドルサイズ比較用の出力
    new cdk.CfnOutput(this, 'DeploymentInfo', {
      value: JSON.stringify({
        patterns: {
          allExternal: 'Function A with --packages: external (all external modules in layer)',
          specificExternal: 'Function A with specific external modules',
          treeShakingOnly: 'Billing Processor with tree shaking only (no layer needed)',
          withNotification: 'Function B with notification service',
          noOptimization: 'Function A with no optimization (baseline comparison)',
          fullBundle: 'Function A with full bundle (worst case scenario)',
        },
        expectedSizes: {
          allExternal: '~1KB (with layer)',
          specificExternal: '~1KB (with layer)', 
          treeShakingOnly: '~8KB (no layer)',
          withNotification: '~1KB (with layer)',
          noOptimization: '~15-20KB (no optimization)',
          fullBundle: '~25-30KB (everything bundled)',
        },
        notes: [
          'Run "npm run build-layer" before deploying to create the shared layer',
          'Compare Lambda package sizes in AWS Console after deployment',
          'Check cold start times for each pattern',
          'Pattern 4&5 show the importance of optimization',
        ],
      }, null, 2),
      description: 'Deployment patterns information with baseline comparisons',
    });
  }
}