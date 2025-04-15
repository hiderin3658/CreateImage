# API Gateway + Lambda 経由での Bedrock 利用: 設定と問題点のまとめ

## 1. 目標

iOS アプリケーションから API Gateway と AWS Lambda を介して AWS Bedrock の画像生成モデル (`amazon.nova-canvas-v1:0`) を利用し、テキストプロンプトに基づいた画像生成を行う。

## 2. 新しいアーキテクチャ

1.  **iOS アプリ:** Cognito Identity Pool で一時認証情報を取得し、それを使用して API Gateway のエンドポイント (`/generateImage`) を呼び出す。
2.  **API Gateway:** IAM 認証を有効にし、リクエストを受け付けると Lambda 関数をトリガーする。
3.  **Lambda 関数 (Python):** API Gateway からプロンプト等を受け取り、自身の実行ロールの権限で Bedrock API (`InvokeModel`) を呼び出し、結果 (Base64画像) を返す。

## 3. 設定状況の詳細 (変更後)

以下は、関連するAWSリソースの設定状況の概要です。

**1. IAMロール (Cognito 未認証ユーザー用)**

*   **ロール名:** (例: `CognitoUnauthBedrockRole`)
*   **信頼ポリシー:** 以前と同様 (Cognito Identity Pool からの `sts:AssumeRoleWithWebIdentity` を許可、正しい Pool ID と `amr: unauthenticated` を Condition で指定)。
*   **許可ポリシー:**
    *   **必要な権限:** `execute-api:Invoke`
    *   **対象リソース:** 作成した API Gateway の Invoke ARN (例: `arn:aws:execute-api:ap-northeast-1:ACCOUNT_ID:API_ID/*/POST/generateImage`)
    *   **不要な権限:** `bedrock:InvokeModel` は削除。

**2. IAM ロール (Lambda 実行用)**

*   **ロール名:** (例: `BedrockInvokeLambdaRole`)
*   **信頼ポリシー:** Lambda サービス (`lambda.amazonaws.com`) からの `sts:AssumeRole` を許可。
*   **許可ポリシー:**
    *   **必要な権限:** `bedrock:InvokeModel`
    *   **対象リソース:** 使用する Bedrock モデルの ARN (`arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.nova-canvas-v1:0`)
    *   **必要な権限:** CloudWatch Logs への書き込み権限 (`logs:CreateLogGroup`, `logs:CreateLogStream`, `logs:PutLogEvents`)

**3. Cognito Identity Pool**

*   **ID プール名:** (例: `NovaCanvasAppPool`)
*   **リージョン:** `ap-northeast-1`
*   **未認証アクセス:** 有効化済み。
*   **未認証ロール:** 上記 **1.** の IAM ロール (`CognitoUnauthBedrockRole`) が設定されていることを確認済み。

**4. Lambda 関数**

*   **ランタイム:** Python (例: 3.11)
*   **コード:** API Gateway からのリクエストを処理し、Boto3 を使用して Bedrock API を呼び出し、Base64 エンコードされた画像を返す。
*   **実行ロール:** 上記 **2.** の IAM ロール (`BedrockInvokeLambdaRole`) を設定。
*   **環境変数:** `AWS_REGION` (`ap-northeast-1`), `BEDROCK_MODEL_ID` (`amazon.nova-canvas-v1:0`) を設定 (推奨)。
*   **タイムアウト/メモリ:** 適切に設定。

**5. API Gateway**

*   **API タイプ:** REST API
*   **エンドポイント:** `/generateImage` (POST メソッド)
*   **認証:** AWS_IAM
*   **統合:** Lambda プロキシ統合で上記 **4.** の Lambda 関数を指定。
*   **デプロイ:** ステージにデプロイし、**呼び出し URL** を取得。

**6. Bedrock モデルアクセス**

*   リージョン `ap-northeast-1` で、使用する Bedrock モデル (`amazon.nova-canvas-v1:0`) へのアクセス権が付与されていることを確認済み。

**7. アプリケーションコード (`AWSManager.swift`)**

*   Cognito ID プール ID、リージョンを設定済み。
*   **API Gateway 呼び出し URL** を `AWSCredentials.swift` に設定済み。
*   `invokeApiGateway` メソッドで API Gateway エンドポイントを呼び出し、SigV4 署名 (Service: `execute-api`) を行っている。
*   Lambda から返される Base64 画像データを処理。

## 4. 移行後の想定される問題とデバッグポイント

*   **iOS -> API Gateway:**
    *   403 Forbidden (SigV4 署名エラー): `AWSSigner` の実装 (特に Service='execute-api', Canonical URI/Query) を確認。
    *   403 Forbidden (IAM 権限エラー): Cognito IAM Role (`CognitoUnauthBedrockRole`) に `execute-api:Invoke` 権限が正しく付与されているか、リソース ARN が正しいか確認。
    *   404 Not Found: API Gateway のエンドポイント URL、パス、デプロイステージが正しいか確認。
    *   5xx Server Error: API Gateway -> Lambda 間の統合設定、マッピングテンプレート (プロキシ統合なら不要) を確認。
*   **API Gateway -> Lambda:**
    *   Lambda 実行ログ (CloudWatch Logs) を確認。
    *   Lambda のトリガー設定、権限を確認。
*   **Lambda -> Bedrock:**
    *   Lambda 実行ログを確認。
    *   Lambda 実行ロール (`BedrockInvokeLambdaRole`) に `bedrock:InvokeModel` 権限が正しく付与されているか確認。
    *   Bedrock API リクエストのパラメータ形式が正しいか確認。
    *   Bedrock モデルアクセスが有効か確認。
*   **Lambda -> API Gateway / iOS:**
    *   Lambda のレスポンス形式が API Gateway (プロキシ統合) の期待する形式になっているか確認 (statusCode, headers, body)。
    *   Base64 エンコード/デコード処理が正しいか確認。

## 5. 現在の状況

アーキテクチャ変更を実施中。iOS アプリコード、Lambda 関数コードを実装・修正。AWS リソース (Lambda 実行ロール、Lambda 関数、API Gateway) の作成と設定、および Cognito IAM Role の権限更新が必要。 