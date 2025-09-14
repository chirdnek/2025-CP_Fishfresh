@echo off
setlocal enableextensions enabledelayedexpansion

REM === PATHS ===
set "ROOT=C:\Users\LENOVO\Desktop\2025-CP_Fishfresh\model"
set "MODELS=%ROOT%\models"
set "VENV=%ROOT%\.tfliteenv"
set "OUT=%MODELS%\tf_mbv2"

REM === Ensure Python 3.10 venv exists ===
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creating venv at "%VENV%" ...
  py -3.10 -m venv "%VENV%" || (
    echo [!] Python 3.10 not found. Install it (winget install -e --id Python.Python.3.10) and re-run.
    pause & exit /b 1
  )
)

REM === Activate venv ===
call "%VENV%\Scripts\activate.bat"
set "TMP=C:\piptmp"
set "TEMP=C:\piptmp"
if not exist "%TMP%" mkdir "%TMP%" >nul 2>&1
python -m pip install --upgrade pip >nul

REM === Install stable toolchain ===
echo [*] Installing/refreshing converter dependencies...
pip install --no-cache-dir ^
  tensorflow-cpu==2.15.1 ^
  onnx2tf==1.27.0 ^
  onnx==1.16.1 ^
  ml-dtypes==0.3.1 ^
  onnxruntime==1.18.0 ^
  onnx-graphsurgeon==0.5.8 ^
  sng4onnx ^
  psutil ^
  tf-keras==2.15.1

REM === Stub ai_edge_litert so onnx2tf can import it everywhere ===
python -c "import site,os; p=[x for x in site.getsitepackages() if 'site-packages' in x][0]; d=os.path.join(p,'ai_edge_litert'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').write(''); open(os.path.join(d,'interpreter.py'),'w').write('from tensorflow.lite.python.interpreter import Interpreter, load_delegate')" >nul 2>&1

REM === Find newest .onnx ===
set "ONNX_FILE="
for /f "delims=" %%F in ('dir /b /o-d "%MODELS%\*.onnx" 2^>nul') do (
  set "ONNX_FILE=%%F"
  goto :found
)
:found
if not defined ONNX_FILE (
  echo [!] No .onnx found in "%MODELS%".
  pause & exit /b 1
)
echo [*] Using ONNX: "%MODELS%\%ONNX_FILE%"

REM === Convert ONNX -> TF SavedModel -> TFLite ===
if exist "%OUT%" rmdir /s /q "%OUT%" >nul 2>&1
echo [*] Converting to TFLite (float32)...
python -m onnx2tf -i "%MODELS%\%ONNX_FILE%" -o "%OUT%" --copy_onnx_input_output_names_to_tflite || (
  echo [!] onnx2tf failed.
  pause & exit /b 1
)

REM === Also create a Float16 variant from the SavedModel ===
echo [*] Creating Float16 TFLite...
python -c "import tensorflow as tf, pathlib; sm=r'%OUT%\saved_model'; out=r'%OUT%\model_float16.tflite'; c=tf.lite.TFLiteConverter.from_saved_model(sm); c.optimizations=[tf.lite.Optimize.DEFAULT]; c.target_spec.supported_types=[tf.float16]; pathlib.Path(out).write_bytes(c.convert())" || echo [!] Float16 conversion skipped.

echo.
echo [OK] TFLite files:
dir "%OUT%\*.tflite"
echo.
start "" "%OUT%"
echo Done.
pause
