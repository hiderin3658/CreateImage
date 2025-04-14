import Foundation
import AWSCore
import CryptoKit

class AWSManager {
    static let shared = AWSManager()
    
    // 認証情報を別ファイルから参照
    private var cognito_pool_id = AWSCredentials.identityPoolId
    private var cognito_region = AWSCredentials.cognitoRegion
    private var bedrock_region = AWSCredentials.bedrockRegion
    
    // Bedrockエンドポイント
    private let bedrockEndpoint = "https://bedrock-runtime.\(AWSCredentials.bedrockRegion).amazonaws.com"
    
    // Nova Canvas モデルID (要確認・修正)
    private let novaCanvasModelId = "amazon.nova-canvas-v1:0" // 仮のID。必要に応じて正しいIDに修正してください。
    
    // AWS認証情報プロバイダー
    private var credentialsProvider: AWSCognitoCredentialsProvider?
    
    private init() {
        setupAWS()
    }
    
    private func setupAWS() {
        // リージョンを設定
        let cognitoRegionType = cognitoRegionToAWSRegionType(region: cognito_region)
        
        // AWS Cognitoクレデンシャルプロバイダーの初期化
        credentialsProvider = AWSCognitoCredentialsProvider(
            regionType: cognitoRegionType,
            identityPoolId: cognito_pool_id
        )
        
        // AWSサービス設定の初期化
        let configuration = AWSServiceConfiguration(
            region: cognitoRegionType,
            credentialsProvider: credentialsProvider
        )
        
        // 設定をAWSサービスマネージャーに登録
        AWSServiceManager.default().defaultServiceConfiguration = configuration
    }
    
    // リージョン文字列をAWSRegionTypeに変換
    private func cognitoRegionToAWSRegionType(region: String) -> AWSRegionType {
        switch region {
        case "us-east-1":
            return .USEast1
        case "ap-northeast-1":
            return .APNortheast1
        // 他のリージョンケースも必要なら追加
        default:
            print("未対応のリージョン: \(region)。デフォルトで ap-northeast-1 を使用します。")
            return .APNortheast1
        }
    }
    
    // Nova Canvas 用の画像生成メソッド
    func generateImage(
        prompt: String,
        stylePreset: String? = nil, // Nova Canvas用のスタイルプリセット (例: "photorealistic")
        numberOfImages: Int = 1,
        width: Int = 1024,
        height: Int = 1024,
        cfgScale: Double = 7.0, // Nova Canvasのデフォルト値に近い可能性
        seed: Int = 0,
        steps: Int = 50, // Nova Canvasのステップ数 (要確認)
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // Nova Canvas用のリクエスト本文を作成 (API仕様に合わせて要調整)
        var textPrompts: [[String: Any]] = [["text": prompt, "weight": 1.0]]
        // ネガティブプロンプトも配列形式の可能性がある
        // let negativePrompts: [[String: Any]] = [["text": negativePrompt, "weight": -1.0]]

        var requestDict: [String: Any] = [
            "text_prompts": textPrompts,
            // "negative_prompts": negativePrompts, // 必要なら追加
            "cfg_scale": cfgScale,
            "seed": seed,
            "steps": steps,
            "width": width,
            "height": height,
            // "samples": numberOfImages, // パラメータ名が違う可能性あり
        ]

        if let style = stylePreset, !style.isEmpty {
            requestDict["style_preset"] = style
        }

        invokeBedrockAPI(modelId: novaCanvasModelId, requestDict: requestDict, completion: completion)
    }

    // --- Titan V2の背景削除機能は削除 ---
    // func removeBackground(...) { ... }

