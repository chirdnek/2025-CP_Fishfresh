# model/source_code/evaluate.py
import tensorflow as tf
from pathlib import Path
from pre_process import IMG_SIZE
MODEL_PATH = Path(__file__).resolve().parents[1] / "models" / "mobilenetv2_fishfresh.keras"
TEST_DIR   = Path(__file__).resolve().parents[1] / "datasets" / "testing"

def main():
    model = tf.keras.models.load_model(MODEL_PATH)
    test_ds = tf.keras.preprocessing.image_dataset_from_directory(
        TEST_DIR, image_size=IMG_SIZE, batch_size=32, label_mode="categorical", shuffle=False
    )
    loss, acc = model.evaluate(test_ds)
    print(f"Test accuracy: {acc:.4f}")

if __name__ == "__main__":
    main()
