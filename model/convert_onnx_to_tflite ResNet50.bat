@echo on
setlocal enableextensions enabledelayedexpansion

rem ========= CONFIG =========
set "ROOT=C:\aziztebbeng\2025-CP_Fishfresh\model"
set "MODELS=%ROOT%\models"
set "VENV=%ROOT%\.tfliteenv"
set "OUT=%MODELS%\tf_resnet50"
set "TMP=C:\piptmp"

if not exist "%MODELS%" (
  echo [ERROR] Models folder not found: "%MODELS%"
  pause & exit /b 1
)
if not exist "%TMP%" mkdir "%TMP%" >nul 2>&1

rem --- ensure Python 3.10 + venv ---
py -3.10 -V || (echo [ERROR] Install Python 3.10 && pause && exit /b 1)
if not exist "%VENV%\Scripts\python.exe" (
  echo [*] Creating venv...
  py -3.10 -m venv "%VENV%" || (pause & exit /b 1)
)

call "%VENV%\Scripts\activate.bat" || (echo [ERROR] venv activate failed & pause & exit /b 1)

echo [*] Upgrading pip...
python -m pip install --upgrade pip >nul

echo [*] Installing converter deps...
pip install --no-cache-dir tensorflow-cpu==2.15.1 onnx2tf==1.27.0 onnx==1.16.1 ml-dtypes==0.3.1 onnxruntime==1.18.0 onnx-graphsurgeon==0.5.8 sng4onnx psutil tf-keras==2.15.1 onnxsim==0.4.36 >nul || (
  echo [ERROR] deps install failed
  pause & exit /b 1
)

rem --- STUB ai_edge_litert ---
echo [*] Stubbing ai_edge_litert...
python -c "import site,os; p=[x for x in site.getsitepackages() if 'site-packages' in x][0]; d=os.path.join(p,'ai_edge_litert'); os.makedirs(d,exist_ok=True); open(os.path.join(d,'__init__.py'),'w').write(''); open(os.path.join(d,'interpreter.py'),'w').write('from tensorflow.lite.python.interpreter import Interpreter, load_delegate')" || (
  echo [ERROR] stub failed
  pause & exit /b 1
)

rem ========= INTERACTIVE FILE PICKER =========
echo.
echo [*] Listing available ONNX models...
set /a count=0
for /f "delims=" %%F in ('dir /b /a:-d /o-d "%MODELS%\*.onnx" 2^>nul') do (
  set /a count+=1
  set "ONNX[!count!]=%%F"
)
if %count%==0 (
  echo [ERROR] No .onnx found in "%MODELS%"
  pause & exit /b 1
)
echo.
for /l %%i in (1,1,%count%) do echo   %%i^) !ONNX[%%i]!
echo.
set /p choice=Enter number to convert [1-%count%]: 
if not defined choice set "choice=1"
if not defined ONNX[%choice%] (
  echo Invalid choice.
  pause & exit /b 1
)
set "ONNX_FILE=!ONNX[%choice%]!"
echo [*] Selected: "%ONNX_FILE%"

