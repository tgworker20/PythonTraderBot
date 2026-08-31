# -*- coding: utf-8 -*-
"""ساخت فایل ZIP کامل پکیج (کد ربات‌ها + اینترفیس + requirements + راهنما)"""
import zipfile
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
TOOLKIT_DIR = Path(__file__).resolve().parent / "toolkit"
ZIP_PATH = TOOLKIT_DIR / "PythonTraderBot_ControlCenter.zip"

EXCLUDE_DIRS = {"myenv", "__pycache__", ".git", ".ipynb_checkpoints", "logs",
                "toolkit", ".streamlit", ".cache", "build", "dist"}
EXCLUDE_FILES = {".gitignore", ".DS_Store"}
EXCLUDE_SUFFIX = {".pyc", ".pyo", ".exe", ".zip", ".log", ".pptx"}
INCLUDE_ROOT_FILES = {"requirements.txt", "README.md", "LICENSE", "START_HERE_FA.md"}


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
    tmp.rename(ZIP_PATH)
    ZIP_PATH.touch()  # بروزرسانی زمان
    return ZIP_PATH


def zip_info():
    if not ZIP_PATH.exists():
        return {"exists": False, "size_mb": 0, "files": 0}
    with zipfile.ZipFile(ZIP_PATH) as zf:
        n = len(zf.namelist())
    return {"exists": True, "size_mb": ZIP_PATH.stat().st_size / 1024 / 1024, "files": n}


if __name__ == "__main__":
    p = build_zip(force=True)
    print(f"built: {p}  info: {zip_info()}")
