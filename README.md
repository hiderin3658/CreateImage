# CreateImageAWS

AWS BedrockのNova Canvasモデルを使用した画像生成iOSアプリケーション

## 機能概要

- テキストプロンプトを使用してNova Canvasモデルで画像を生成
- 以下の生成パラメータを調整可能：
  - プロンプト
  - スタイルプリセット（photorealistic、digital-art、cinematicなど）
  - 画像サイズ（現在は1024x1024をサポート）
  - プロンプト忠実度（CFG Scale）
  - ステップ数
  - シード値
- 生成された画像の表示
- 生成された画像を写真ライブラリに保存
- 生成された画像の共有
- エラー処理と表示
- SwiftUIによるUI実装

## システム要件

- Xcode 15以降
- AWSアカウント
- 設定済みのAWS認証情報（Cognito Identity Pool推奨）
- 選択したリージョンでAWS Bedrockコンソールでのnova-canvas-v1モデルへのアクセス権

## システム構成

このアプリケーションは以下のコンポーネントで構成されています：

1. **iOS クライアントアプリ**：
   - Swift/SwiftUIで実装されたユーザーインターフェース
   - AWS認証情報の管理
   - AWSサービスとの通信

2. **AWS サービス**：
   - **Amazon Cognito**: 認証管理
   - **AWS Bedrock**: Nova Canvasモデルによる画像生成
   - **AWS Lambda**: 画像生成リクエストの処理（オプション）
   - **Amazon API Gateway**: Lambda関数へのAPIエンドポイント提供（オプション）

## フォルダ構成

```
CreateImageAWS/
├── CreateImageAWS/
│   ├── AWSManager.swift            # AWS通信を担当するクラス
│   ├── AWSCredentials.swift        # AWS認証情報（gitignoreに含めること）
│   ├── AWSCredentials_sample.swift # 認証情報のサンプルファイル
│   ├── ImageGeneratorView.swift    # メイン画面のUI
│   ├── ImageGeneratorViewModel.swift # ビューモデル（ロジック部分）
│   ├── ContentView.swift           # アプリのエントリーポイント
│   ├── CreateImageAWSApp.swift     # アプリケーション定義
│   └── Assets.xcassets/            # 画像リソース
├── CreateImageAWSTests/            # テストコード
├── CreateImageAWSUITests/          # UIテストコード
├── lambda_function.py              # AWS Lambdaの関数コード
└── AWS_Setting.md                  # AWS設定の詳細ガイド
```

## セットアップ手順

1. **リポジトリをクローン：**
   ```bash
   git clone <repository-url>
   cd CreateImageAWS
   ```

2. **AWS認証情報の設定：**
   - `AWSCredentials_sample.swift`ファイルを`AWSCredentials.swift`にコピーします
   ```bash
   cp CreateImageAWS/AWSCredentials_sample.swift CreateImageAWS/AWSCredentials.swift
   ```
   - Xcodeでプロジェクトを開きます
   - `AWSCredentials.swift`ファイルのプレースホルダーを実際の値で置き換えます：
     - `identityPoolId`: CognitoアイデンティティプールID
     - `cognitoRegion`: Cognitoサービスのリージョン
     - `bedrockRegion`: Bedrockサービスのリージョン

3. **AWS設定：**
   - AWS関連の詳細な設定手順については、`AWS_Setting.md`を参照してください
   - このファイルには以下の情報が含まれています：
     - Cognito Identity Poolの作成方法
     - IAMロールの設定方法
     - Bedrockモデルへのアクセス権限の設定
     - Lambda関数のデプロイ方法（オプション）
     - API Gatewayの設定方法（オプション）

4. **ビルドと実行：**
   - XcodeでCreateImageAWS.xcodeprojファイルを開きます
   - ターゲットシミュレータまたはデバイスを選択します
   - アプリケーションをビルドして実行します（Cmd+R）

## 使用方法

1. 生成したい画像を説明するテキストプロンプトを入力
2. 「Generate Image」ボタンをタップ
3. 生成された画像を表示
4. 必要に応じて「Save to Photos」または「Share」ボタンを使用

### シミュレータでの注意

- シミュレータでは、「Save to Photos」機能は動作せず、代わりにアプリのドキュメントディレクトリに画像が保存されます
- 実機で写真ライブラリへの保存機能を使用するには、プロジェクト設定でプライバシー権限を追加する必要があります

## アーキテクチャ

- **SwiftUI:** ユーザーインターフェース
- **MVVM (Model-View-ViewModel):**
  - `ImageGeneratorView` (View)
  - `ImageGeneratorViewModel` (ViewModel): UI状態を管理し、`AWSManager`と相互作用
  - （Modelはデータ構造とAWSレスポンスによって暗黙的に処理）
- **AWSManager:** AWS Bedrock APIとの通信を担当するシングルトンクラス。直接HTTPSリクエストとSigV4署名を使用
- **AWSCredentials:** AWS設定詳細を保持する構造体（Identity Pool ID、リージョンなど）

