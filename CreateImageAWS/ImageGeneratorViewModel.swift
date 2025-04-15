import Foundation
import SwiftUI
import Combine

class ImageGeneratorViewModel: ObservableObject {
    // Published properties for UI updates
    @Published var prompt: String = ""
    @Published var generatedImage: UIImage?
    @Published var isGenerating: Bool = false
    @Published var errorMessage: String?
    
    // Image generation parameters (Nova Canvas用に調整)
    @Published var stylePreset: String = "photorealistic"
    @Published var numberOfImages: Int = 1
    @Published var width: Int = 1024
    @Published var height: Int = 1024
    @Published var cfgScale: Double = 7.0
    @Published var seed: Int = 0
    @Published var steps: Int = 50
    
    // AWS Manager instance
    private let awsManager = AWSManager.shared
    
    // Generate an image based on the current parameters
    func generateImage() {
        isGenerating = true
        errorMessage = nil
        
        awsManager.generateImage(
            prompt: prompt,
            stylePreset: stylePreset.isEmpty ? nil : stylePreset,
            numberOfImages: numberOfImages,
            width: width,
            height: height,
            cfgScale: cfgScale,
            seed: seed,
            steps: steps
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.isGenerating = false
                
                switch result {
                case .success(let imageData):
                    if let image = UIImage(data: imageData) {
                        self.generatedImage = image
                    } else {
                        self.errorMessage = "Failed to create image from data"
                    }
                case .failure(let error):
                    if let awsError = error as? NSError {
                        if awsError.domain == "AWSBedrockError" && awsError.code == 403 {
                            self.errorMessage = awsError.localizedDescription
                            print("�� IAM権限エラーが検出されました")
                            print("AWSコンソールでIAMポリシーとBedrockモデルアクセスを確認してください。")
                        } else if let message = awsError.userInfo["message"] as? String {
                            self.errorMessage = message
                        } else {
                            self.errorMessage = "Error: \(error.localizedDescription)"
                        }
                    } else {
                        self.errorMessage = "Error: \(error.localizedDescription)"
                    }
                }
            }
        }
    }
    
    // Save generated image to photo library
    func saveImage() {
        guard let image = generatedImage else {
            self.errorMessage = "No image to save"
            return
        }
        
        // シミュレータでは写真保存が機能しない場合がある
        #if targetEnvironment(simulator)
        // シミュレータでは一時的にファイルとして保存する代替手段を提供
        if let data = image.pngData(), let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
            let fileURL = directory.appendingPathComponent("generated_image_\(Date().timeIntervalSince1970).png")
            do {
                try data.write(to: fileURL)
                self.errorMessage = "画像をシミュレータ内に保存しました: \(fileURL.path)"
                print("画像をシミュレータ内に保存しました: \(fileURL.path)")
            } catch {
                self.errorMessage = "シミュレータでの保存エラー: \(error.localizedDescription)"
            }
            return
        }
        #endif
        
        // 実機では通常の写真ライブラリへの保存を試みる
        UIImageWriteToSavedPhotosAlbum(image, self, #selector(image(_:didFinishSavingWithError:contextInfo:)), nil)
    }
    
    // Callback for image saving
    @objc func image(_ image: UIImage, didFinishSavingWithError error: Error?, contextInfo: UnsafeRawPointer) {
        if let error = error {
            // 写真ライブラリへのアクセス権限がない場合の特定のエラー処理
            let nsError = error as NSError
            if nsError.domain == "ALAssetsLibraryErrorDomain" && (nsError.code == -3310 || nsError.code == -3311) {
                self.errorMessage = "写真へのアクセス権限がありません。設定アプリから権限を許可してください。"
            } else {
                self.errorMessage = "Error saving image: \(error.localizedDescription)"
            }
        } else {
            // 成功した場合のフィードバック
            self.errorMessage = "写真に保存しました"
            // 少し遅れてメッセージをクリア
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                self?.errorMessage = nil
            }
        }
    }
    
    // Share the generated image
    func shareImage() -> UIActivityViewController? {
        guard let image = generatedImage else {
            self.errorMessage = "No image to share"
            return nil
        }
        
        let activityViewController = UIActivityViewController(
            activityItems: [image],
            applicationActivities: nil
        )
        
        return activityViewController
    }
} 