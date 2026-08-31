<#
.SYNOPSIS
    Portable Python installer for PythonTraderBot Control Center.

.DESCRIPTION
    1. Downloads the Windows embeddable Python package (64-bit) into the
       program folder (.\python) - no system-wide installation, no registry
       changes, no PATH changes.
    2. Installs pip INSIDE that portable folder (via get-pip.py).
    3. Installs all packages from requirements.txt into the portable Python.

    Everything stays inside the program folder. To remove it later,
    simply delete the "python" folder.

.PARAMETER PythonVersion
    Python version to download. Default: 3.14.3

.PARAMETER InstallDir
    Target folder for the portable Python. Default: .\python (next to this script)

.PARAMETER Force
    Delete the existing portable Python folder and reinstall from scratch.

.EXAMPLE
    .\install_python_portable.ps1
    .\install_python_portable.ps1 -PythonVersion 3.13.15
    .\install_python_portable.ps1 -Force
#>

param(
    [string]$PythonVersion = "3.14.3",
    [string]$InstallDir = "",
    [switch]$Force
)

$ErrorActionPreference = "Stop"
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }

if (-not $InstallDir) { $InstallDir = Join-Path $PSScriptRoot "python" }

$PythonZipName   = "python-$PythonVersion-embed-amd64.zip"
$PythonZipUrl    = "https://www.python.org/ftp/python/$PythonVersion/$PythonZipName"
$GetPipUrl       = "https://bootstrap.pypa.io/get-pip.py"
$RequirementsTxt = Join-Path $PSScriptRoot "requirements.txt"
$PythonExe       = Join-Path $InstallDir "python.exe"
$TempDir         = Join-Path $env:TEMP "ptb_portable_setup"

function Step  { param($msg) Write-Host ""; Write-Host "[*] $msg" -ForegroundColor Cyan }
function Ok    { param($msg) Write-Host "    $msg" -ForegroundColor Green }
function Info  { param($msg) Write-Host "    $msg" -ForegroundColor Gray }
function Fail  { param($msg) Write-Host "[ERROR] $msg" -ForegroundColor Red }

function Invoke-PythonCheck {
    # Runs the portable python with the given arguments, hides its output and
    # returns ONLY the exit code.
    #
    # IMPORTANT: do NOT use "2>$null" directly on a native command while
    # $ErrorActionPreference is "Stop" (the default in this script). Windows
    # PowerShell 5.1 turns the first stderr line - e.g. "No module named pip" -
    # into a terminating NativeCommandError and KILLS the whole script.
    # (Fixed behaviour in PowerShell 7+, but the default on Windows 11 is 5.1.)
    # Inside this function we temporarily relax the preference, which makes the
    # redirected stderr harmless.
    param([string[]]$Arguments)
    $prev = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        & $PythonExe @Arguments 2>$null | Out-Null
        return $LASTEXITCODE
    } catch {
        return 1
    } finally {
        $ErrorActionPreference = $prev
    }
}

function Download-File {
    param([string]$Url, [string]$OutFile)
    try {
        # try the faster/quieter .NET client first
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Url, $OutFile)
    } catch {
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -UseBasicParsing
    }
}

Write-Host "==================================================" -ForegroundColor DarkCyan
Write-Host "   PythonTraderBot Control Center"                    -ForegroundColor White
Write-Host "   Portable Python $PythonVersion Installer"               -ForegroundColor White
Write-Host "==================================================" -ForegroundColor DarkCyan

# ---------------------------------------------------------------- checks ----
if (-not (Test-Path $RequirementsTxt)) {
    Fail "requirements.txt not found next to this script: $RequirementsTxt"
    Fail "Put this file in the main program folder (next to requirements.txt)."
    exit 1
}

# ------------------------------------------------- 1) portable python -------
Step "Step 1/4 - Portable Python ($PythonVersion embeddable, 64-bit)"

if ((Test-Path $PythonExe) -and $Force) {
    Info "Removing existing portable Python (-Force) ..."
    Remove-Item -Recurse -Force $InstallDir
}

if (Test-Path $PythonExe) {
    Ok "Portable Python already exists - skipping download."
    & $PythonExe --version
} else {
    Info "Downloading: $PythonZipUrl"
    Info "(about 12 MB - please wait)"
    if (-not (Test-Path $TempDir)) { New-Item -ItemType Directory -Path $TempDir | Out-Null }
    $ZipPath = Join-Path $TempDir $PythonZipName
    try {
        Download-File -Url $PythonZipUrl -OutFile $ZipPath
    } catch {
        Fail "Could not download Python: $($_.Exception.Message)"
        Fail "Check your internet connection and the version number."
        exit 1
    }
    if (-not (Test-Path $ZipPath)) {
        Fail "Download failed (file not found)."
        exit 1
    }
    Ok "Download complete."

    Info "Extracting to: $InstallDir"
    try {
        # Note: .NET Framework's ExtractToDirectory requires the destination
        # folder NOT to exist - it creates it by itself.
        if (Test-Path $InstallDir) { Remove-Item -Recurse -Force $InstallDir }
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $InstallDir)
    } catch {
        Fail "Could not extract the zip: $($_.Exception.Message)"
        exit 1
    }
    if (-not (Test-Path $PythonExe)) {
        Fail "python.exe not found after extraction."
        exit 1
    }
    Ok "Extracted."
    & $PythonExe --version
}

