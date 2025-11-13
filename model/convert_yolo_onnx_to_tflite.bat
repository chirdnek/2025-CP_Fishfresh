@echo off
setlocal enabledelayedexpansion

REM ===== CONFIG =====
set "ROOT=C:\aziztebbeng\2025-CP_Fishfresh\model"
set "VENV=%ROOT%\.yolotf"
set "PYTHON=%VENV%\Scripts\python.exe"
set "EXPORT_DIR=%ROOT%\runs_fishdet\export"

echo.
echo ================================
echo   YOLOv8 ONNX → TFLite Converter
echo ================================
echo.

REM Check Python
if not exist "%PYTHON%" (
    echo [ERROR] Python not found:
    echo        "%PYTHON%"
    pause
    exit /b 1
)

REM Check ONNX directory
if not exist "%EXPORT_DIR%" (
    echo [ERROR] Export directory not found:
    echo        "%EXPORT_DIR%"
    pause
    exit /b 1
)

echo ONNX files found in:
echo %EXPORT_DIR%
echo.

REM List ONNX files
set count=0
for %%F in ("%EXPORT_DIR%\*.onnx") do (
    set /a count+=1
    set "file[!count!]=%%~nxF"
)

if %count%==0 (
    echo [ERROR] No ONNX file found.
    pause
    exit /b 1
)

echo Select ONNX file to convert:
echo --------------------------------------

for /l %%i in (1,1,%count%) do (
    echo   %%i^) !file[%%i]!
)

echo --------------------------------------
set /p choice=Enter number:

REM Validate choice
if "%choice%"=="" (
    echo [ERROR] No selection.
    pause
    exit /b 1
)

if %choice% GTR %count% (
    echo [ERROR] Invalid choice.
    pause
    exit /b 1
)

set "ONNX=%EXPORT_DIR%\!file[%choice%]!"

echo.
echo [*] Selected ONNX:
echo     "%ONNX%"
echo.

REM Run converter script
"%PYTHON%" "%ROOT%\yolo_onnx_to_tflite.py" "%ONNX%" "%EXPORT_DIR%"

if errorlevel 1 (
    echo.
    echo [ERROR] Conversion failed.
    pause
    exit /b 1
)

echo.
echo [✓] Conversion complete!
echo [✓] Saved TFLite files in:
echo     %EXPORT_DIR%
echo.
pause
