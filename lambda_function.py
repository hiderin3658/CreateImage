import json
import boto3
import os
import base64
import logging

# ロギングの設定
logger = logging.getLogger()
logger.setLevel(logging.INFO)

def lambda_handler(event, context):
    # ログ出力を追加
    logger.info(f"Received event: {json.dumps(event)}")
    
    try:
        # リクエストボディの取得
        if 'body' in event:
            # プロキシ統合の場合、bodyはJSON文字列
            try:
                body = json.loads(event['body'])
                logger.info(f"Parsed body from event['body']: {json.dumps(body)}")
            except Exception as e:
                logger.error(f"Error parsing body: {str(e)}")
                if isinstance(event['body'], dict):
                    body = event['body']  # すでにJSONオブジェクトの場合
                else:
                    logger.error("Invalid body format in event")
                    return {
                        "statusCode": 400,
                        "headers": {"Content-Type": "application/json"},
                        "body": json.dumps({"error": "リクエストボディのフォーマットが無効です。"})
                    }
        else:
            # 非プロキシ統合または直接イベントにパラメータがある場合
            body = event
            logger.info(f"Using entire event as body: {json.dumps(event)}")
        
        # 必要なパラメータの取得
        prompt = body.get('prompt')
        
        # Promptがない場合はエラー
        if not prompt:
            error_response = {
                "statusCode": 400,
                "headers": {"Content-Type": "application/json"},
                "body": json.dumps({"error": "リクエストボディが見つかりません。"})
            }
            logger.error("Missing prompt in request")
            return error_response
        
        # その他のパラメータを取得
        number_of_images = body.get('numberOfImages', 1)
        width = body.get('width', 1024)
        height = body.get('height', 1024)
        cfg_scale = body.get('cfgScale', 7.0)
        seed = body.get('seed', 0)
        steps = body.get('steps', 50)
        style_preset = body.get('style_preset', '')
        
        logger.info(f"Parameters: prompt={prompt}, style_preset={style_preset}, numberOfImages={number_of_images}, width={width}, height={height}, cfgScale={cfg_scale}, seed={seed}, steps={steps}")
        
        # オリジナルプロンプトを保存
        original_prompt = prompt
        
        # 日本語プロンプトを検出して英語に翻訳
        translate_client = boto3.client('translate')
        
        # 日本語文字が含まれているか簡易チェック
        has_japanese = any(ord(c) > 0x3000 for c in prompt)
        
        if has_japanese:
            try:
                # AWS Translateを使用して翻訳
                translation_response = translate_client.translate_text(
                    Text=prompt,
                    SourceLanguageCode='ja',
                    TargetLanguageCode='en'
                )
                
                # 翻訳結果を取得
                prompt = translation_response.get('TranslatedText')
                
                logger.info(f"Translated prompt: '{original_prompt}' -> '{prompt}'")
            except Exception as e:
                logger.warning(f"Translation failed: {str(e)}, using original prompt")
        
        # Nova Canvasに最適化したプロンプトに拡張
        # スタイルプリセットがある場合は適用
        enhanced_prompt = enhance_prompt_for_nova_canvas(prompt, style_preset)
        logger.info(f"Enhanced prompt: '{prompt}' -> '{enhanced_prompt}'")
        
        # Bedrock クライアント
        bedrock_runtime = boto3.client('bedrock-runtime')
        
        # モデルID
        model_id = os.environ.get('BEDROCK_MODEL_ID', 'amazon.nova-canvas-v1:0')
        
        # Bedrock API リクエスト（Nova Canvas正しい形式）
        request_body = {
            "taskType": "TEXT_IMAGE",
            "textToImageParams": {
                "text": enhanced_prompt
            },
            "imageGenerationConfig": {
                "seed": seed,
                "quality": "standard",
                "width": width,
                "height": height,
                "numberOfImages": number_of_images
            }
        }
        
        logger.info(f"Bedrock request: {json.dumps(request_body)}")
        
        # Bedrock API 呼び出し
        response = bedrock_runtime.invoke_model(
            modelId=model_id,
            body=json.dumps(request_body)
        )
        
        # レスポンスの解析
        response_body = json.loads(response['body'].read())
        logger.info(f"Bedrock response: {json.dumps(response_body)}")
        
        # Base64 エンコードされた画像データの取得
        images = []
        if 'images' in response_body:
            images = response_body['images']
        elif 'content' in response_body:
            # Claude形式のレスポンス処理
            for item in response_body.get('content', []):
                if item.get('type') == 'image' and 'source' in item:
                    if 'data' in item['source'] and 'base64' in item['source']['data']:
                        images.append(item['source']['data']['base64'])
        
        # 成功レスポンス
        success_response = {
            "statusCode": 200,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({
                "images": images, 
                "prompt": enhanced_prompt,
                "originalPrompt": original_prompt,
                "translatedPrompt": prompt if has_japanese else ""
            })
        }
        
        return success_response
        
    except Exception as e:
        logger.error(f"Error: {str(e)}")
        # エラーレスポンス
        error_response = {
            "statusCode": 500,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": str(e)})
        }
        return error_response

def enhance_prompt_for_nova_canvas(prompt, style_preset=""):
    """
    プロンプトをNova Canvasに最適化して拡張する
    """
    # プロンプトの基本構造: 主題 + 詳細 + スタイル + 品質
    base_prompt = prompt.strip()
    
    # スタイルプリセットに基づく拡張
    style_description = ""
    if style_preset:
        if style_preset.lower() == "line art":
            style_description = "in line art style, clean linework, high contrast black and white illustration, minimalist"
        elif style_preset.lower() == "digital art":
            style_description = "digital art style, vibrant colors, detailed, professional digital painting"
        elif style_preset.lower() == "photorealistic":
            style_description = "photorealistic style, highly detailed, sharp focus, professional photography"
        elif style_preset.lower() == "anime":
            style_description = "anime style, vibrant colors, clean lines, detailed characters and backgrounds"
        elif style_preset.lower() == "watercolor":
            style_description = "watercolor painting style, soft colors, gentle brush strokes, artistic"
        elif style_preset.lower() == "oil painting":
            style_description = "oil painting style, textured brush strokes, rich colors, classic art technique"
        elif style_preset.lower() == "3d rendering":
            style_description = "3D rendering, detailed textures, volumetric lighting, professional 3D visualization"
        elif style_preset.lower() == "cartoon":
            style_description = "cartoon style, bold outlines, bright colors, simplified shapes"
        else:
            style_description = f"in {style_preset} style"
    
    # 品質とレンダリングに関する詳細を追加
    quality_description = "high quality, 4K, detailed, professional"
    
    # 最終的なプロンプトを構築
    if style_description:
        enhanced_prompt = f"{base_prompt}, {style_description}, {quality_description}"
    else:
        enhanced_prompt = f"{base_prompt}, {quality_description}"
    
    return enhanced_prompt