rem ========= CREATE PYTHON PATCHER FILE =========
set "PATCHPY=%TMP%\fix_rgba_to_rgb.py"
echo import onnx, onnx_graphsurgeon as gs, numpy as np, os> "%PATCHPY%"
echo f = r"%MODELS%\%ONNX_FILE%">> "%PATCHPY%"
echo m = onnx.load(f)>> "%PATCHPY%"
echo g = gs.import_onnx(m)>> "%PATCHPY%"
echo x = g.inputs[0]>> "%PATCHPY%"
echo dims = list(x.shape) if hasattr(x, "shape") else []>> "%PATCHPY%"
echo use_path = f>> "%PATCHPY%"
echo changed = False>> "%PATCHPY%"
echo if len(dims)==4:>> "%PATCHPY%"
echo ^    if dims[-1]==4:>> "%PATCHPY%"
echo ^        print("[*] NHWC 4-channel input detected. Patching to RGB3...")>> "%PATCHPY%"
echo ^        starts = gs.Constant("starts", np.array([0,0,0,0], np.int64))>> "%PATCHPY%"
echo ^        ends = gs.Constant("ends", np.array([9223372036854775807,9223372036854775807,9223372036854775807,3], np.int64))>> "%PATCHPY%"
echo ^        axes = gs.Constant("axes", np.array([0,1,2,3], np.int64))>> "%PATCHPY%"
echo ^        steps = gs.Constant("steps", np.array([1,1,1,1], np.int64))>> "%PATCHPY%"
echo ^        sliced = gs.Variable("x_rgb3", dtype=x.dtype)>> "%PATCHPY%"
echo ^        g.layer(op="Slice", inputs=[x, starts, ends, axes, steps], outputs=[sliced], name="slice_rgba_to_rgb")>> "%PATCHPY%"
echo ^        for n in g.nodes: n.inputs = [sliced if i is x else i for i in n.inputs]>> "%PATCHPY%"
echo ^        g.cleanup().toposort()>> "%PATCHPY%"
echo ^        use_path = os.path.splitext(f)[0] + "_rgb3.onnx">> "%PATCHPY%"
echo ^        onnx.save(gs.export_onnx(g), use_path)>> "%PATCHPY%"
echo ^        changed = True>> "%PATCHPY%"
echo ^    elif dims[1]==4:>> "%PATCHPY%"
echo ^        print("[*] NCHW 4-channel input detected. Patching to RGB3...")>> "%PATCHPY%"
echo ^        starts = gs.Constant("starts", np.array([0,0,0,0], np.int64))>> "%PATCHPY%"
echo ^        ends = gs.Constant("ends", np.array([9223372036854775807,3,9223372036854775807,9223372036854775807], np.int64))>> "%PATCHPY%"
echo ^        axes = gs.Constant("axes", np.array([0,1,2,3], np.int64))>> "%PATCHPY%"
echo ^        steps = gs.Constant("steps", np.array([1,1,1,1], np.int64))>> "%PATCHPY%"
echo ^        sliced = gs.Variable("x_rgb3", dtype=x.dtype)>> "%PATCHPY%"
echo ^        g.layer(op="Slice", inputs=[x, starts, ends, axes, steps], outputs=[sliced], name="slice_rgba_to_rgb")>> "%PATCHPY%"
echo ^        for n in g.nodes: n.inputs = [sliced if i is x else i for i in n.inputs]>> "%PATCHPY%"
echo ^        g.cleanup().toposort()>> "%PATCHPY%"
echo ^        use_path = os.path.splitext(f)[0] + "_rgb3.onnx">> "%PATCHPY%"
echo ^        onnx.save(gs.export_onnx(g), use_path)>> "%PATCHPY%"
echo ^        changed = True>> "%PATCHPY%"
echo if not changed:>> "%PATCHPY%"
echo ^    print("[*] Input already 3-channel; using original")>> "%PATCHPY%"
echo print(use_path)>> "%PATCHPY%"

rem ========= RUN PATCHER =========
for /f "delims=" %%A in ('python "%PATCHPY%"') do set "ONNX_PATH=%%A"

if not defined ONNX_PATH (
  echo [ERROR] Failed to patch or find ONNX file.
  pause & exit /b 1
)

rem echo [*] Using ONNX: "%ONNX_PATH%"

rem if exist "%OUT%" (
rem   echo [*] Cleaning old output folder...
rem   rmdir /s /q "%OUT%"
rem )

echo [*] Converting: "%ONNX_PATH%"
python -m onnx2tf -i "%ONNX_PATH%" -o "%OUT%" --copy_onnx_input_output_names_to_tflite || (
  echo [ERROR] onnx2tf failed.
  pause & exit /b 1
)

echo [*] Creating Float16 variant...
python -c "import tensorflow as tf, pathlib; sm=r'%OUT%\saved_model'; out=r'%OUT%\model_float16.tflite'; c=tf.lite.TFLiteConverter.from_saved_model(sm); c.optimizations=[tf.lite.Optimize.DEFAULT]; c.target_spec.supported_types=[tf.float16]; pathlib.Path(out).write_bytes(c.convert())" || echo [!] Skipped Float16.

echo.
echo [OK] TFLite files:
dir "%OUT%\*.tflite"
start "" "%OUT%"
pause
