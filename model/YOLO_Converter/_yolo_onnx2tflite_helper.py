import sys, json
from pathlib import Path
import tensorflow as tf

if len(sys.argv) < 4:
    print("USAGE: helper <tf_savedmodel_dir> <out_fp32.tflite> <out_fp16.tflite>")
    sys.exit(1)

saved_model_dir = Path(sys.argv[1])
tfl_fp32 = Path(sys.argv[2])
tfl_fp16 = Path(sys.argv[3])

def convert(saved_model_dir: Path, out_path: Path, fp16: bool):
    conv = tf.lite.TFLiteConverter.from_saved_model(str(saved_model_dir))
    conv.optimizations = [tf.lite.Optimize.DEFAULT]
    if fp16:
        conv.target_spec.supported_types = [tf.float16]
    tfl = conv.convert()
    out_path.write_bytes(tfl)

print("[*] TFLite FP32...")
convert(saved_model_dir, tfl_fp32, fp16=False)
print("[*] TFLite FP16...")
convert(saved_model_dir, tfl_fp16, fp16=True)
print("[✓] Wrote:", tfl_fp32, "and", tfl_fp16)
