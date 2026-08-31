@echo off
rem ============================================================
rem   PythonTraderBot Control Center
rem   Portable Python Installer (runs install_python_portable.ps1)
rem
rem   - Downloads embeddable Python 3.14.3 (64-bit) into .\python
rem   - Installs pip inside that folder
rem   - Installs all packages from requirements.txt
rem   - No system-wide changes (delete .\python to remove)
rem ============================================================
title PythonTraderBot - Portable Python Installer
cd /d "%~dp0"

echo ==================================================
echo   PythonTraderBot Control Center
echo   Portable Python Installer
echo ==================================================
echo.
echo This will download Python 3.14.3 (embeddable, 64-bit)
echo and install all required packages into the "python" folder.
echo No system-wide changes will be made.
echo.

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install_python_portable.ps1" %*
set EXITCODE=%ERRORLEVEL%

echo.
if "%EXITCODE%"=="0" (
    echo ==================================================
    echo   Done. Double-click run_portable.bat to start.
    echo ==================================================
) else (
    echo ==================================================
    echo   Installation failed with exit code %EXITCODE%.
    echo   Check the messages above.
    echo ==================================================
)
echo.
pause
