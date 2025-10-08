@echo on
setlocal enableextensions enabledelayedexpansion

rem ========= CONFIG (edit ROOT only if your folder moved) =========
set "ROOT=C:\aziztebbeng\2025-CP_Fishfresh\model"
set "MODELS=%ROOT%\models"
set "VENV=%ROOT%\.tfliteenv"
set "OUT=%MODELS%\tf_mbv2"

if not exist "%MODELS%" (
  echo [ERROR] Models folder not found: "%MODELS%"
  pause & exit /b 1
)

rem --- ensure Python 3.10 + venv ---
py -3.10 -V || (echo [ERROR] Install Python 3.10 && pause && exit /b 1)
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creating venv...
  py -3.10 -m venv "%VENV%" || (pause & exit /b 1)
)

call "%VENV%\Scripts\activate.bat" || (echo [ERROR] venv activate failed & pause & exit /b 1)
set "TMP=C:\piptmp" & set "TEMP=C:\piptmp" & if not exist "%TMP%" mkdir "%TMP%" >nul 2>&1

echo [*] Upgrading pip...
python -m pip install --upgrade pip

echo [*] Installing converter deps (stable stack)...
pip install --no-cache-dir tensorflow-cpu==2.15.1 onnx2tf==1.27.0 onnx==1.16.1 ml-dtypes==0.3.1 onnxruntime==1.18.0 onnx-graphsurgeon==0.5.8 sng4onnx psutil tf-keras==2.15.1 || (echo [ERROR] deps install failed & pause & exit /b 1)

rem --- STUB ai_edge_litert (instant) ---
echo [*] Stubbing ai_edge_litert...
python -c "import site,os; p=[x for x in site.getsitepackages() if 'site-packages' in x][0]; d=os.path.join(p,'ai_edge_litert'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').write(''); open(os.path.join(d,'interpreter.py'),'w').write('from tensorflow.lite.python.interpreter import Interpreter, load_delegate'); print('ai_edge_litert stub ready at', d)" || (echo [ERROR] stub failed & pause & exit /b 1)

rem --- pick newest .onnx ---
set "ONNX_FILE="
for /f "delims=" %%F in ('dir /b /o-d "%MODELS%\*.onnx" 2^>nul') do (set "ONNX_FILE=%%F" & goto :found)
:found
if not defined ONNX_FILE (
  echo [ERROR] No .onnx found in "%MODELS%"
  pause & exit /b 1
)
echo [*] Converting: "%MODELS%\%ONNX_FILE%"

if exist "%OUT%" rmdir /s /q "%OUT%"
python -m onnx2tf -i "%MODELS%\%ONNX_FILE%" -o "%OUT%" --copy_onnx_input_output_names_to_tflite || (echo [ERROR] onnx2tf failed & pause & exit /b 1)

echo [*] Creating Float16 variant...
python -c "import tensorflow as tf, pathlib; sm=r'%OUT%\saved_model'; out=r'%OUT%\model_float16.tflite'; c=tf.lite.TFLiteConverter.from_saved_model(sm); c.optimizations=[tf.lite.Optimize.DEFAULT]; c.target_spec.supported_types=[tf.float16]; pathlib.Path(out).write_bytes(c.convert())" || echo [!] Skipped Float16.

echo.
echo [OK] TFLite files:
dir "%OUT%\*.tflite"
start "" "%OUT%"
pause
