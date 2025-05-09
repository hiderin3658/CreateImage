import SwiftUI

struct ImageGeneratorView: View {
    @StateObject private var viewModel = ImageGeneratorViewModel()
    @State private var showingShareSheet = false
    @State private var showingAdvancedSettings = false
    @FocusState private var isPromptFocused: Bool // フォーカス状態追跡用
    
    // Nova Canvas 用のスタイルプリセット選択肢
    let stylePresets = ["none", "photorealistic", "digital-art", "cinematic", "anime", "comic-book", "fantasy-art", "line-art", "low-poly", "pixel-art"]
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Title
                    Text("Create Image with Nova Canvas") // モデル名を変更
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .padding(.horizontal)
                    
                    // Image display area
                    ZStack {
                        Rectangle()
                            .fill(Color.gray.opacity(0.1))
                            .aspectRatio(1, contentMode: .fit)
                            .cornerRadius(10)
                        
                        if viewModel.isGenerating {
                            ProgressView()
                                .scaleEffect(1.5)
                        } else if let image = viewModel.generatedImage {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .cornerRadius(10)
                        } else {
                            VStack {
                                Image(systemName: "photo")
                                    .font(.system(size: 60))
                                    .foregroundColor(.gray)
                                Text("Generated image will appear here")
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding(.horizontal)
                    
                    // Prompt input
                    VStack(alignment: .leading) {
                        Text("Prompt")
                            .font(.headline)
                        ZStack(alignment: .topLeading) {
                            if viewModel.prompt.isEmpty {
                                Text("Enter your prompt here")
                                    .foregroundColor(Color.gray.opacity(0.7))
                                    .padding(.top, 8)
                                    .padding(.leading, 8)
                            }
                            TextEditor(text: $viewModel.prompt)
                                .focused($isPromptFocused) // フォーカス状態にバインド
                                .frame(height: 100)
                                .padding(4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(5)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 5)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                        }
                        .onTapGesture {
                            isPromptFocused = true // タップでフォーカスを強制
                        }
                    }
                    .padding(.horizontal)
                    
                    // Style Preset Picker（非表示化）
                    /*
                    Picker("Style Preset", selection: $viewModel.stylePreset) {
                        ForEach(stylePresets, id: \ .self) { preset in
                            Text(preset.capitalized)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .padding(.horizontal)
                    */
                    
                    // Advanced Settings（非表示化）
                    /*
                    Button(action: {
                        showingAdvancedSettings = true
                    }) {
                        Text("Advanced Settings")
                            .font(.subheadline)
                            .foregroundColor(.blue)
                            .padding(.horizontal)
                    }
                    .sheet(isPresented: $showingAdvancedSettings) {
                        // AdvancedSettingsView(viewModel: viewModel)
                    }
                    */
                    
                    // エラーメッセージ表示
                    /*
                    if let errorMessage = viewModel.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Error")
                                .font(.headline)
                                .foregroundColor(.red)
                            
                            Text(errorMessage)
                                .font(.body)
                                .foregroundColor(.red)
                            
                            // IAM権限エラーの場合、解決策を表示
                            if errorMessage.contains("IAM権限エラー") || errorMessage.contains("アクセス権限がありません") {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("解決方法:")
                                        .font(.subheadline)
                                        .bold()
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("1. AWSコンソールにログイン")
                                        Text("2. IAMサービスに移動")
                                        Text("3. Cognito未認証ロールを検索・選択")
                                        Text("4. インラインポリシーを追加して以下の権限を付与:")
                                        Text("   - Action: bedrock:InvokeModel")
                                        Text("   - Resource: Nova Canvas model ARN")
                                    }
                                    .font(.caption)
                                    .foregroundColor(.primary)
                                    
                                    Text("5. BedrockコンソールでNova Canvasモデルアクセスを有効化")
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    
                                    Button(action: {
                                        // AWS IAMコンソールページへのリンク
                                        if let url = URL(string: "https://console.aws.amazon.com/iamv2/") {
                                            UIApplication.shared.open(url)
                                        }
                                    }) {
                                        Text("AWSコンソールを開く")
                                            .font(.caption)
                                            .padding(.vertical, 5)
                                            .padding(.horizontal, 10)
                                            .background(Color.blue)
                                            .foregroundColor(.white)
                                            .cornerRadius(5)
                                    }
                                    .padding(.top, 5)
                                }
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(10)
                            }
                        }
                        .padding()
                        .background(Color(.systemGray5).opacity(0.5))
                        .cornerRadius(10)
                        .padding(.horizontal)
                    }
                    */
                    
                    // Action buttons
                    VStack(spacing: 15) {
                        Button(action: {
                            viewModel.generateImage()
                        }) {
                            Text("Generate Image")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                        }
                        .disabled(viewModel.isGenerating || viewModel.prompt.isEmpty)
                        
                        HStack(spacing: 15) {
                            Button(action: {
                                viewModel.saveImage()
                            }) {
                                Text("Save to Photos")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.green)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(viewModel.generatedImage == nil)
                            
                            Button(action: {
                                showingShareSheet = true
                            }) {
                                Text("Share")
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.orange)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                            }
                            .disabled(viewModel.generatedImage == nil)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                .padding(.vertical)
            }
            .navigationBarHidden(true) // Hide the default navigation bar
            .sheet(isPresented: $showingShareSheet) {
                if let activityVC = viewModel.shareImage() {
                    ActivityView(activityViewController: activityVC)
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

// Activity View Controller for SwiftUI
struct ActivityView: UIViewControllerRepresentable {
    var activityViewController: UIActivityViewController
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        return activityViewController
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct ImageGeneratorView_Previews: PreviewProvider {
    static var previews: some View {
        ImageGeneratorView()
    }
} 