# model/source_code/pre_process.py
from pathlib import Path
import tensorflow as tf

IMG_SIZE = (224, 224)
BATCH_SIZE = 32

def get_datasets(base_dir: str | Path):
    base_dir = Path(base_dir)
    train_dir = base_dir / "train"
    val_dir   = base_dir / "validation"   # ← change to "val" if your folder is named val

    # 1) Build raw datasets
    raw_train = tf.keras.preprocessing.image_dataset_from_directory(
        train_dir,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=True,
    )
    raw_val = tf.keras.preprocessing.image_dataset_from_directory(
        val_dir,
        image_size=IMG_SIZE,
        batch_size=BATCH_SIZE,
        label_mode="categorical",
        shuffle=False,
    )

    # 2) Capture class names BEFORE caching/prefetching
    class_names = list(raw_train.class_names)

    # 3) Optimize pipelines
    AUTOTUNE = tf.data.AUTOTUNE
    train_ds = raw_train.cache().shuffle(1000).prefetch(AUTOTUNE)
    val_ds   = raw_val.cache().prefetch(AUTOTUNE)

    return train_ds, val_ds, class_names

def get_augmenter():
    return tf.keras.Sequential([
        tf.keras.layers.RandomFlip("horizontal"),
        tf.keras.layers.RandomRotation(0.10),
        tf.keras.layers.RandomZoom(0.10),
        tf.keras.layers.RandomTranslation(0.10, 0.10),
        tf.keras.layers.RandomBrightness(0.10),
        tf.keras.layers.RandomContrast(0.10),
    ], name="augmenter")

def attach_augmentation_to_model(backbone, num_classes: int):
    inputs = tf.keras.Input(shape=(*IMG_SIZE, 3))
    x = tf.keras.layers.Rescaling(1./255)(inputs)
    x = get_augmenter()(x)
    x = backbone(x, training=False)
    x = tf.keras.layers.GlobalAveragePooling2D()(x)
    outputs = tf.keras.layers.Dense(num_classes, activation="softmax")(x)
    return tf.keras.Model(inputs, outputs)
