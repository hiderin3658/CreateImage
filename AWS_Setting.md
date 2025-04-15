# AWS設定ガイド

このドキュメントでは、CreateImageAWSアプリケーションで必要なAWSサービスのセットアップ方法について説明します。

## 前提条件

- AWSアカウント
- AWSマネジメントコンソールへのアクセス権限
- AWS CLI（推奨）

## 1. Amazon Cognito Identity Poolの設定

### 1.1 Identity Poolの作成

1. [AWSマネジメントコンソール](https://console.aws.amazon.com/)にログインします
2. リージョンを選択します（例: ap-northeast-1）
3. Amazon Cognitoサービスを検索し、選択します
4. 「Identity Pool」を選択し、「Create Identity Pool」をクリックします
5. 以下の情報を入力します:
   - Identity pool name: `CreateImageAWSIdentityPool`（任意の名前）
   - 「Guest access」セクションで「Enable access to unauthenticated identities」にチェックを入れます
6. 「次へ」をクリックします
7. IAMロール設定画面で:
   - 「Create a new IAM role」を選択
   - Unauthenticated role name: `Cognito_CreateImageAWSUnauth`（任意の名前）
8. 「Create Identity Pool」をクリックします

Identity Poolが作成されたら、Identity Pool IDをメモしておきます（例: `ap-northeast-1:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`）。
このIDは`AWSCredentials.swift`ファイルで使用します。

### 1.2 IAMロールの設定

1. [IAMコンソール](https://console.aws.amazon.com/iam/)に移動します
2. 「ロール」を選択します
3. 作成したロール（例: `Cognito_CreateImageAWSUnauth`）を検索して選択します
4. 「アクセス権限を追加」→「インラインポリシーを作成」を選択します
5. JSON形式を選択し、以下のポリシーを追加します:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": [
                "arn:aws:bedrock:*::foundation-model/amazon.nova-canvas-v1"
            ]
        }
    ]
}
```

6. 「ポリシーの確認」をクリックします
7. ポリシー名を入力（例: `BedrockNovaCanvasAccess`）し、「ポリシーの作成」をクリックします

## 2. AWS Bedrockの設定

### 2.1 Bedrockモデルへのアクセス権限取得

1. [AWS Bedrockコンソール](https://console.aws.amazon.com/bedrock/)に移動します
2. 左側のメニューから「Model access」を選択します
3. 「Manage model access」をクリックします
4. Amazon Nova Canvas v1を探し、チェックボックスを選択します
5. 「Access model」ボタンをクリックします
6. アクセス権限のリクエストが承認されるのを待ちます（通常は即時）

### 2.2 Bedrockモデルの詳細確認

Bedrockのコンソールで「models」セクションを開き、Amazon Nova Canvas v1を選択して、モデルの詳細情報や利用可能なパラメータを確認します。

## 3. Lambda関数とAPI Gateway（オプション）

### 3.1 Lambda関数のデプロイ

1. [AWS Lambdaコンソール](https://console.aws.amazon.com/lambda/)に移動します
2. 「関数の作成」をクリックします
3. 「一から作成」を選択し、以下の情報を入力します:
   - 関数名: `GenerateImageBedrockFunction`
   - ランタイム: Python 3.9（または最新バージョン）
   - アーキテクチャ: x86_64
4. 「関数の作成」をクリックします
5. コードソースセクションで、リポジトリの`lambda_function.py`の内容をコピーして貼り付けます
6. 「デプロイ」をクリックします

### 3.2 Lambda用のIAMポリシー設定

Lambdaが使用するロールに、Bedrockモデルへのアクセス権限を追加します:

1. Lambda関数の「設定」タブから「アクセス権限」を選択します
2. 「ロール名」のリンクをクリックしてIAMコンソールに移動します
3. 「アクセス権限を追加」→「インラインポリシーを作成」を選択します
4. JSON形式で以下のポリシーを追加します:

```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "bedrock:InvokeModel"
            ],
            "Resource": [
                "arn:aws:bedrock:*::foundation-model/amazon.nova-canvas-v1"
            ]
        }
    ]
}
```

5. ポリシー名を入力し、「ポリシーの作成」をクリックします

### 3.3 API Gatewayの設定

1. [API Gatewayコンソール](https://console.aws.amazon.com/apigateway/)に移動します
2. 「APIを作成」→「REST API」→「構築」を選択します
3. 「新しいAPI」を選択し、以下の情報を入力します:
   - API名: `CreateImageAPI`
   - 説明: 任意の説明
   - エンドポイントタイプ: リージョン
4. 「APIの作成」をクリックします
5. 「リソースの作成」をクリックし、以下の情報を入力します:
   - リソース名: `generate-image`
   - リソースパス: `/generate-image`
   - APIGateway CORSを有効化: チェックを入れる
6. 「リソースの作成」をクリックします
7. 作成したリソースを選択し、「メソッドの作成」をクリックします
8. メソッドタイプとして「POST」を選択し、「チェックマーク」をクリックします
9. 以下の情報を入力します:
   - 統合タイプ: Lambda関数
   - Lambda関数: `GenerateImageBedrockFunction`（作成したLambda関数名）
10. 「保存」をクリックします
11. 「アクション」→「APIのデプロイ」を選択します
12. 「デプロイされるステージ」で「新しいステージ」を選択し、ステージ名を入力（例: `dev`）します
13. 「デプロイ」をクリックします

デプロイ後、Invoke URLが表示されます。このURLをメモしておきます（例: `https://xxxxxxxxxx.execute-api.ap-northeast-1.amazonaws.com/dev/generate-image`）。
このURLを`AWSManager.swift`の`apiEndpoint`変数に設定する場合、このURLを使用します。

## 4. シミュレータでのフォトライブラリ権限（iOS開発向け）

Xcodeでプロジェクトを開き、以下の手順で写真ライブラリへのアクセス権限を追加します:

1. プロジェクトファイル（CreateImageAWS.xcodeproj）をクリックします
2. 「Info」タブを選択します
3. 「Custom iOS Target Properties」セクションで「+」をクリックして以下のキーを追加します:
   - `NSPhotoLibraryAddUsageDescription` - 値: "生成画像を写真ライブラリに保存するためにアクセスが必要です"
   - `NSPhotoLibraryUsageDescription` - 値: "生成画像を写真ライブラリに保存するためにアクセスが必要です"

シミュレータでは写真ライブラリへの保存機能に制限があるため、アプリを実機でテストすることをお勧めします。

## トラブルシューティング

### Bedrockモデルアクセスに関する問題

エラーメッセージに「Access Denied」や「権限がありません」などの表示がある場合:

1. Cognitoの未認証ロールに適切なBedrockの権限が付与されているか確認します
2. BedrockコンソールでNova Canvasモデルへのアクセスが承認されているか確認します
3. リージョン設定が一致しているか確認します

### Lambda関数の実行エラー

Lambda実行時のエラーは、AWSマネジメントコンソールのLambdaセクションでCloudWatchログを確認できます。
一般的なエラーとしては以下があります:

1. Bedrockモデルへのアクセス権限の問題
2. リクエスト形式の誤り
3. タイムアウト（Lambda関数のタイムアウト設定を増やす必要がある場合）

### その他のリソース

- [AWS Bedrock公式ドキュメント](https://docs.aws.amazon.com/bedrock/)
- [Amazon Cognito公式ドキュメント](https://docs.aws.amazon.com/cognito/)
- [AWS Lambda公式ドキュメント](https://docs.aws.amazon.com/lambda/) 