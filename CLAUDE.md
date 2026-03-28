# FishFresh

AI-powered Flutter mobile app for **fish species identification** and **freshness assessment** using on-device machine learning.

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Mobile App | Flutter (Dart), SDK 3.8.1+ |
| ML Inference | TensorFlow Lite (on-device) |
| Detection Model | YOLOv8s (768x768 input) |
| Classification Model | ResNet50 (320x320 input, ~96% val accuracy) |
| Backend | Firebase (Auth, Firestore, Storage, Messaging, Analytics) |
| Auth | Email/password + Google Sign-In + Biometrics |
| Training | PyTorch + Jupyter Notebooks (Kaggle) |
| Model Conversion | PyTorch -> ONNX -> TFLite (FP32/FP16) |
| AI Features | Google Gemini (fish almanac descriptions) |

## ML Pipeline

Two-stage detection + classification:

1. **YOLOv8 Detection** -- Locates fish bounding boxes in the image
2. **ResNet50 Classification** -- Classifies each detected fish crop

### 12 Classes (6 species x 2 freshness states)

| Species | Fresh | Not Fresh |
|---------|-------|-----------|
| Bigeye Scad | fresh__bigeye_scad | not_fresh__bigeye_scad |
| Country Maiden | fresh__country_maiden | not_fresh__country_maiden |
| Fringescale Sardinella | fresh__fringescale_sardinella | not_fresh__fringescale_sardinella |
| Indian Mackerel | fresh__indian_mackerel | not_fresh__indian_mackerel |
| Shortfin Scad | fresh__shortfin_scad | not_fresh__shortfin_scad |
| Yellowfin Tuna | fresh__yellowfin_tuna | not_fresh__yellowfin_tuna |

### Scan Modes

- **Single** -- One fish detection + full-frame fallback
- **Tray** -- Multi-fish detection (market trays/displays)
- **Auto** -- Switches between single/tray based on detection count

### Thresholds

- Detection confidence: 0.05
- IoU (NMS): 0.45
- Classification confidence: 40% (below = "Unknown")

## Directory Structure

```
2025-CP_Fishfresh/
├── fishfresh/                      # Flutter application
│   ├── lib/
│   │   ├── main.dart               # App entry point, Firebase init, routing
│   │   ├── models/
│   │   │   └── user_model.dart     # User data model
│   │   ├── screens/                # UI screens
│   │   │   ├── splash_screen.dart
│   │   │   ├── loading_screen.dart      # Transition screen before home
│   │   │   ├── login.dart
│   │   │   ├── signup.dart
│   │   │   ├── home.dart
│   │   │   ├── fish_scan_camera.dart    # Camera UI for scanning
│   │   │   ├── fish_result_screen.dart  # Detection results display
│   │   │   ├── history.dart
│   │   │   ├── gallery.dart
│   │   │   ├── almanac_screen.dart      # Fish species database
│   │   │   ├── profile_screens.dart
│   │   │   ├── profile_settings_screen.dart
│   │   │   ├── faq_screen.dart
│   │   │   ├── privacypolicy_screen.dart
│   │   │   ├── termsofuse_screen.dart
│   │   │   ├── user_form.dart
│   │   │   └── onboarding/onboarding_screen.dart
│   │   ├── services/               # Core business logic
│   │   │   ├── fish_pipeline.dart       # Full detect->classify pipeline
│   │   │   ├── fish_detector.dart       # YOLOv8 TFLite wrapper
│   │   │   ├── fish_classifier.dart     # ResNet50 TFLite wrapper
│   │   │   ├── fish_model.dart          # Legacy single-model classifier
│   │   │   ├── fishdet_config.dart      # Detector config loader
│   │   │   ├── db_service.dart          # Firestore operations
│   │   │   ├── storage_service.dart     # SharedPreferences
│   │   │   ├── image_service.dart       # Image processing utils
│   │   │   ├── network_monitor.dart     # Connectivity monitoring
│   │   │   ├── preprocess_guard.dart    # Image preprocessing
│   │   │   ├── push_notification_service.dart
│   │   │   ├── biometrics_service.dart
│   │   │   └── save_scan_history.dart
│   │   └── widgets/                # Reusable UI components
│   │       ├── network_status_listener.dart
│   │       ├── network_status_banner.dart
│   │       ├── biometric_gate.dart
│   │       ├── button.dart
│   │       ├── circular_transition.dart
│   │       └── onboarding_page.dart
│   ├── assets/
│   │   ├── model/                  # Deployed TFLite models
│   │   │   ├── fishdet_fp32_2025-11-17_00-50-15.tflite    # YOLOv8 detector
│   │   │   ├── resnet50_torchvision_Jan_31_12-33_am_NEWYEAR_float32.tflite  # Classifier (active)
│   │   │   ├── fishdet_config.json      # Detector hyperparams
│   │   │   └── classes_flat.json        # 12 class labels
│   │   ├── images/                 # UI images, fish samples
│   │   ├── icons/                  # App icons
│   │   └── kb/fishfresh_kb.txt     # Knowledge base
│   ├── android/                    # Android native config
│   ├── ios/                        # iOS native config
│   └── pubspec.yaml               # Dart dependencies
│
├── model/                          # ML training & conversion
│   ├── resnet-kaggle-320-nobars.ipynb   # ResNet50 training (LATEST - 320px input, no bar charts)
│   ├── yolo_onnx_to_tflite.py          # ONNX -> TFLite converter
│   ├── detector_dataset.yaml            # YOLO dataset config
│   ├── source_code/
│   │   ├── convert_to_tflite.py         # Keras -> TFLite converter
│   │   └── split_multitask.py           # Dataset train/val/test splitter
│   ├── YOLO_Converter/
│   │   └── _yolo_onnx2tflite_helper.py  # TFLite conversion helper
│   ├── models/                          # All model artifacts
│   │   ├── classes.json
│   │   ├── classes_flat.json
│   │   └── classes_6species.json
│   ├── OLD_IPYNB/                       # Archived training notebooks
│   └── runs_fishdet/                    # YOLO evaluation results
│
└── CLAUDE.md                       # This file
```

