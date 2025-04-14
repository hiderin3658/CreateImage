# CreateImageAWS

An iOS application demonstrating image generation using AWS Bedrock's Nova Canvas model.

## Features

- Generate images from text prompts using the Nova Canvas model.
- Adjust various generation parameters:
    - Prompt
    - Style Preset (e.g., photorealistic, digital-art, cinematic)
    - Image Size (currently supports 1024x1024)
    - Prompt Adherence (CFG Scale)
    - Steps
    - Seed
- Display the generated image.
- Save the generated image to the photo library.
- Share the generated image.
- Basic error handling and display.
- UI implemented with SwiftUI.

## Prerequisites

- Xcode 15 or later
- An AWS account
- Configured AWS credentials (Cognito Identity Pool recommended)
- Access granted to the Nova Canvas model in the AWS Bedrock console for your chosen region.

## Setup

1.  **Clone the repository:**
    ```bash
    git clone <repository-url>
    cd CreateImageAWS
    ```
2.  **Configure AWS Credentials:**
    - Open the Xcode project.
    - Locate the `AWSCredentials.swift` file.
    - Replace the placeholder value for `identityPoolId` with your Cognito Identity Pool ID.
    - Ensure the `cognitoRegion` and `bedrockRegion` are set correctly (e.g., "us-east-1").
3.  **Configure IAM Role:**
    - Ensure the IAM role associated with your Cognito Identity Pool (specifically the unauthenticated role) has the necessary permissions to invoke the Nova Canvas Bedrock model. The required action is `bedrock:InvokeModel` with the resource ARN for the Nova Canvas model (e.g., `arn:aws:bedrock:us-east-1::foundation-model/amazon.nova-canvas-v1`).
    - Make sure the IAM role's trust policy allows assumption by `cognito-identity.amazonaws.com` for your specific Identity Pool ID and for `unauthenticated` identities.
4.  **Enable Bedrock Model Access:**
    - In the AWS Management Console, navigate to the Bedrock service.
    - Go to "Model access".
    - Ensure you have requested and been granted access to the "Nova Canvas" model in the AWS region you are using.
5.  **Build and Run:**
    - Open the `CreateImageAWS.xcodeproj` file in Xcode.
    - Select a target simulator or device.
    - Build and run the application (Cmd+R).

## Usage

1.  Enter a text prompt describing the image you want to generate.
2.  Optionally, select a "Style Preset".
3.  Optionally, adjust advanced settings like CFG Scale, Steps, and Seed.
4.  Tap "Generate Image".
5.  View the generated image.
6.  Use the "Save to Photos" or "Share" buttons as needed.

## Architecture

-   **SwiftUI:** Used for the user interface.
-   **MVVM (Model-View-ViewModel):**
    -   `ImageGeneratorView` (View)
    -   `ImageGeneratorViewModel` (ViewModel): Manages UI state and interacts with `AWSManager`.
    -   (Model part is implicitly handled by the data structures and AWS responses)
-   **AWSManager:** Singleton class responsible for interacting with the AWS Bedrock API using direct HTTPS requests and SigV4 signing. It handles authentication via Cognito Identity Pool.
-   **AWSCredentials:** Struct holding AWS configuration details (Identity Pool ID, regions).
-   **AWSSigner:** Helper class for generating SigV4 signatures.

## Future Improvements

- Add support for negative prompts if supported by Nova Canvas.
- Implement more robust error handling and user feedback.
- Add more parameter controls (e.g., sampler selection if applicable).
- Support different aspect ratios/image sizes supported by Nova Canvas.
- Improve UI/UX.
- Consider using the official AWS SDK for Swift instead of manual SigV4 signing for better maintainability (once Bedrock support is mature).

## License

[Your chosen license]

## Acknowledgements

- AWS SDK for Swift
- Amazon Titan Image Generator
- [Any other acknowledgements] 