    // Bedrock REST APIを呼び出す共通メソッド (内容は変更なし、エラー処理を維持)
    private func invokeBedrockAPI(
        modelId: String,
        requestDict: [String: Any],
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // ... (既存のAPI呼び出し、署名、エラー処理ロジックはそのまま) ...
        // 注意: このメソッド内のログ出力やエラー処理は現状維持しますが、
        // IAMポリシーエラーのメッセージはNova Canvasモデルへの権限不足を指摘するように調整が必要かもしれません。
        
        guard let credentialsProvider = self.credentialsProvider else {
            print("🔴 AWS認証情報エラー: No credentials provider")
            completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No credentials provider"])))
            return
        }
        
        credentialsProvider.credentials().continueWith { (task) -> Any? in
            if let error = task.error {
                print("🔴 AWS認証情報エラー: \(error.localizedDescription)")
                completion(.failure(error))
                return nil
            }
            
            guard let credentials = task.result else {
                print("🔴 AWS認証情報取得失敗: 結果がnilです")
                completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get AWS credentials"])))
                return nil
            }
            
            let accessKeySuffix = String(credentials.accessKey.suffix(4))
            print("🟢 認証情報取得成功: アクセスキー末尾 \(accessKeySuffix)")
            print("🟢 セッショントークン有無: \(credentials.sessionKey != nil ? "あり" : "なし")")
            
            let urlString = "\(self.bedrockEndpoint)/model/\(modelId)/invoke"
            guard let url = URL(string: urlString) else {
                completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid URL"])))
                return nil
            }
            
            do {
                let requestData = try JSONSerialization.data(withJSONObject: requestDict, options: [])
                if let requestString = String(data: requestData, encoding: .utf8) {
                    print("📤 リクエスト本文: \(requestString)")
                }
                
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = requestData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept") // Acceptも必要か確認
                
                let _ = AWSSigner.sign(
                    request: &request,
                    accessKey: credentials.accessKey,
                    secretKey: credentials.secretKey,
                    sessionToken: credentials.sessionKey,
                    region: self.bedrock_region,
                    service: "bedrock",
                    date: Date()
                )
                
                print("📡 Bedrock API呼び出し: モデル=\(modelId), URL=\(urlString)")
                print("📡 リクエストヘッダー:")
                request.allHTTPHeaderFields?.forEach { key, value in
                    if key == "Authorization" {
                        print("  \(key): AWS4-HMAC-SHA256 Credential=**MASKED**/...")
                    } else {
                        print("  \(key): \(value)")
                    }
                }
                
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        print("🔴 ネットワークエラー: \(error.localizedDescription)")
                        completion(.failure(error))
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        print("🔴 HTTPレスポンスではありません")
                        completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response"])))
                        return
                    }
                    
                    print("📩 HTTPステータスコード: \(httpResponse.statusCode)")
                    print("📩 レスポンスヘッダー:")
                    httpResponse.allHeaderFields.forEach { key, value in
                        print("  \(key): \(value)")
                    }
                    
                    if httpResponse.statusCode != 200 {
                        var errorMessage = "HTTP Error: \(httpResponse.statusCode)"
                        var errorDetails: [String: Any] = [:]
                        if let responseData = data, let responseString = String(data: responseData, encoding: .utf8) {
                            print("🔴 エラーレスポンス: \(responseString)")
                            errorDetails["response"] = responseString
                            if responseString.contains("is not authorized to perform: bedrock:InvokeModel") {
                                let iamError = NSError(
                                    domain: "AWSBedrockError",
                                    code: 403,
                                    userInfo: [
                                        NSLocalizedDescriptionKey: "AWS IAM権限エラー: Bedrockモデルへのアクセス権限がありません",
                                        NSLocalizedRecoverySuggestionErrorKey: "AWSコンソールでIAMポリシーを確認し、'bedrock:InvokeModel'アクションの権限をロールに追加し、Nova CanvasモデルのARNがResourceに含まれているか確認してください。また、BedrockコンソールでNova Canvasモデルアクセスが有効になっているか確認してください。"
                                    ]
                                )
                                completion(.failure(iamError))
                                return
                            }
                        }
                        // 他のエラーコード処理...
                        completion(.failure(NSError(domain: "AWSManager", code: httpResponse.statusCode, userInfo: ["message": errorMessage, "details": errorDetails])))
                        return
                    }
                    
                    guard let responseData = data else {
                        completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data in response"])))
                        return
                    }
                    
                    // Nova Canvasのレスポンス形式に合わせてデコード処理が必要
                    // 例: Base64エンコードされた画像データを取り出す
                    do {
                        guard let responseDict = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any],
                              let artifacts = responseDict["artifacts"] as? [[String: Any]],
                              let firstArtifact = artifacts.first,
                              let base64Image = firstArtifact["base64"] as? String,
                              let imageData = Data(base64Encoded: base64Image) else {
                            print("🔴 レスポンス形式エラー: artifacts または base64 が見つかりません")
                            completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from Nova Canvas"])))
                            return
                        }
                        completion(.success(imageData))
                    } catch {
                        print("🔴 レスポンスJSONパースエラー: \(error.localizedDescription)")
                        completion(.failure(error))
                    }
                }
                task.resume()
            } catch {
                print("🔴 リクエスト作成エラー: \(error.localizedDescription)")
                completion(.failure(error))
            }
            return nil
        }
    }
    
    // Bedrockの設定情報をユーザーに表示するためのヘルパーメソッド
    public func getBedrockConfigInfo() -> [String: Any] {
        return [
            "cognitoPoolId": self.cognito_pool_id,
            "cognitoRegion": self.cognito_region,
            "bedrockRegion": self.bedrock_region,
            "bedrockEndpoint": self.bedrockEndpoint,
            "novaCanvasModelId": self.novaCanvasModelId // Titan IDをNova Canvas IDに変更
            // "titanImageV1": self.titanImageV1, // 削除
            // "titanImageV2": self.titanImageV2  // 削除
        ]
    }
    
    // IAMポリシーの問題をチェックするヘルパーメソッド
    public func checkIAMPolicies(completion: @escaping (Bool, String?) -> Void) {
        guard let credentialsProvider = self.credentialsProvider else {
            completion(false, "認証情報プロバイダーが設定されていません")
            return
        }
        
        credentialsProvider.credentials().continueWith { (task) -> Any? in
            if let error = task.error {
                completion(false, "認証情報の取得に失敗しました: \(error.localizedDescription)")
                return nil
            }
            
            guard let credentials = task.result else {
                completion(false, "認証情報が取得できませんでした")
                return nil
            }
            
            // 認証情報が取得できた場合、簡単なテストリクエストを送信
            let testDict = ["testRequest": true]
            let modelId = self.novaCanvasModelId // Titan IDをNova Canvas IDに変更
            let urlString = "\(self.bedrockEndpoint)/model/\(modelId)/invoke"
            
            guard let url = URL(string: urlString) else {
                completion(false, "無効なURL: \(urlString)")
                return nil
            }
            
            do {
                let requestData = try JSONSerialization.data(withJSONObject: testDict, options: [])
                var request = URLRequest(url: url)
                request.httpMethod = "POST"
                request.httpBody = requestData
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                
                // SigV4署名を適用
                let _ = AWSSigner.sign(
                    request: &request,
                    accessKey: credentials.accessKey,
                    secretKey: credentials.secretKey,
                    sessionToken: credentials.sessionKey,
                    region: self.bedrock_region,
                    service: "bedrock",
                    date: Date()
                )
                
                let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                    if let error = error {
                        completion(false, "ネットワークエラー: \(error.localizedDescription)")
                        return
                    }
                    
                    guard let httpResponse = response as? HTTPURLResponse else {
                        completion(false, "不正なレスポンス")
                        return
                    }
                    
                    // 認証エラーのチェック
                    if httpResponse.statusCode == 403 {
                        if let data = data, let responseString = String(data: data, encoding: .utf8),
                           responseString.contains("is not authorized to perform: bedrock:InvokeModel") {
                            // IAMポリシーの問題を検出
                            completion(false, "IAM権限エラー: bedrock:InvokeModelのアクションが許可されていません。AWSコンソールでIAMポリシーを確認してください。")
                            return
                        }
                        completion(false, "アクセス権限エラー: HTTPステータスコード \(httpResponse.statusCode)")
                        return
                    } else if httpResponse.statusCode == 404 {
                        completion(false, "リソースが見つかりません: モデルIDまたはエンドポイントが正しいか確認してください")
                        return
                    } else if httpResponse.statusCode == 200 {
                        completion(true, nil) // 認証成功
                        return
                    } else {
                        completion(false, "エラー: HTTPステータスコード \(httpResponse.statusCode)")
                        return
                    }
                }
                
                task.resume()
            } catch {
                completion(false, "リクエスト作成エラー: \(error.localizedDescription)")
            }
            
            return nil
        }
    }
}

