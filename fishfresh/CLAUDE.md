# FishFresh — CLAUDE.md

## Project Overview

**FishFresh** is an AI-powered fish freshness and species detection mobile app built with Flutter. It uses two TFLite ML models in a pipeline:
1. **YOLOv8** — detects fish bounding boxes in an image
2. **ResNet50** — classifies each detected fish by species and freshness

The app targets Android and iOS primarily, with desktop (Windows, macOS, Linux) and web builds also present.

---

## Tech Stack

| Layer | Technology |
|-------|-----------|
| UI Framework | Flutter ^3.8.1 |
| ML Inference | tflite_flutter 0.11.0 |
| Image Processing | image 4.2.0 |
| Camera | camera 0.10.6 + image_picker 1.0.4 |
| Auth | Firebase Auth, Google Sign-In, local_auth (biometrics) |
| Database | Cloud Firestore (scan history), sqflite (local, minimal use) |
| Storage | SharedPreferences (onboarding flag), Firebase Storage |
| AI/NLP | google_generative_ai 0.4.7 (Gemini API) |
| Notifications | firebase_messaging + flutter_local_notifications |
| PDF/Print | pdf 3.11.0 + printing 5.12.0 |
| Connectivity | connectivity_plus + internet_connection_checker_plus |

---

## ML Pipeline

```
User Input (Camera frame or gallery image)
    │
    ▼
FishPipeline.runOnBytes(imageBytes)          ← lib/services/fish_pipeline.dart
    │
    ├─ FishDetector.detect()                 ← lib/services/fish_detector.dart
    │    YOLOv8s, 768×768 input, fp32
    │    Letterbox resize → inference → NMS (IOU 0.45) → bounding boxes
    │
    ├─ Decide mode:
    │    ≥2 boxes → "tray"  (multi-fish)
    │    <2 boxes → "single"
    │
    └─ Per fish crop → FishClassifier.classify()   ← lib/services/fish_classifier.dart
           ResNet50 (torchvision), 224×224 input, fp32
           Resize shorter side to 258px → center crop 224×224
           ImageNet normalize (mean=[0.485,0.456,0.406], std=[0.229,0.224,0.225])
           Output: species + freshness label, confidence
```

### Pipeline Output Structure
```dart
{
  'latency_ms': int,
  'per_fish': [
    {
      'fish_box_id': int,
      'box_norm': { 'left', 'top', 'right', 'bottom' }, // 0–1 normalized
      'species': String,   // e.g. "Indian Mackerel"
      'freshness': String, // "Fresh" or "Not Fresh"
      'cls_conf': double,
      'det_score': double,
    }
  ],
  'overall_species': String,
  'overall_freshness': String,
  'scan_mode': String,  // 'single', 'tray', 'single-fallback', etc.
}
```

### Scan Modes
- **auto** — pipeline decides based on box count
- **single** — one fish (best bbox or full frame fallback)
- **tray** — multiple fish, each cropped and classified separately

---

## Supported Classes

**File:** `assets/model/classes_flat.json`

6 species × 2 freshness states = 12 labels:

| Label (raw) | Species | Freshness |
|-------------|---------|-----------|
| `fresh__bigeye_scad` | Bigeye Scad | Fresh |
| `not_fresh__bigeye_scad` | Bigeye Scad | Not Fresh |
| `fresh__country_maiden` | Country Maiden | Fresh |
| `not_fresh__country_maiden` | Country Maiden | Not Fresh |
| `fresh__fringescale_sardinella` | Fringescale Sardinella | Fresh |
| `not_fresh__fringescale_sardinella` | Fringescale Sardinella | Not Fresh |
| `fresh__indian_mackerel` | Indian Mackerel | Fresh |
| `not_fresh__indian_mackerel` | Indian Mackerel | Not Fresh |
| `fresh__shortfin_scad` | Shortfin Scad | Fresh |
| `not_fresh__shortfin_scad` | Shortfin Scad | Not Fresh |
| `fresh__yellowfin_tuna` | Yellowfin Tuna | Fresh |
| `not_fresh__yellowfin_tuna` | Yellowfin Tuna | Not Fresh |

Confidence threshold: **0.40** — returns "Unknown" if below.

---

## Key File Paths

### ML / Core Services
| File | Purpose |
|------|---------|
| `lib/services/fish_pipeline.dart` | Orchestrates full detection + classification |
| `lib/services/fish_detector.dart` | YOLOv8 TFLite inference, NMS, bbox output |
| `lib/services/fish_classifier.dart` | ResNet50 TFLite inference, species/freshness |
| `lib/services/fishdet_config.dart` | Loads `fishdet_config.json` |
| `assets/model/fishdet_config.json` | YOLO thresholds, input size, model path |
| `assets/model/classes_flat.json` | Classifier label list |

