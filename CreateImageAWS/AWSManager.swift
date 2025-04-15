import Foundation
import AWSCore
import CryptoKit

class AWSManager {
    static let shared = AWSManager()
    
    // 認証情報を別ファイルから参照
    private var cognito_pool_id = AWSCredentials.identityPoolId
    private var cognito_region = AWSCredentials.cognitoRegion
    private var api_gateway_invoke_url = AWSCredentials.apiGatewayInvokeUrl
    
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
    
    // ImageGeneratorViewModelから呼び出されるメソッド
    func generateImage(
        prompt: String,
        stylePreset: String? = nil,
        numberOfImages: Int = 1,
        width: Int = 1024,
        height: Int = 1024,
        cfgScale: Double = 7.0,
        seed: Int = 0,
        steps: Int = 50,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // 内部でAPI Gateway経由のメソッドを呼び出す
        generateImageViaApiGateway(
            prompt: prompt,
            stylePreset: stylePreset,
            numberOfImages: numberOfImages,
            width: width,
            height: height,
            cfgScale: cfgScale,
            seed: seed,
            steps: steps,
            completion: completion
        )
    }
    
    // API Gateway経由で画像生成をリクエストするメソッド
    func generateImageViaApiGateway(
        prompt: String,
        stylePreset: String? = nil,
        numberOfImages: Int = 1,
        width: Int = 1024,
        height: Int = 1024,
        cfgScale: Double = 7.0,
        seed: Int = 0,
        steps: Int = 50,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        // API Gatewayに送信するリクエスト本文を作成
        var requestDict: [String: Any] = [
            "prompt": prompt,
            "numberOfImages": numberOfImages,
            "width": width,
            "height": height,
            "cfgScale": cfgScale,
            "seed": seed,
            "steps": steps
        ]
        if let style = stylePreset, !style.isEmpty {
            requestDict["style_preset"] = style
        }

        invokeApiGateway(endpointPath: AWSCredentials.apiGatewayResourcePath, // AWSCredentialsから参照
                         httpMethod: "POST",
                         requestDict: requestDict,
                         completion: completion)
    }

