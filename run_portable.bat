@echo off
rem ============================================================
rem   PythonTraderBot Control Center - Portable Launcher
rem   Starts the interface using the portable Python (.\python)
rem   created by install.bat / install_python_portable.ps1
rem ============================================================
title PythonTraderBot Control Center (Portable)
cd /d "%~dp0"

set "PY=%~dp0python\python.exe"

if not exist "%PY%" (
    echo [ERROR] Portable Python not found: %PY%
    echo.
    echo         Run install.bat first to download and set up
    echo         the portable Python and all required packages.
    echo.
    pause
    exit /b 1
)

echo ==================================================
echo   PythonTraderBot Control Center ^(Portable^)
echo ==================================================
echo.
echo [1/2] Checking installed packages ...
"%PY%" -c "import streamlit, pandas, numpy, ta, backtesting, yfinance, plotly, notebook, nbconvert" >nul 2>nul
if errorlevel 1 (
    echo       Some packages are missing - installing from requirements.txt ...
    echo       This may take several minutes.
    echo.
    "%PY%" -m pip install -r requirements.txt --no-warn-script-location
    if errorlevel 1 (
        echo.
        echo [ERROR] pip install failed. Check your internet connection.
        echo         Or run install.bat again.
        echo.
        pause
        exit /b 1
    )
) else (
    echo       All required packages are installed.
)
echo.

echo [2/2] Starting the interface ...
echo       The browser will open at http://localhost:8501
echo       Keep this window open - press Ctrl+C here to stop.
echo.
"%PY%" -m streamlit run dashboard/app.py

echo.
echo Interface stopped.
pause
