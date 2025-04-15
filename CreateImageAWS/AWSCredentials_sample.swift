import Foundation

struct AWSCredentials {
    // Cognito Identity PoolのID（例: ap-northeast-1:xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx）
    static let identityPoolId = "<YOUR_COGNITO_IDENTITY_POOL_ID>"
    
    // AWSリージョン（例: ap-northeast-1）
    static let cognitoRegion = "<YOUR_COGNITO_REGION>"
    static let bedrockRegion = "<YOUR_BEDROCK_REGION>"

    // API GatewayのエンドポイントURL（例: https://xxxxxx.execute-api.ap-northeast-1.amazonaws.com）
    static let apiGatewayInvokeUrl = "<YOUR_API_GATEWAY_INVOKE_URL>"
    // API Gatewayのリソースパス（例: /dev/generateImage）
    static let apiGatewayResourcePath = "<YOUR_API_GATEWAY_RESOURCE_PATH>"
} 
