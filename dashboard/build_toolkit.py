# -*- coding: utf-8 -*-
"""ساخت فایل ZIP کامل پکیج (کد ربات‌ها + اینترفیس + requirements + راهنما)"""
import zipfile
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLKIT_DIR = Path(__file__).resolve().parent / "toolkit"
ZIP_PATH = TOOLKIT_DIR / "PythonTraderBot_ControlCenter.zip"

EXCLUDE_DIRS = {"myenv", "__pycache__", ".git", ".ipynb_checkpoints", "logs",
                "toolkit", ".streamlit", ".cache", "build", "dist"}
EXCLUDE_FILES = {".gitignore", ".DS_Store"}
EXCLUDE_SUFFIX = {".pyc", ".pyo", ".exe", ".zip", ".log", ".pptx"}
INCLUDE_ROOT_FILES = {"requirements.txt", "README.md", "LICENSE", "START_HERE_FA.md",
                      "run.bat", "install.bat", "run_portable.bat",
                      "install_python_portable.ps1"}


def _iter_files():
    # فایل‌های ریشهٔ ریپو
    for f in REPO_ROOT.iterdir():
        if f.is_file() and f.name in INCLUDE_ROOT_FILES:
            yield f, f.name
    # پوشه‌های اصلی
    for folder in ["code", "dashboard"]:
        base = REPO_ROOT / folder
        if not base.exists():
            continue
        for p in base.rglob("*"):
            if p.is_dir():
                continue
            rel = p.relative_to(REPO_ROOT)
            if any(part in EXCLUDE_DIRS for part in rel.parts):
                continue
            if p.name in EXCLUDE_FILES or p.suffix.lower() in EXCLUDE_SUFFIX:
                continue
            if "README_FA" in p.name and p.parent.name != "dashboard":
                continue
            yield p, str(rel)


def build_zip(force=False):
    """ساخت ZIP پکیج؛ اگر موجود باشد و force=False دوباره ساخته نمی‌شود."""
    if ZIP_PATH.exists() and not force:
        return ZIP_PATH
    TOOLKIT_DIR.mkdir(exist_ok=True)
    tmp = ZIP_PATH.with_suffix(".tmp")
    count = 0
    with zipfile.ZipFile(tmp, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as zf:
        for path, arcname in _iter_files():
            zf.write(path, arcname)
            count += 1
        # فایل شناسنامهٔ بیلد — برای تشخیص نسخهٔ ZIP بعد از دانلود
        build_utc = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")
        info = (
            "PythonTraderBot Control Center - BUILD INFO\n"
            "============================================\n"
            f"Build time (UTC): {build_utc}\n"
            f"Total files: {count + 1} (including this file)\n"
            "\n"
            "Portable-Python kit files included at zip root:\n"
            "  - install_python_portable.ps1  (downloads portable Python 3.14.3 + pip + requirements)\n"
            "  - install.bat                  (runs the script above)\n"
            "  - run_portable.bat             (launcher using .\\python\\python.exe)\n"
            "  - run.bat                      (launcher using system Python)\n"
            "  - requirements.txt\n"
            "\n"
            "How to verify your copy: open this file inside the zip.\n"
            "If BUILD_INFO.txt is missing, or the build time below is old,\n"
            "you have a stale cached download - re-download the zip.\n"
        )
        zf.writestr("BUILD_INFO.txt", info)
        count += 1
    tmp.rename(ZIP_PATH)
    ZIP_PATH.touch()  # بروزرسانی زمان
    return ZIP_PATH


def zip_build_time():
    """زمان بیلد داخل BUILD_INFO.txt — برای نمایش در UI و تشخیص نسخهٔ کش‌شده."""
    try:
        with zipfile.ZipFile(ZIP_PATH) as zf:
            if "BUILD_INFO.txt" not in zf.namelist():
                return None
            for line in zf.read("BUILD_INFO.txt").decode("utf-8").splitlines():
                if line.startswith("Build time (UTC):"):
                    return line.split(":", 1)[1].strip()
    except Exception:
        pass
    return None


def zip_info():
    if not ZIP_PATH.exists():
        return {"exists": False, "size_mb": 0, "files": 0}
    with zipfile.ZipFile(ZIP_PATH) as zf:
        n = len(zf.namelist())
    return {"exists": True, "size_mb": ZIP_PATH.stat().st_size / 1024 / 1024, "files": n}


if __name__ == "__main__":
    p = build_zip(force=True)
    print(f"built: {p}  info: {zip_info()}")