# ------------------------------------------------------- 2) enable site -----
Step "Step 2/4 - Enabling site-packages for the embeddable Python"

$PthFile = Get-ChildItem -Path $InstallDir -Filter "python*._pth" | Select-Object -First 1
if ($null -eq $PthFile) {
    Fail "python*._pth file not found inside $InstallDir"
    exit 1
}
$PthContent = Get-Content $PthFile.FullName -Raw
if ($PthContent -match "(?m)^import\s+site") {
    Ok "Already enabled."
} else {
    Add-Content -Path $PthFile.FullName -Value "import site"
    Ok "Enabled site-packages ($($PthFile.Name))."
}

# ------------------------------------------------------------- 3) pip -------
Step "Step 3/4 - Installing pip (inside the portable folder)"

if ((Invoke-PythonCheck @("-m", "pip", "--version")) -eq 0) {
    Ok "pip already installed."
} else {
    Info "pip is not installed yet - installing it with get-pip.py ..."
    Info "Downloading: $GetPipUrl"
    $GetPipPath = Join-Path $TempDir "get-pip.py"
    try {
        Download-File -Url $GetPipUrl -OutFile $GetPipPath
    } catch {
        Fail "Could not download get-pip.py: $($_.Exception.Message)"
        exit 1
    }
    Info "Running get-pip.py ..."
    & $PythonExe $GetPipPath --no-warn-script-location
    if ($LASTEXITCODE -ne 0) {
        Fail "get-pip.py failed."
        exit 1
    }
    # verify that pip is now really importable; if not, show the ._pth file
    # content so the problem is easy to diagnose.
    if ((Invoke-PythonCheck @("-m", "pip", "--version")) -ne 0) {
        Fail "pip was installed but python cannot import it."
        Info "Content of $($PthFile.Name) for diagnosis:"
        Get-Content $PthFile.FullName | ForEach-Object { Info "    $_" }
        exit 1
    }
    Ok "pip installed."
}

Info "Upgrading pip / setuptools / wheel ..."
& $PythonExe -m pip install --upgrade pip setuptools wheel --no-warn-script-location --quiet
if ($LASTEXITCODE -ne 0) {
    Info "(upgrade skipped - continuing with the current version)"
}

# --------------------------------------------------- 4) requirements --------
Step "Step 4/4 - Installing packages from requirements.txt"
Info "This can take several minutes (about 200-300 MB of downloads)."

& $PythonExe -m pip install -r $RequirementsTxt --no-warn-script-location
if ($LASTEXITCODE -ne 0) {
    Fail "pip install failed. Check your internet connection and try again."
    Fail "You can retry with:  python\python.exe -m pip install -r requirements.txt"
    exit 1
}
Ok "All packages installed."

# ---------------------------------------------------------- verify ----------
Step "Verifying installation"

& $PythonExe -c "import sys; print('    Python : ' + sys.version.split()[0])"
& $PythonExe -c "import streamlit; print('    streamlit : OK')"
& $PythonExe -c "import pandas; print('    pandas : OK')"
& $PythonExe -c "import numpy; print('    numpy : OK')"
& $PythonExe -c "import backtesting; print('    backtesting : OK')"
& $PythonExe -c "import notebook; print('    jupyter notebook : OK')"
& $PythonExe -c "import yfinance; print('    yfinance : OK')"

if ((Invoke-PythonCheck @("-c", "import pandas_ta")) -eq 0) {
    & $PythonExe -c "import pandas_ta; print('    pandas-ta : OK')"
} else {
    Info "pandas-ta not installed (only needed for TraderBot / CE_ZLSMA bots)."
}

if ((Invoke-PythonCheck @("-c", "import MetaTrader5")) -eq 0) {
    & $PythonExe -c "import MetaTrader5; print('    MetaTrader5 : OK')"
} else {
    Info "MetaTrader5 not installed (only needed for the MT5 bots)."
}

# ---------------------------------------------------------- summary ---------
Write-Host ""
Write-Host "==================================================" -ForegroundColor DarkGreen
Write-Host "   Portable Python installed successfully."           -ForegroundColor Green
Write-Host "==================================================" -ForegroundColor DarkGreen
Write-Host ""
Write-Host "Next steps:" -ForegroundColor White
Write-Host "  1. Double-click  run_portable.bat  to start the interface"
Write-Host "     (or run:  python\python.exe -m streamlit run dashboard/app.py)"
Write-Host "  2. The browser opens at http://localhost:8501"
Write-Host ""
Write-Host "To remove the portable Python later, just delete the 'python' folder."
Write-Host ""

exit 0
