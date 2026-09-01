@echo off
rem ============================================================
rem   PythonTraderBot Control Center - Launcher
rem   1) Finds Python (python / py -3)
rem   2) Checks that requirements.txt packages are installed
rem   3) Installs them if missing
rem   4) Starts the interface (Streamlit)
rem ============================================================
title PythonTraderBot Control Center
cd /d "%~dp0"

echo ==================================================
echo      PythonTraderBot Control Center
echo      Streamlit Interface Launcher
echo ==================================================
echo.

rem ------------------- 1) find python -------------------
set "PYCMD=python"
python -c "import sys" >nul 2>nul
if not errorlevel 1 goto :pyok

set "PYCMD=py -3"
%PYCMD% -c "import sys" >nul 2>nul
if errorlevel 1 goto :nopy

:pyok
echo [1/4] Python found:
%PYCMD% --version
echo.
goto :checkreq

:nopy
echo [ERROR] Python not found.
echo.
echo        Install Python 3.12 or newer from https://www.python.org/downloads/
echo        and make sure "Add python.exe to PATH" is checked during install.
echo.
echo        (Alternative: use install.bat to set up a portable Python
echo         inside this folder - no system installation needed.)
echo.
pause
exit /b 1

rem --------------- 2) check requirements.txt ---------------
:checkreq
echo [2/4] Checking required packages ...
%PYCMD% -c "import streamlit, pandas, numpy, ta, backtesting, yfinance, plotly, matplotlib, seaborn, scipy, sklearn, xgboost, joblib, colorama, tqdm, requests, feedparser, bs4, vaderSentiment, notebook, nbconvert" >nul 2>nul
if not errorlevel 1 goto :reqok

echo        Some packages are missing - installing from requirements.txt ...
echo        (this may take several minutes and needs an internet connection)
echo.
%PYCMD% -m pip install -r requirements.txt
if errorlevel 1 goto :pipfail
echo.
goto :checkta

:reqok
echo        All required packages are installed.
echo.
goto :checkta

:pipfail
echo.
echo [ERROR] pip install failed. Check your internet connection.
echo         Manual command:  python -m pip install -r requirements.txt
echo.
pause
exit /b 1

rem ---------- 3) optional pandas-ta (Python 3.12+) ----------
:checkta
%PYCMD% -c "import pandas_ta" >nul 2>nul
if errorlevel 1 (
    echo [NOTE] pandas-ta is not installed.
    echo        It is only needed for the TraderBot / CE_ZLSMA bots
    echo        and works on Python 3.12 / 3.13 only (its numba
    echo        dependency does not support Python 3.14 yet).
    echo        Install it with:  python -m pip install pandas-ta
    echo.
)

rem ------------------- 4) start interface -------------------
echo [3/4] Starting the interface ...
echo        The browser will open at http://localhost:8501
echo        Keep this window open - press Ctrl+C here to stop.
echo.
echo [4/4] Launching ...
%PYCMD% -m streamlit run dashboard/app.py

echo.
echo Interface stopped.
pause
