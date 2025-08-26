# model/source_code/multitask_train.py
from pathlib import Path
import json
import tensorflow as tf
from keras import layers, regularizers
import numpy as np

# ---------- CONFIG ----------
IMG_SIZE   = (224, 224)
BATCH_SIZE = 32
FRESHNESS_CLASSES = ["borderline", "fresh", "not_fresh"]
SAVE_NAME  = "multitask_mobilenetv2.keras"
LABELS_JSON= "multitask_labels.json"

# when resuming:
RESUME_TRAINING = True        # set True to continue from saved model if it exists
EPOCHS_HEAD     = 25          # first stage (frozen backbone)
EPOCHS_FINETUNE = 10          # second stage (partial unfreeze)
# You can run again later with RESUME_TRAINING=True and it’ll keep improving.

# ---------- DATA PIPELINE ----------
ALLOWED = {".jpg", ".jpegA", ".png", ".bmp", ".webp"}

def discover_species_classes(train_root: Path) -> list[str]:
    species = set()
    for fcls in FRESHNESS_CLASSES:
        fdir = train_root / fcls
        if not fdir.exists(): 
            continue
        for sdir in fdir.iterdir():
            if sdir.is_dir():
                species.add(sdir.name)
    if not species:
        species = {"unknown"}
    return sorted(species)

def list_images_with_labels(split_dir: Path, species_classes):
    filepaths, freshness_ids, species_ids = [], [], []
    sp_index = {name:i for i,name in enumerate(species_classes)}
    fr_index = {name:i for i,name in enumerate(FRESHNESS_CLASSES)}
    for f_name in FRESHNESS_CLASSES:
        f_dir = split_dir / f_name
        if not f_dir.exists(): 
            continue
        for s_dir in f_dir.iterdir():
            if not s_dir.is_dir(): 
                continue
            s_name = s_dir.name
            if s_name not in sp_index:
                # skip unknown folder names
                continue
            for p in s_dir.rglob("*"):
                if p.suffix.lower() in ALLOWED:
                    filepaths.append(str(p))
                    freshness_ids.append(fr_index[f_name])
                    species_ids.append(sp_index[s_name])
    return filepaths, np.array(freshness_ids), np.array(species_ids)

def make_dataset(split_dir: Path, species_classes, shuffle: bool):
    fps, fr_y, sp_y = list_images_with_labels(split_dir, species_classes)
    fr_y = tf.one_hot(fr_y, depth=len(FRESHNESS_CLASSES))
    sp_y = tf.one_hot(sp_y, depth=len(species_classes))

    ds = tf.data.Dataset.from_tensor_slices((fps, fr_y, sp_y))

    def load_img(path, fr_label, sp_label):
        img = tf.io.read_file(path)
        img = tf.image.decode_image(img, channels=3, expand_animations=False)
        img = tf.image.resize(img, IMG_SIZE)
        img = tf.cast(img, tf.float32) / 255.0
        return img, {"fresh_out": fr_label, "species_out": sp_label}

    ds = ds.map(load_img, num_parallel_calls=tf.data.AUTOTUNE)
    if shuffle:
        ds = ds.shuffle(1000)
    return ds.batch(BATCH_SIZE).prefetch(tf.data.AUTOTUNE)

def get_augmenter():
    return tf.keras.Sequential([
        layers.RandomFlip("horizontal"),
        layers.RandomRotation(0.10),
        layers.RandomZoom(0.10),
        layers.RandomTranslation(0.10, 0.10),
        layers.RandomBrightness(0.10),
        layers.RandomContrast(0.10),
    ], name="augmenter")

# ---------- MODEL ----------
def build_model(num_species: int):
    inputs = layers.Input(shape=(*IMG_SIZE, 3))
    x = get_augmenter()(inputs)
    base = tf.keras.applications.MobileNetV2(
        input_shape=(*IMG_SIZE, 3), include_top=False, weights="imagenet"
    )
    base.trainable = False  # stage 1: frozen
    x = base(x, training=False)
    x = layers.GlobalAveragePooling2D()(x)
    x = layers.Dropout(0.5)(x)
    x = layers.Dense(128, activation="relu",
                    kernel_regularizer=regularizers.l2(1e-4))(x)
    x = layers.Dropout(0.4)(x)

    fresh_out   = layers.Dense(len(FRESHNESS_CLASSES), activation="softmax", name="fresh_out")(x)
    species_out = layers.Dense(num_species, activation="softmax", name="species_out")(x)

    model = tf.keras.Model(inputs, outputs={"fresh_out": fresh_out, "species_out": species_out})
    return model, base

