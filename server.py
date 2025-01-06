from flask import Flask, request, jsonify, send_file
from flask_cors import CORS
import base64
import vertexai
import os
import requests
from vertexai.preview.generative_models import GenerativeModel, SafetySetting, Part, Tool
from vertexai.preview.generative_models import grounding
import io
import gtts

# Set the credentials path
credentials_path = '/Users/xinpengshou/PycharmProjects/flask/mlb-446801-6c9c1d55635e.json'
os.environ['GOOGLE_APPLICATION_CREDENTIALS'] = credentials_path

# Microsoft TTS Configuration
API_URL = "https://api-inference.huggingface.co/models/microsoft/speecht5_tts"
headers = {
    "Authorization": "Bearer hf_xxxxxxxxxxxxxxxxxxxxxxx"}  # Replace with your actual Hugging Face token


def text_to_speech(text):
    try:
        # Use gTTS with slower speed and US English accent
        tts = gtts.gTTS(text=text, lang='en', tld='com')  # tld='com' for US accent
        audio_content = io.BytesIO()
        tts.write_to_fp(audio_content)
        audio_content.seek(0)
        return audio_content.read()
    except Exception as e:
        print(f"TTS error: {str(e)}")
        return None


app = Flask(__name__)
CORS(app)

try:
    print("Initializing Vertex AI...")
    vertexai.init(
        project="mlb-446801",
        location="us-central1"
    )
    print("Vertex AI initialized successfully")

    generation_config = {
        "max_output_tokens": 100,
        "temperature": 0.7,
        "top_p": 0.8,
    }

    safety_settings = [
        SafetySetting(
            category=SafetySetting.HarmCategory.HARM_CATEGORY_HATE_SPEECH,
            threshold=SafetySetting.HarmBlockThreshold.BLOCK_ONLY_HIGH
        ),
        SafetySetting(
            category=SafetySetting.HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT,
            threshold=SafetySetting.HarmBlockThreshold.BLOCK_ONLY_HIGH
        ),
        SafetySetting(
            category=SafetySetting.HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT,
            threshold=SafetySetting.HarmBlockThreshold.BLOCK_ONLY_HIGH
        ),
        SafetySetting(
            category=SafetySetting.HarmCategory.HARM_CATEGORY_HARASSMENT,
            threshold=SafetySetting.HarmBlockThreshold.BLOCK_ONLY_HIGH
        ),
    ]

    print("Creating Gemini model...")
    model = GenerativeModel(
        "gemini-1.5-flash-002",
        tools=[Tool.from_google_search_retrieval(
            google_search_retrieval=grounding.GoogleSearchRetrieval()
        )],
        system_instruction=["""You are a humorous MLB chatbot. Only provide baseball-related information. 
        Keep responses short, direct, and focused in two sentences. Never mention AI, chatbots, based on provided text, or training data. 
        If asked about non-baseball topics, politely redirect to baseball."""]
    )
    # Disable response validation
    chat = model.start_chat(response_validation=False)
    print("Gemini model created successfully")

except Exception as e:
    print(f"Error during initialization: {str(e)}")
    raise e


@app.route('/gemini', methods=['POST'])
def process_text():
    try:
        data = request.json
        text = data.get('text', '')
        print(f"\nReceived request with text: {text}")

        if not text:
            return jsonify({'error': 'No text provided'}), 400

        # Create a new chat instance for each request
        chat = model.start_chat(response_validation=False)

        # Send text to Gemini and get response
        print("Sending to Gemini...")
        response = chat.send_message(
            [text],
            generation_config=generation_config,
            safety_settings=safety_settings
        )

        # Extract and clean the response text
        try:
            response_text = response.candidates[0].content.parts[0].text
            # Clean up the response text
            clean_response = (response_text.strip()
                              .replace('\n', ' ')
                              .replace('*', '')
                              .replace('"', '')
                              .replace('**', ''))
            # Remove multiple spaces
            clean_response = ' '.join(clean_response.split())
        except Exception as e:
            clean_response = str(response)

        print(f"Gemini response: {clean_response}")

        # Convert text to speech
        print("Converting to speech...")
        audio_content = text_to_speech(clean_response)

        response_data = {
            'response': clean_response,
            'audio': None
        }

        if audio_content:
            response_data['audio'] = base64.b64encode(audio_content).decode('utf-8')
            print("Audio conversion successful")
            print("Response contains: text and audio")
        else:
            print("Audio conversion failed or returned None")
            print("Response contains: text only")

        return jsonify(response_data)

    except Exception as e:
        error_message = str(e)
        print(f"Error processing request: {error_message}")
        return jsonify({
            'response': "I apologize, but I couldn't process that request. Please try again.",
            'audio': None
        }), 200


if __name__ == '__main__':
    print("Starting Flask server...")
    app.run(host='0.0.0.0', port=8000, debug=True)
