@echo off
setlocal enableextensions enabledelayedexpansion

rem =========================
rem YOLOv8 ONNX -> TFLite (FP32 + FP16) converter for Windows
rem - Works best with *pre-NMS* ONNX exported at imgsz=640
rem - Creates its own venv with pinned deps for TF 2.16.1
rem Usage:
rem   convert_yolov8_onnx_to_tflite.bat path\to\fishdet_yolov8n_oiv7.onnx out_dir
rem =========================

if "%~1"=="" (
  echo [USAGE] %~nx0 ^<model.onnx^> ^<out_dir^>
  exit /b 1
)
set "ONNX_IN=%~1"
if not exist "%ONNX_IN%" (
  echo [ERROR] ONNX file not found: %ONNX_IN%
  exit /b 1
)

set "OUT_DIR=%~2"
if "%OUT_DIR%"=="" set "OUT_DIR=%~dp1out_tflite"
if not exist "%OUT_DIR%" mkdir "%OUT_DIR%" >nul 2>&1

echo [*] ONNX_IN  = %ONNX_IN%
echo [*] OUT_DIR  = %OUT_DIR%

rem --- choose Python (3.10 or 3.11 recommended) ---
where py >nul 2>&1 || (echo [ERROR] Python launcher 'py' not found && exit /b 1)
for /f "tokens=2 delims= " %%v in ('py -0p ^| findstr /r "3\.11 3\.10" ^| findstr "*"') do set "PYEXE=%%v"
if "%PYEXE%"=="" for /f "tokens=2 delims= " %%v in ('py -0p ^| findstr /r "3\.11 3\.10"') do set "PYEXE=%%v"
if "%PYEXE%"=="" (
  echo [ERROR] Python 3.10/3.11 not found. Install one of them.
  exit /b 1
)
echo [*] Using Python: %PYEXE%

rem --- venv under out_dir ---
set "VENV=%OUT_DIR%\.yolo2tfl"
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creating venv...
  "%PYEXE%" -m venv "%VENV%" || (echo [ERROR] venv creation failed && exit /b 1)
)
set "PIP=%VENV%\Scripts\pip.exe"
set "PY=%VENV%\Scripts\python.exe"

echo [*] Upgrading pip/setuptools...
"%PY%" -m pip install --upgrade pip setuptools wheel --quiet

echo [*] Installing pinned deps (this may take a few minutes)...
"%PIP%" install --prefer-binary ^
  "numpy==1.26.4" "ml-dtypes==0.3.2" ^
  "tensorflow-cpu==2.16.1" "tf-keras==2.16.0" ^
  "onnx==1.16.1" "onnxruntime" "onnxslim==0.1.74" "onnxsim" ^
  "onnx2tf==1.26.3" "onnx-graphsurgeon==0.5.8" "sng4onnx==1.0.1" "psutil==5.9.8" --quiet
if errorlevel 1 (
  echo [ERROR] Dependency installation failed.
  exit /b 1
)

rem --- paths ---
set "ONNX_SIM=%OUT_DIR%\model_sim.onnx"
set "TF_DIR=%OUT_DIR%\tf_savedmodel"
set "TFL_FP32=%OUT_DIR%\yolov8_fp32.tflite"
set "TFL_FP16=%OUT_DIR%\yolov8_fp16.tflite"

echo [*] Simplifying ONNX...
"%PY%" -m onnxsim "%ONNX_IN%" "%ONNX_SIM%" --overwrite-input-shape 1,3,640,640
if errorlevel 1 (
  echo [WARN] onnxsim failed or not needed, using original ONNX.
  set "ONNX_SIM=%ONNX_IN%"
)

echo [*] Converting ONNX -> TF SavedModel (onnx2tf)...
"%PY%" -m onnx2tf -i "%ONNX_SIM%" -o "%TF_DIR%" -v info
if errorlevel 1 (
  echo [ERROR] onnx2tf conversion failed.
  exit /b 1
)

echo [*] Converting TF SavedModel -> TFLite (FP32 + FP16)...
"%PY%" "%~dp0\_yolo_onnx2tflite_helper.py" "%TF_DIR%" "%TFL_FP32%" "%TFL_FP16%"
if errorlevel 1 (
  echo [ERROR] TFLite conversion failed.
  exit /b 1
)

echo.
echo [✓] Done.
echo [i] Files:
echo     %TFL_FP32%
echo     %TFL_FP16%
exit /b 0