// AWS SigV4署名を行うヘルパークラス
class AWSSigner {
    static func sign(
        request: inout URLRequest,
        accessKey: String,
        secretKey: String,
        sessionToken: String?,
        region: String,
        service: String,
        date: Date
    ) -> String {
        print("🔑 SigV4署名開始: リージョン=\(region), サービス=\(service)")
        
        // 日時フォーマット
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
        let amzDate = dateFormatter.string(from: date)
        
        let dateStamp = String(amzDate.prefix(8))
        print("🔑 日付スタンプ: \(dateStamp), AMZ日付: \(amzDate)")
        
        // ホストヘッダと必須ヘッダを設定
        guard let host = request.url?.host else {
            print("🔴 エラー: URLからホストを取得できません")
            return "" // またはエラー処理
        }
        request.setValue(host, forHTTPHeaderField: "Host")
        request.setValue(amzDate, forHTTPHeaderField: "X-Amz-Date")
        if let sessionToken = sessionToken {
            request.setValue(sessionToken, forHTTPHeaderField: "X-Amz-Security-Token")
            print("🔑 セッショントークン: 設定済み")
        } else {
            print("🔑 セッショントークン: なし")
        }

        let method = request.httpMethod ?? "GET"

        // Canonical URI: パスの正規化とエンコーディング
        let path = request.url?.path.isEmpty == false ? request.url!.path : "/"
        // SigV4ではパス内のコロン : を %3A にエンコードする必要がある
        // 他の文字は Bedrock API の場合、通常エンコード不要なため、単純置換のみ行う
        let canonicalURI = path.replacingOccurrences(of: ":", with: "%3A")
        print("🔑 Canonical URI: \(canonicalURI)")


        let canonicalQueryString = "" // クエリパラメータがない場合は空文字列

        // Canonical Headers と Signed Headers の作成
        // ヘッダー名を小文字にし、アルファベット順にソート
        let headersToSign = ["content-type", "host", "x-amz-date"]
        if sessionToken != nil {
             // セッショントークンがある場合は x-amz-security-token も署名対象に含める必要があるか確認 (通常は含めない)
             // headersToSign.append("x-amz-security-token")
             // Note: AWS ドキュメントによれば、x-amz-security-token は通常 SignedHeaders に含めません。
        }
        let sortedHeaderKeys = headersToSign.sorted()

        var canonicalHeaders = ""
        for key in sortedHeaderKeys {
            if let value = request.value(forHTTPHeaderField: key) {
                // 値の前後の空白をトリムし、連続する空白を1つにまとめる (今回は単純化)
                let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
                canonicalHeaders += key + ":" + trimmedValue + "\n"
            }
        }
        let signedHeaders = sortedHeaderKeys.joined(separator: ";")

        print("🔑 Canonical Headers:\n\(canonicalHeaders)")
        print("🔑 Signed Headers: \(signedHeaders)")

        // リクエスト本文のハッシュを生成
        let payloadHash = sha256(data: request.httpBody ?? Data())
        print("🔑 ペイロードハッシュ: \(payloadHash)")

        // 正規リクエストの作成
        let canonicalRequest = [
            method,
            canonicalURI,
            canonicalQueryString,
            canonicalHeaders, // 最後に改行が追加されている状態
            signedHeaders,
            payloadHash
        ].joined(separator: "\n")

        // デバッグ用に正規リクエストを出力 (サーバー側の期待値と比較用)
        print("🔑 Canonical Request:\n\(canonicalRequest)")


        let algorithm = "AWS4-HMAC-SHA256"
        let credentialScope = [dateStamp, region, service, "aws4_request"].joined(separator: "/")
        print("🔑 認証情報スコープ: \(credentialScope)")

        // 署名文字列の作成
        let stringToSign = [
            algorithm,
            amzDate,
            credentialScope,
            sha256(string: canonicalRequest) // 正規リクエストのハッシュ
        ].joined(separator: "\n")

        print("🔑 String-To-Sign:\n\(stringToSign)")

        // 署名キーの導出
        let kSecret = "AWS4" + secretKey
        let kDate = hmacSHA256(data: dateStamp, key: kSecret)
        let kRegion = hmacSHA256(data: region, key: kDate)
        let kService = hmacSHA256(data: service, key: kRegion)
        let kSigning = hmacSHA256(data: "aws4_request", key: kService)

        print("🔑 署名キー: 生成完了")

        // 署名の計算
        let signature = hmacSHA256(data: stringToSign, key: kSigning).hexEncodedString()
        print("🔑 最終署名: \(signature)")

        // Authorizationヘッダの設定
        let authorizationHeader = "\(algorithm) Credential=\(accessKey)/\(credentialScope), SignedHeaders=\(signedHeaders), Signature=\(signature)"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")

        return signature
    }
    
    // SHA256ハッシュを計算
    private static func sha256(string: String) -> String {
        return sha256(data: string.data(using: .utf8) ?? Data())
    }
    
    private static func sha256(data: Data) -> String {
        let hashed = SHA256.hash(data: data)
        return hashed.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    // HMAC-SHA256を計算
    private static func hmacSHA256(data: String, key: String) -> Data {
        let keyData = key.data(using: .utf8)!
        let dataToAuthenticate = data.data(using: .utf8)!
        
        let key = SymmetricKey(data: keyData)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: dataToAuthenticate, using: key)
        return Data(authenticationCode)
    }
    
    // リージョンなどの文字列をHMAC処理するためのオーバーロードメソッド
    private static func hmacSHA256(data: String, key: Data) -> Data {
        guard let dataToAuthenticate = data.data(using: .utf8) else {
            return Data()
        }
        
        let key = SymmetricKey(data: key)
        let authenticationCode = HMAC<SHA256>.authenticationCode(for: dataToAuthenticate, using: key)
        return Data(authenticationCode)
    }
}

// Data拡張 - 16進数文字列変換
extension Data {
    func hexEncodedString() -> String {
        return self.map { String(format: "%02hhx", $0) }.joined()
    }
} 