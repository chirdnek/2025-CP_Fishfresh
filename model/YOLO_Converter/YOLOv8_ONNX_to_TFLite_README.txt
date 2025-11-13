YOLOv8 ONNX -> TFLite (FP32 + FP16) — Windows Batch

USAGE
-----
convert_yolov8_onnx_to_tflite.bat path\to\fishdet_yolov8n_oiv7.onnx out_dir

WHAT IT DOES
------------
1) Creates a local venv under out_dir\.yolo2tfl (Python 3.10/3.11).
2) Installs pinned deps compatible with TensorFlow 2.16.1.
3) (Optional) Simplifies ONNX at shape 1x3x640x640.
4) Uses onnx2tf to produce a TF SavedModel.
5) Converts to TFLite FP32 and FP16.

NOTES
-----
- Use the *pre-NMS* ONNX export (`fishdet_yolov8n_oiv7.onnx`) for best compatibility.
- Input must be 1x3x640x640 BCHW (exported from Ultralytics at imgsz=640).
- If you need dynamic shapes, remove the `--overwrite-input-shape` in the batch.

OUTPUTS
-------
out_dir\tf_savedmodel\   (SavedModel)
out_dir\yolov8_fp32.tflite
out_dir\yolov8_fp16.tflite