    // API Gatewayを呼び出す共通メソッド (SigV4署名付き)
    private func invokeApiGateway(
        endpointPath: String, // 例: "/generateImage"
        httpMethod: String,   // 例: "POST"
        requestDict: [String: Any]?,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        guard let credentialsProvider = self.credentialsProvider else {
            print("🔴 AWS認証情報エラー: No credentials provider")
            completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No credentials provider"])))
            return
        }

        // API GatewayのエンドポイントURLを構築
        guard !api_gateway_invoke_url.isEmpty && api_gateway_invoke_url != "YOUR_API_GATEWAY_INVOKE_URL",
              let baseUrl = URL(string: api_gateway_invoke_url),
              let endpointUrl = URL(string: endpointPath, relativeTo: baseUrl) else {
            let errorMsg = api_gateway_invoke_url.isEmpty || api_gateway_invoke_url == "YOUR_API_GATEWAY_INVOKE_URL"
                         ? "API Gateway Invoke URLが設定されていません (AWSCredentials.swiftを確認)"
                         : "無効なAPI Gateway URLまたはパス: Base=\(api_gateway_invoke_url), Path=\(endpointPath)"
            print("🔴 URL構築エラー: \(errorMsg)")
            completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMsg])))
            return
        }

        print("📡 API Gateway 呼び出し準備: URL=\(endpointUrl.absoluteString)")

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

            do {
                var request = URLRequest(url: endpointUrl)
                request.httpMethod = httpMethod
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                if let dict = requestDict {
                    let requestData = try JSONSerialization.data(withJSONObject: dict, options: [])
                    request.httpBody = requestData
                    if let requestString = String(data: requestData, encoding: .utf8) {
                        print("📤 リクエスト本文: \(requestString)")
                    }
                }

                // API Gateway呼び出し用にSigV4署名を適用 (Serviceは 'execute-api')
                // AWSRegionTypeから文字列への変換が必要
                guard let regionString = self.awsRegionTypeToString(self.cognitoRegionToAWSRegionType(region: self.cognito_region)) else {
                     print("🔴 リージョン文字列変換エラー: \(self.cognito_region)")
                     completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to convert region type to string"])))
                     return nil
                }

                let _ = AWSSigner.sign(
                    request: &request,
                    accessKey: credentials.accessKey,
                    secretKey: credentials.secretKey,
                    sessionToken: credentials.sessionKey,
                    region: regionString, // 文字列のリージョンを渡す
                    service: "execute-api", // サービス名を変更
                    date: Date()
                )

                print("📡 API Gateway 呼び出し実行: \(httpMethod) \(endpointUrl.absoluteString)")
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
                    // ... (レスポンスヘッダーのログは省略可)

                    guard let responseData = data else {
                         print("🔴 レスポンスデータがありません")
                         completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "No data in response. Status: \(httpResponse.statusCode)"])))
                         return
                     }

                    if httpResponse.statusCode != 200 {
                        let responseString = String(data: responseData, encoding: .utf8) ?? ""
                        print("🔴 API Gateway エラーレスポンス: \(responseString)")
                        // API Gatewayからのエラーメッセージをラップする
                        let apiError = NSError(
                            domain: "APIGatewayError",
                            code: httpResponse.statusCode,
                            userInfo: [NSLocalizedDescriptionKey: "API Gateway Error (Status: \(httpResponse.statusCode))", "response": responseString]
                        )
                        completion(.failure(apiError))
                        return
                    }

                    // JSONレスポンスをパース
                    do {
                        if let responseString = String(data: responseData, encoding: .utf8) {
                            print("📥 レスポンス本文: \(responseString)")
                        }
                        
                        // API Gateway Lambda Proxyインテグレーションによるレスポンス構造
                        let jsonResponse = try JSONSerialization.jsonObject(with: responseData, options: []) as? [String: Any]
                        
                        // API Gateway Lambdaプロキシ統合ではbodyがJSON文字列としてネストされている
                        if let bodyString = jsonResponse?["body"] as? String {
                            print("📥 ネストされたbody: \(bodyString)")
                            
                            // body文字列を再度JSONとしてパース
                            if let bodyData = bodyString.data(using: .utf8),
                               let bodyJson = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] {
                                
                                // bodyJSONから画像データを抽出
                                if let images = bodyJson["images"] as? [String], let base64Image = images.first {
                                    print("🟢 画像データ受信成功")
                                    if let imageData = Data(base64Encoded: base64Image, options: .ignoreUnknownCharacters) {
                                        print("🟢 Base64デコード成功")
                                        completion(.success(imageData))
                                        return
                                    } else {
                                        print("🔴 Base64デコード失敗: 無効なBase64データ")
                                    }
                                } else {
                                    print("🔴 bodyJSONに画像データが含まれていません")
                                    // bodyJSONの構造をログ出力
                                    print("bodyJSON構造: \(bodyJson)")
                                }
                                
                                // エラー情報の確認
                                if let error = bodyJson["error"] as? String {
                                    print("🔴 Lambda エラー: \(error)")
                                    completion(.failure(NSError(domain: "LambdaError", code: -1, userInfo: [NSLocalizedDescriptionKey: error])))
                                    return
                                }
                            } else {
                                print("🔴 bodyのJSONパース失敗")
                            }
                        } else if let images = jsonResponse?["images"] as? [String], let base64Image = images.first {
                            // 直接レスポンスに画像データが含まれている場合の処理（プロキシなしのケース）
                            print("🟢 直接レスポンスから画像データ受信")
                            if let imageData = Data(base64Encoded: base64Image, options: .ignoreUnknownCharacters) {
                                print("🟢 Base64デコード成功")
                                completion(.success(imageData))
                                return
                            }
                        } else {
                            print("🔴 レスポンスにbodyキーまたは画像データが含まれていません")
                            print("レスポンス構造: \(jsonResponse ?? [:])")
                        }
                        
                        // APIエラー確認
                        if let errorMessage = jsonResponse?["message"] as? String {
                            print("🔴 API Gateway エラー: \(errorMessage)")
                            completion(.failure(NSError(domain: "APIGatewayError", code: -1, userInfo: [NSLocalizedDescriptionKey: errorMessage])))
                            return
                        }
                        
                        // その他のエラー
                        completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response format from API Gateway/Lambda"])))
                    } catch {
                        print("🔴 JSONパースエラー: \(error.localizedDescription)")
                        completion(.failure(NSError(domain: "AWSManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to parse JSON response: \(error.localizedDescription)"])))
                    }
                }
                task.resume()
            } catch {
                print("🔴 リクエスト作成/署名エラー: \(error.localizedDescription)")
                completion(.failure(error))
            }
            return nil
        }
    }
    
    // AWSRegionTypeを文字列に変換するヘルパー (AWSSignerに渡すため)
    private func awsRegionTypeToString(_ regionType: AWSRegionType) -> String? {
         switch regionType {
         case .USEast1: return "us-east-1"
         case .APNortheast1: return "ap-northeast-1"
         // 他の必要なリージョンを追加
         default:
             print("未対応のAWSRegionType: \(regionType)")
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

        // Canonical URI: API Gatewayの場合、ステージ名を含むパスが必要な場合がある
        // URLにステージ名が含まれていることを前提とする
        let canonicalURI = request.url?.path.isEmpty == false ? request.url!.path : "/"
        // API Gatewayでは通常 : のエンコードは不要か、API Gateway側で処理されることが多い
        // let encodedURI = canonicalURI.replacingOccurrences(of: ":", with: "%3A")
        print("🔑 Canonical URI: \(canonicalURI)") // エンコードしない


        let canonicalQueryString = request.url?.query ?? "" // クエリも署名に含める

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