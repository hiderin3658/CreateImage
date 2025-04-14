# Cognito Identity Pool 未認証ロール設定の問題に関する状況報告

## 問題の概要

iOSアプリケーションからAWS Bedrockの画像生成モデルを呼び出す際に、Cognito Identity Poolを介して一時認証情報を取得しています。**アプリケーションは一時認証情報（アクセスキー、シークレットキー、セッショントークン）の取得には成功しています。** しかし、**取得した認証情報を使用して Bedrock API (`InvokeModel`) を呼び出す段階で 403 Forbidden エラーが発生**し、「User: arn:aws:sts::...:assumed-role/ロール名/CognitoIdentityCredentials is not authorized to perform: bedrock:InvokeModel on resource: モデルARN ...」というエラーメッセージが表示されます。これは、Cognito が引き受けた IAM ロールに必要な権限が付与されていない、または正しく評価されていないことを示唆しています。

以前、AWS CLI で Cognito Identity Pool の `UnauthenticatedRoleArn` が `null` になっている問題が確認されましたが、コンソール UI 上での設定箇所が見つからず、CLI (`set-identity-pool-roles`) で設定を試みても反映されない状況がありました。（この問題が現在の権限エラーと直接関連しているかは不明確ですが、設定プロセスにおける課題の一つです。）

## 設定状況の詳細

以下は、関連するAWSリソースの設定状況の概要です。

**1. IAMロール (未認証ユーザー用)**

*   **ロール名:** (例: `BedrockUnauthRole` や `CognitoUnauthBedrockRole`)
*   **信頼ポリシー:**
    *   プリンシパル: `cognito-identity.amazonaws.com` (Federated)
    *   許可されるアクション: `sts:AssumeRoleWithWebIdentity`
    *   条件 (Condition):
        *   `cognito-identity.amazonaws.com:aud` が、対象のCognito IDプールIDと一致すること (`StringEquals`)。
        *   `cognito-identity.amazonaws.com:amr` が `unauthenticated` であること (`ForAnyValue:StringLike`)。
    *   *信頼関係ポリシーの設定は正しいことを確認済み。*
*   **許可ポリシー (インラインまたはアタッチ):**
    *   許可されるアクション: `bedrock:InvokeModel`
    *   対象リソース: 使用するBedrockモデルのARN (例: `arn:aws:bedrock:ap-northeast-1::foundation-model/amazon.titan-image-generator-v1` など)。
    *   *ポリシー内容、ロールへのアタッチ状況は正しいことを確認済み。IAM Policy Simulator でも Allow となることを確認済み (または、確認したが Deny となり原因不明の場合もある)。*

**2. Cognito Identity Pool**

*   **ID プール名:** (例: `NovaCanvasAppPool`)
*   **リージョン:** `ap-northeast-1` (IAMロール、Bedrockモデルと一貫性あり)
*   **未認証アクセス:** 有効化済み (`AllowUnauthenticatedIdentities` が `true`)。
*   **未認証ロール:** **AWS コンソール上で、上記 IAM ロールが正しく設定されていることを確認済み。**
    *   （過去に CLI で `UnauthenticatedRoleArn` が `null` になる問題があったが、現在はコンソール上で設定済み）

**3. Bedrock モデルアクセス**

*   AWSアカウントレベルで、対象リージョン (`ap-northeast-1`) において、使用するBedrockモデル（例: `amazon.titan-image-generator-v1`）へのアクセス権が付与されていることをコンソールで確認済み。

**4. 操作ユーザーと権限**

*   コンソール/CLI 操作ユーザーは、関連リソースの編集に必要な権限を持っている。

**5. アプリケーションコード**

*   Cognito ID プール ID は、作成されたプールのIDと一致していることを確認済み。
*   リージョン設定 (`ap-northeast-1`) はAWS上の設定と一貫していることを確認済み。
*   SigV4 署名ロジックは修正済みで、署名関連のエラーは解消済み。
*   アプリは Cognito から一時認証情報を正常に取得できているログを確認済み。

## 試したこと

*   IAMロールの許可ポリシーで `Resource` を `"*"` に変更（変化なし、元に戻した）。
*   IAMロール、Cognito IDプールを削除し、再作成。
*   IAMポリシー、Cognito設定変更後の十分な待機（30分以上）。
*   コンソールキャッシュのクリア、別ブラウザでの試行。
*   アプリのクリーンビルド、シミュレーター/デバイスの再起動。
*   IAM Policy Simulator での権限確認。

## 現在の状況と課題

Cognito Identity Pool 経由での一時認証情報の取得は成功している。しかし、その認証情報を用いて Bedrock API (`InvokeModel`) を呼び出すと、403 Forbidden (AccessDeniedException) エラーが発生する。エラーメッセージは、Cognito が引き受けた IAM ロールに `bedrock:InvokeModel` の権限がないことを示している。

IAM ロールの許可ポリシー、信頼ポリシー、Cognito Identity Pool のロール設定、Bedrock モデルアクセス設定、アプリ側のコード（認証情報取得、署名、API 呼び出し）は、すべて正しく構成されているように見える。IAM Policy Simulator でも権限が許可されるはずだが、それでも実際の API 呼び出しではアクセスが拒否されるという矛盾した状況が発生している。

根本的な原因の特定に至っておらず、問題解決が難航している。 