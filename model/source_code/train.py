# --- top of train.py ---
from collections import Counter
import numpy as np
import tensorflow as tf
from pathlib import Path
from pre_process import get_datasets, attach_augmentation_to_model, IMG_SIZE

DATA_DIR = Path(__file__).resolve().parents[1] / "datasets"
SAVE_DIR = Path(__file__).resolve().parents[1] / "models"
SAVE_DIR.mkdir(parents=True, exist_ok=True)
SAVE_PATH = SAVE_DIR / "mobilenetv2_fishfresh.keras"

def infer_class_weights_from_ds(train_ds, num_classes: int):
    # iterate once to collect labels
    labels = []
    for _, y in train_ds.unbatch():
        labels.append(int(np.argmax(y.numpy())))
    counts = Counter(labels)
    total = sum(counts.values())
    # inverse frequency weighting
    return {i: total / (num_classes * counts.get(i, 1)) for i in range(num_classes)}

def main():
    # ⬇️ now returns class_names from pre_process.py
    train_ds, val_ds, class_names = get_datasets(DATA_DIR)
    num_classes = len(class_names)
    print("Classes:", class_names)

    base = tf.keras.applications.MobileNetV2(
        input_shape=(*IMG_SIZE, 3), include_top=False, weights="imagenet"
    )

    model = attach_augmentation_to_model(base, num_classes)
    model.compile(
        optimizer=tf.keras.optimizers.Adam(1e-3),
        loss="categorical_crossentropy",
        metrics=["accuracy"]
    )

    # ⬇️ pass num_classes instead of using train_ds.class_names
    class_weight = infer_class_weights_from_ds(train_ds, num_classes)
    print("Class weights:", class_weight)

    callbacks = [
        tf.keras.callbacks.ModelCheckpoint(str(SAVE_PATH), save_best_only=True, monitor="val_accuracy"),
        tf.keras.callbacks.EarlyStopping(patience=5, restore_best_weights=True, monitor="val_accuracy"),
    ]

    model.fit(train_ds, validation_data=val_ds, epochs=25,
              callbacks=callbacks, class_weight=class_weight)
    print("✅ Saved best model to:", SAVE_PATH)

if __name__ == "__main__":
    main()