### UI Screens
| File | Purpose |
|------|---------|
| `lib/main.dart` | App entry, SplashDirector routing, named routes |
| `lib/screens/home.dart` | Main hub, bottom nav, camera picker |
| `lib/screens/fish_scan_camera.dart` | Live camera preview with fish detection overlay |
| `lib/screens/fish_result_screen.dart` | Results display, PDF export, share |
| `lib/screens/gallery.dart` | Browse gallery, select image for scan |
| `lib/screens/history.dart` | Firestore-backed scan history |
| `lib/screens/almanac_screen.dart` | Fish species encyclopedia |
| `lib/screens/login.dart` | Email + Google OAuth login |
| `lib/screens/signup.dart` | User registration |
| `lib/screens/profile_screens.dart` | User profile |
| `lib/screens/profile_settings_screen.dart` | App settings |

### Widgets
| File | Purpose |
|------|---------|
| `lib/widgets/network_status_listener.dart` | Real-time connectivity stream |
| `lib/widgets/network_listener_banner.dart` | Offline banner widget |
| `lib/widgets/biometric_gate.dart` | Biometric auth gate wrapper |
| `lib/widgets/circular_transition.dart` | Circular reveal animation |

### Services / Storage
| File | Purpose |
|------|---------|
| `lib/services/save_scan_history.dart` | Saves scan results to Firestore |
| `lib/services/storage_service.dart` | SharedPreferences wrapper |
| `lib/services/network_monitor.dart` | Connectivity stream singleton |
| `lib/services/push_notification_service.dart` | FCM + local notifications setup |
| `lib/services/biometrics_service.dart` | local_auth Face ID / Fingerprint |

---

## Active TFLite Models

| Model | File | Size | Purpose |
|-------|------|------|---------|
| YOLOv8s OIV7 | `fishdet_fp32_2025-11-17_00-50-15.tflite` | ~44MB | Fish detection |
| ResNet50 (donkey) | `resnet50_torchvision_Mar_7_11-07_am_donkey_float32.tflite` | ~90MB | Species + freshness |

**Legacy/unused models** (in assets but not active):
- `resnet50_torchvision_Feb_12_6-39_pm_320inputsize_float32.tflite` — previous iteration
- Deleted models tracked in git (Dec 2024, Jan 2025 versions)

Current active branch: **donkey** (model trained Mar 7). The classifier model filename is set in `fish_classifier.dart` directly (not via a config JSON).

---

## Navigation & Architecture

**Routing (main.dart):**
- Named routes: `/onboarding`, `/login`, `/home`
- `SplashDirector` widget decides initial route:
  1. `onboarding_seen_v1` flag not set → `/onboarding`
  2. Firebase user exists → `/home`
  3. Silent Google sign-in succeeds → `/home`
  4. Else → `/login`

**State Management:** Singleton services + `StatefulWidget`
- `FishDetector.instance`, `FishClassifier.instance`, `FishPipeline.instance`
- `NetworkMonitor.instance` exposes a `Stream<bool>`
- No Provider/Riverpod/Bloc — pure singleton pattern

---

## Firebase / Firestore Structure

```
users/
  {uid}/
    firstName, lastName, email, photoUrl, createdAt
    scanHistory/
      {docId}/
        uid, species, freshness, frontImagePath, backImagePath,
        timestamp, confidence, summary (full pipeline result map)
```

---

## Assets Structure

```
assets/
  model/
    fishdet_config.json         ← YOLO config
    classes_flat.json           ← 12 classifier labels
    fishdet_fp32_*.tflite       ← Active YOLO model
    resnet50_*_donkey_*.tflite  ← Active ResNet model
    resnet50_*_320inputsize_*.tflite ← Legacy ResNet
  images/
    scan.png, logo*.png, fish_bg.jpg, fish_koi.png
    almanac_logo.png, freshness.png, market.png
    avatar.jpg, avatar1-5.png, google_logo.png
    indian_mackerel.jpg, yellowfin_tuna.jpg, bigeye_scad.JPG, ...
  icons/
    Icon-*.png
  kb/
    fishfresh_kb.txt            ← Fish knowledge base text
```

---

## Dev Notes

- **Debug crop saving:** `debugSaveCropToGallery` flag in `fish_pipeline.dart` — saves intermediate crops to device gallery
- **Tray mode filtering:** Filters boxes by area (≥ 1% of image) and aspect ratio (0.2–5.0), skips class index ~192 (non-fish YOLO class)
- **Legacy file:** `lib/services/fish_model.dart` — alternate classifier, references a model not in pubspec; likely unused
- **Empty file:** `lib/services/db_service.dart` — placeholder, no content
- **Interpreter threads:** Both YOLO and ResNet use 2 threads (`InterpreterOptions()..threads = 2`)
- **Input size:** ResNet reads input size dynamically from the TFLite tensor shape, not hardcoded
- **YOLOv8 output parsing:** Handles both NCHW and NHWC tensor layouts automatically
- **Image cache:** 150 items / 50MB limit configured in `main.dart`
- **Platforms:** Android/iOS are the primary targets; Windows/macOS/Linux/Web support is present but secondary
