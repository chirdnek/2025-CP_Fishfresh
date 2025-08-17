# model/source_code/convert_to_tflite.py
import tensorflow as tf
from pathlib import Path

MODEL_PATH = Path(__file__).resolve().parents[1] / "models" / "mobilenetv2_fishfresh.keras"
TFLITE_PATH = MODEL_PATH.with_suffix(".tflite")

def main():
    model = tf.keras.models.load_model(MODEL_PATH)
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    # (optional) enable optimizations for mobile
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    tflite_model = converter.convert()
    with open(TFLITE_PATH, "wb") as f:
        f.write(tflite_model)
    print("✅ Saved:", TFLITE_PATH)

if __name__ == "__main__":
    main()
