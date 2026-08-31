@echo off
rem ============================================================
rem   PythonTraderBot Control Center - Windows Launcher
rem   اجرای مرکز کنترل روی ویندوز ۱۱
rem   ۱) پایتون را پیدا می‌کند  ۲) نصب بودن requirements.txt را چک می‌کند
rem   ۳) در صورت نیاز نصب می‌کند  ۴) اینترفیس را اجرا می‌کند
rem ============================================================
chcp 65001 >nul
title PythonTraderBot Control Center
cd /d "%~dp0"

echo ==================================================
echo      PythonTraderBot Control Center
echo      راه‌انداز مرکز کنترل (ویندوز)
echo ==================================================
echo.

rem ------------------- ۱) پیدا کردن پایتون -------------------
set "PYCMD=python"
python -c "import sys" >nul 2>nul
if not errorlevel 1 goto :pyok

set "PYCMD=py -3"
%PYCMD% -c "import sys" >nul 2>nul
if errorlevel 1 goto :nopy

:pyok
echo [1/4] پایتون پیدا شد:
%PYCMD% --version
echo.
goto :checkreq

:nopy
echo [خطا] پایتون پیدا نشد / Python not found
echo.
echo        پایتون 3.12 را از https://www.python.org/downloads/ نصب کنید
echo        و حتما تیک "Add python.exe to PATH" را موقع نصب بزنید.
echo.
pause
exit /b 1

rem --------------- ۲) چک نصب requirements.txt ---------------
:checkreq
echo [2/4] بررسی نصب پکیج‌های موردنیاز ...
%PYCMD% -c "import streamlit, pandas, numpy, ta, backtesting, yfinance, plotly, matplotlib, seaborn, scipy, sklearn, xgboost, joblib, colorama, tqdm, requests, feedparser, bs4, vaderSentiment, notebook, nbconvert" >nul 2>nul
if not errorlevel 1 goto :reqok

echo        بعضی پکیج‌ها نصب نیستند — نصب از requirements.txt ...
echo        (چند دقیقه طول می‌کشد؛ به اینترنت نیاز دارد)
echo.
%PYCMD% -m pip install -r requirements.txt
if errorlevel 1 goto :pipfail
echo.
goto :checkta

:reqok
echo        همهٔ پکیج‌های موردنیاز نصب هستند.
echo.
goto :checkta

:pipfail
echo.
echo [خطا] نصب پکیج‌ها ناموفق بود. اتصال اینترنت را بررسی کنید.
echo        دستور اجرای دستی:  python -m pip install -r requirements.txt
echo.
pause
exit /b 1

rem ---------- ۳) بررسی اختیاری pandas-ta (پایتون ۳.۱۲) ----------
:checkta
%PYCMD% -c "import pandas_ta" >nul 2>nul
if errorlevel 1 (
    echo [توجه] pandas-ta نصب نیست.
    echo        فقط برای ربات‌های TraderBot و CE_ZLSMA لازم است و پایتون 3.12+ می‌خواهد.
    echo        نصب دستی:  python -m pip install pandas-ta
    echo.
)

rem ------------------- ۴) اجرای اینترفیس -------------------
echo [3/4] در حال اجرای اینترفیس ...
echo        مرورگر به‌زودی روی http://localhost:8501 باز می‌شود.
echo        این پنجره را باز نگه دارید — برای توقف Ctrl+C بزنید.
echo.
echo [4/4] اجرا ...
%PYCMD% -m streamlit run dashboard/app.py

echo.
echo اینترفیس متوقف شد.
pause
