import sys
from pathlib import Path

import onnx
from onnx_tf.backend import prepare
import tensorflow as tf

def main():
    import datetime

    now = datetime.datetime.now()

    # For filenames / folders (no ':' so Windows is happy)
    date_for_name = now.strftime("%b_%d_%Y")       # Nov_13_2025
    time_for_name = now.strftime("%I-%M%p").lower()  # 07-23am
    ts = f"{date_for_name}_{time_for_name}"         # Nov_13_2025_07-23am

    # Optional: pretty version just for printing (not used in paths)
    pretty_time = now.strftime("%I:%M %p").lower()   # 07:23 am
    print("Timestamp (human):", f"{date_for_name.replace('_', ' ')} {pretty_time}")

    if len(sys.argv) != 3:
        print("Usage: yolo_onnx_to_tflite.py input.onnx out_dir")
        sys.exit(1)

    onnx_path = Path(sys.argv[1]).resolve()
    export_root = Path(sys.argv[2]).resolve()

    if not onnx_path.exists():
        print("[ERROR] ONNX not found")
        sys.exit(1)

    export_root.mkdir(parents=True, exist_ok=True)

    print("[*] ONNX file:", onnx_path)

    # =======================
    # 1) ONNX → TF SavedModel
    # =======================

    savedmodel_dir = export_root / f"yolo_tf_savedmodel_{ts}"
    savedmodel_dir.mkdir(parents=True, exist_ok=True)

    print("[*] Exporting TensorFlow SavedModel to:", savedmodel_dir)

    model = onnx.load(str(onnx_path))
    tf_rep = prepare(model)
    tf_rep.export_graph(str(savedmodel_dir))

    # TFLite files INSIDE savedmodel folder
    fp32_path = savedmodel_dir / f"fishdet_fp32_{ts}.tflite"
    fp16_path = savedmodel_dir / f"fishdet_fp16_{ts}.tflite"

    # =======================
    # 2) SavedModel → TFLite FP32
    # =======================
    print("[*] Converting to TFLite FP32...")
    converter = tf.lite.TFLiteConverter.from_saved_model(str(savedmodel_dir))
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter.allow_custom_ops = True

    tflite_fp32 = converter.convert()
    fp32_path.write_bytes(tflite_fp32)
    print("[✓] Wrote:", fp32_path)

    # =======================
    # 3) SavedModel → TFLite FP16
    # =======================
    print("[*] Converting to TFLite FP16...")
    converter = tf.lite.TFLiteConverter.from_saved_model(str(savedmodel_dir))
    converter.target_spec.supported_ops = [
        tf.lite.OpsSet.TFLITE_BUILTINS,
        tf.lite.OpsSet.SELECT_TF_OPS,
    ]
    converter.allow_custom_ops = True
    converter.optimizations = [tf.lite.Optimize.DEFAULT]
    converter.target_spec.supported_types = [tf.float16]

    tflite_fp16 = converter.convert()
    fp16_path.write_bytes(tflite_fp16)
    print("[✓] Wrote:", fp16_path)

    print("\nAll good.")
    print(" SavedModel:", savedmodel_dir)
    print(" FP32:", fp32_path)
    print(" FP16:", fp16_path)



if __name__ == "__main__":
    main()