## Key Files

### Flutter App (Core ML)
- `fishfresh/lib/services/fish_pipeline.dart` -- Orchestrates detection + classification
- `fishfresh/lib/services/fish_detector.dart` -- YOLOv8 inference, NMS, letterbox resize
- `fishfresh/lib/services/fish_classifier.dart` -- ResNet50 inference, ImageNet normalization
- `fishfresh/lib/services/fishdet_config.dart` -- Loads detector config JSON

### Flutter App (UI)
- `fishfresh/lib/main.dart` -- Entry point, Firebase setup, routing
- `fishfresh/lib/screens/fish_scan_camera.dart` -- Camera scanning UI
- `fishfresh/lib/screens/fish_result_screen.dart` -- Results display

### Model Training & Conversion
- `model/resnet-kaggle-320-nobars.ipynb` -- **Latest** ResNet50 training notebook (320px input, YOLO-crop augmentation, weighted loss, pHash dedup)
- `model/yolo_onnx_to_tflite.py` -- YOLO ONNX to TFLite conversion
- `model/source_code/split_multitask.py` -- Dataset splitting utility

### Model Assets
- `fishfresh/assets/model/fishdet_config.json` -- Detector config (768px input, 0.05 conf)
- `fishfresh/assets/model/classes_flat.json` -- 12 class labels

## Build & Run

```bash
cd fishfresh
flutter pub get
flutter run
```

## Model Conversion Pipeline

```
PyTorch (.pt) -> ONNX (.onnx) -> TensorFlow SavedModel -> TFLite (.tflite)
```

- ResNet50/MobileNetV2: Export via `torch.onnx.export()`, convert with `onnx_tf` + `TFLiteConverter`
- YOLOv8: Export via Ultralytics, convert with `model/yolo_onnx_to_tflite.py`
- Both FP32 (full precision) and FP16 (half precision) variants supported

## Training Notebook Pipeline (`resnet-kaggle-320-nobars.ipynb`)

1. Path config (Kaggle + local)
2. Auto-split `_raw` into train/val/test
3. Multitask splitter (freshness x species folders)
4. Image deduplication (pHash)
5. Flatten to ImageFolder layout (`freshness__species`)
6. YOLO-based cls-style crop building (detect fish -> crop -> save)
7. Weighted CrossEntropyLoss for class imbalance
8. Build ResNet50 (torchvision, 320px input)
9. Train with SGD + Cosine LR + AMP (staged fine-tune: head then full)
10. Validation + classification report
11. Test set evaluation
12. Export TorchScript (.pt) + ONNX (.onnx)

## Dataset

~1,380 labeled images across 12 classes (train: 914, val: 122, test: 344). Final ResNet50 achieved **96.13% validation accuracy** over 72 training epochs.

## Known Issues

- **Merge conflicts** in `fishfresh/lib/services/fish_classifier.dart` (7 conflicts) and `fishfresh/lib/services/fish_pipeline.dart` (3 conflicts) from branch merge with `afe1cba`