def compile_model(model, lr, label_smoothing):
    model.compile(
        optimizer=tf.keras.optimizers.Adam(lr),
        loss={
            "fresh_out":   tf.keras.losses.CategoricalCrossentropy(label_smoothing=label_smoothing),
            "species_out": tf.keras.losses.CategoricalCrossentropy(label_smoothing=label_smoothing),
        },
        metrics={"fresh_out": "accuracy", "species_out": "accuracy"},
        loss_weights={"fresh_out": 1.0, "species_out": 1.0},
    )

# ---------- TRAIN / RESUME ----------
def main():
    root = Path(__file__).resolve().parents[1]
    data_root = root / "datasets"
    save_dir  = root / "models"
    save_dir.mkdir(parents=True, exist_ok=True)
    save_path = save_dir / SAVE_NAME
    labels_path = save_dir / LABELS_JSON

    # Discover species from train tree (or load previous labels to keep order consistent)
    discovered_species = discover_species_classes(data_root / "train")

    if labels_path.exists():
        with open(labels_path, "r", encoding="utf-8") as f:
            stored = json.load(f)
        prev_species = stored.get("species_classes", [])
        prev_fresh   = stored.get("freshness_classes", [])
        # ensure same order across runs
        if prev_species and prev_fresh == FRESHNESS_CLASSES:
            species_classes = prev_species
        else:
            species_classes = discovered_species
    else:
        species_classes = discovered_species
        with open(labels_path, "w", encoding="utf-8") as f:
            json.dump({"freshness_classes": FRESHNESS_CLASSES,
                       "species_classes": species_classes}, f, indent=2)

    print("Freshness classes:", FRESHNESS_CLASSES)
    print("Species classes  :", species_classes)

    # Datasets
    train_ds = make_dataset(data_root / "train", species_classes, shuffle=True)
    val_ds   = make_dataset(data_root / "validation", species_classes, shuffle=False)

    # Callbacks
    cbs = [
        tf.keras.callbacks.ModelCheckpoint(
            str(save_path), save_best_only=True,
            monitor="val_fresh_out_accuracy", mode="max"
        ),
        tf.keras.callbacks.EarlyStopping(
            patience=6, restore_best_weights=True,
            monitor="val_fresh_out_accuracy", mode="max"
        ),
        tf.keras.callbacks.ReduceLROnPlateau(
            monitor="val_fresh_out_loss", factor=0.5, patience=2, min_lr=1e-6, mode="min"
        ),
    ]

    # --------- BUILD OR LOAD ----------
    if RESUME_TRAINING and save_path.exists():
        print(f"🔁 Resuming from: {save_path.name}")
        model = tf.keras.models.load_model(save_path)
        # try to find base by name; if not, it's okay to continue without unfreezing
        base = None
        for layer in model.layers:
            if isinstance(layer, tf.keras.Model) and layer.name.startswith("MobilenetV2".lower()) or "mobilenetv2" in layer.name.lower():
                base = layer
                break
        # compile at a low LR for safe continuation
        compile_model(model, lr=1e-5, label_smoothing=0.05)
        model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_FINETUNE, callbacks=cbs)
    else:
        # fresh build
        model, base = build_model(num_species=len(species_classes))
        # stage 1: heads only
        compile_model(model, lr=1e-4, label_smoothing=0.1)
        model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_HEAD, callbacks=cbs)

        # stage 2: fine-tune last ~20 layers (if base found)
        if base is not None:
            base.trainable = True
            for layer in base.layers[:-20]:
                layer.trainable = False
            compile_model(model, lr=1e-5, label_smoothing=0.05)
            model.fit(train_ds, validation_data=val_ds, epochs=EPOCHS_FINETUNE, callbacks=cbs)

    print(f"✅ Saved best to: {save_path}")

if __name__ == "__main__":
    main()
