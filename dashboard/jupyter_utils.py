# -*- coding: utf-8 -*-
"""ابزارهای Jupyter: اجرای سرور، ویرایش سلول‌ها، اجرای نوت‌بوک اصلی نویسنده"""
import json
import re
import subprocess
import sys
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CODE_DIR = REPO_ROOT / "code"
LOGS_DIR = Path(__file__).resolve().parent / "logs"
LOGS_DIR.mkdir(exist_ok=True)

JUPYTER_PROC = None
JUPYTER_LOG_PATH = LOGS_DIR / "jupyter_server.log"


# ---------------------------------------------------------------------------
# بررسی نصب بودن
# ---------------------------------------------------------------------------
def jupyter_available():
    """آیا پکیج notebook در همین پایتون نصب است؟"""
    try:
        import notebook  # noqa
        return True
    except Exception:
        return False


def jupyterlab_available():
    try:
        import jupyterlab  # noqa
        return True
    except Exception:
        return False


def jupyter_install_hint():
    return "pip install notebook"


# ---------------------------------------------------------------------------
# اجرای سرور Jupyter
# ---------------------------------------------------------------------------
def jupyter_server_running():
    global JUPYTER_PROC
    return JUPYTER_PROC is not None and JUPYTER_PROC.poll() is None


def start_jupyter(port=8888, bind_all=False, lab=False):
    """اجراه سرور Jupyter Notebook/JupyterLab؛ خروجی: (ok, message)"""
    global JUPYTER_PROC
    if jupyter_server_running():
        return True, "سرور Jupyter از قبل در حال اجراست."
    if not (jupyter_available() or jupyterlab_available()):
        return False, (
            "پکیج Jupyter نصب نیست. در ترمینال اجرا کنید: "
            f"`{jupyter_install_hint()}` سپس صفحه را بروزرسانی کنید."
        )
    mod = "jupyterlab" if (lab and jupyterlab_available()) else "notebook"
    bind = "0.0.0.0" if bind_all else "127.0.0.1"
    cmd = [
        sys.executable, "-m", mod,
        "--no-browser",
        f"--port={int(port)}",
        f"--ip={bind}",
        # برای کارکرد درست پشت پروکسی/پیش‌نمایش
        "--ServerApp.allow_origin='*'",
        "--ServerApp.disable_check_xsrf=True",
        "--ServerApp.allow_remote_access=True",
        "--NotebookApp.iopub_data_rate_limit=1e12",
    ]
    log_file = open(JUPYTER_LOG_PATH, "ab")
    log_file.write(f"\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] START {mod} port={port}\n".encode("utf-8"))
    try:
        proc = subprocess.Popen(cmd, cwd=str(REPO_ROOT),
                                stdout=log_file, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL)
    except Exception as e:
        log_file.close()
        return False, f"خطا در اجرای Jupyter: {e}"
    JUPYTER_PROC = proc
    # کمی صبر تا URL توکن در لاگ ثبت شود
    for _ in range(20):
        time.sleep(0.5)
        if jupyter_token_url():
            break
        if proc.poll() is not None:
            break
    return True, f"سرور Jupyter روی پورت {port} اجرا شد."


def stop_jupyter():
    global JUPYTER_PROC
    if not jupyter_server_running():
        JUPYTER_PROC = None
        return False, "سرور Jupyter در حال اجرا نیست."
    JUPYTER_PROC.terminate()
    try:
        JUPYTER_PROC.wait(timeout=8)
    except subprocess.TimeoutExpired:
        JUPYTER_PROC.kill()
        JUPYTER_PROC.wait(timeout=8)
    JUPYTER_PROC = None
    return True, "سرور Jupyter متوقف شد."


def jupyter_log_tail(tail=40):
    if not JUPYTER_LOG_PATH.exists():
        return "— لاگی موجود نیست —"
    try:
        lines = JUPYTER_LOG_PATH.read_bytes().decode("utf-8", errors="replace").splitlines()
        return "\n".join(lines[-tail:])
    except OSError:
        return "— خطا در خواندن لاگ —"


def jupyter_token_url():
    """استخراج آخرین URL با توکن از لاگ سرور"""
    if not JUPYTER_LOG_PATH.exists():
        return None
    try:
        text = JUPYTER_LOG_PATH.read_bytes().decode("utf-8", errors="replace")
    except OSError:
        return None
    urls = re.findall(r"(https?://[^\s]*?token=[A-Za-z0-9\-]+)", text)
    return urls[-1] if urls else None


def jupyter_urls():
    """تمام URLهای سرور از لاگ"""
    if not JUPYTER_LOG_PATH.exists():
        return []
    try:
        text = JUPYTER_LOG_PATH.read_bytes().decode("utf-8", errors="replace")
    except OSError:
        return []
    urls = re.findall(r"(https?://(?:127\.0\.0\.1|localhost):\d+/[^\s]*)", text)
    out, seen = [], set()
    for u in urls:
        if u not in seen:
            seen.add(u)
            out.append(u)
    return out


# ---------------------------------------------------------------------------
# لیست نوت‌بوک‌های ریپو (پویا — نوت‌بوک‌های آپدیت‌های بعدی نویسنده هم پیدا می‌شوند)
# ---------------------------------------------------------------------------
NOTEBOOK_META = {
    "Markov.ipynb": "بک‌تست زنجیرهٔ مارکوف روی ۲۰ سهم آمریکا (yfinance)",
    "LeverageLongRun_SPY_UPRO.ipynb": "بک‌تست استراتژی لوریج SPY→UPRO (yfinance) — وین‌ریت اعلامی ۸۵٪",
    "HA_RSI_CE_EMA_Scalper_Backtesting.ipynb": "بک‌تست ربات اسکالپر — به فایل Candles.csv کنار خودش نیاز دارد",
    "MichaelHarrisSplit.ipynb": "بک‌تست مایکل هریس (MT5، CARDANO/H4) — سود گزارش‌شده ۳۷۰٪",
    "SP2L2_Advanced_Backtest.ipynb": "بک‌تست SP2L پیشرفته (MT5، XAUUSD/M1) — وین‌ریت اعلامی ۸۴٪",
    "SP2L.ipynb": "آموزش استراتژی SP2L",
    "KNN&XGBOOST.ipynb": "پیش‌بینی جهت با KNN و XGBoost",
    "WhichIndicator.ipynb": "انتخاب بهترین اندیکاتور با XGBoost",
    "TargetDefinition.ipynb": "مدل‌سازی هدف با یادگیری ماشین",
    "AI-Traderbot.ipynb": "ربات لایو مبتنی بر مدل ML ذخیره‌شده (joblib)",
    "TradeAssistant-StrongSupportResistanceDetector1.ipynb": "تشخیص سقف/کف — بخش ۱",
    "TradeAssistant-StrongSupportResistanceDetector2.ipynb": "سطوح قوی حمایت/مقاومت — بخش ۲",
    "Slope_PandasTa_Backroll.ipynb": "شیب اندیکاتورها — به EURUSDH4.csv نیاز دارد",
    "GetSummaryAndIndicatorFromTradingview.ipynb": "دریافت داده از TradingView",
    "TraderBotWithTradingviewData.ipynb": "معامله با سیگنال TradingView روی MT5",
}


def list_notebooks():
    """همهٔ نوت‌بوک‌های موجود در code/ (و زیرپوشه‌ها)"""
    nbs = []
    if CODE_DIR.exists():
        for p in sorted(CODE_DIR.rglob("*.ipynb")):
            if any(part in {"myenv", "__pycache__", ".ipynb_checkpoints"} for part in p.parts):
                continue
            nbs.append({
                "path": p,
                "rel": str(p.relative_to(REPO_ROOT)),
                "name": p.name,
                "desc": NOTEBOOK_META.get(p.name, "نوت‌بوک"),
                "needs_mt5": _needs_mt5(p),
            })
    return nbs


def _needs_mt5(path):
    try:
        src = path.read_text(encoding="utf-8", errors="replace")
        return ("MetaTrader5" in src) or ("from Meta import" in src)
    except OSError:
        return False


# ---------------------------------------------------------------------------
# ویرایش سلول‌های نوت‌بوک (بدون تغییر بقیهٔ ساختار)
# ---------------------------------------------------------------------------
def load_notebook(path):
    return json.loads(Path(path).read_text(encoding="utf-8", errors="replace"))


def get_cells(path):
    nb = load_notebook(path)
    cells = []
    for i, c in enumerate(nb.get("cells", [])):
        cells.append({
            "index": i,
            "type": c.get("cell_type", "code"),
            "source": "".join(c.get("source", [])),
        })
    return cells


def save_cell_source(path, cell_index, new_source):
    """ذخیرهٔ سورس یک سلول (با بکاپ)"""
    p = Path(path)
    nb = load_notebook(p)
    _backup(p)
    if 0 <= cell_index < len(nb.get("cells", [])):
        # source به شکل لیست خطوط با newline
        lines = new_source.split("\n")
        nb["cells"][cell_index]["source"] = [l + "\n" for l in lines[:-1]] + [lines[-1]]
        p.write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
        return True
    return False


def notebook_outputs(path, max_len=2500):
    """استخراج خروجی‌های متنی هر سلول (بعد از اجرا)"""
    nb = load_notebook(path)
    outs = []
    for i, c in enumerate(nb.get("cells", [])):
        if c.get("cell_type") != "code":
            continue
        parts = []
        for o in c.get("outputs", []):
            if o.get("output_type") == "stream":
                parts.append("".join(o.get("text", [])))
            elif o.get("output_type") in ("execute_result", "display_data"):
                data = o.get("data", {})
                if "text/plain" in data:
                    parts.append("".join(data["text/plain"]))
                if "image/png" in data:
                    parts.append("[📷 نمودار تصویری — در Jupyter ببینید]")
            elif o.get("output_type") == "error":
                parts.append("❌ " + "\n".join(o.get("traceback", []))[:max_len])
        text = "\n".join(parts).strip()
        if text:
            src_head = "".join(c.get("source", []))[:80].replace("\n", " ⏎ ")
            outs.append({"cell": i, "src": src_head, "output": text[:max_len]})
    return outs


# ---------------------------------------------------------------------------
# اجرای نوت‌بوک اصلی نویسنده (دقیقا همان کد، بدون بازنویسی)
# ---------------------------------------------------------------------------
NB_RUN_PROC = None
NB_RUN_LOG = LOGS_DIR / "notebook_run.log"


def notebook_run_running():
    global NB_RUN_PROC
    return NB_RUN_PROC is not None and NB_RUN_PROC.poll() is None


def run_notebook_async(path):
    """اجرای نوت‌بوک با nbconvert --execute --inplace به‌صورت غیرهمزمان"""
    global NB_RUN_PROC
    if notebook_run_running():
        return False, "یک نوت‌بوک دیگر در حال اجراست."
    p = Path(path)
    if not p.exists():
        return False, f"فایل یافت نشد: {p}"
    _backup(p)
    cmd = [sys.executable, "-m", "nbconvert", "--to", "notebook",
           "--execute", "--inplace", str(p), "--ExecutePreprocessor.timeout=1800"]
    log_file = open(NB_RUN_LOG, "ab")
    log_file.write(f"\n{'=' * 60}\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] RUN {p.name}\n{'=' * 60}\n".encode("utf-8"))
    try:
        proc = subprocess.Popen(cmd, cwd=str(p.parent),
                                stdout=log_file, stderr=subprocess.STDOUT,
                                stdin=subprocess.DEVNULL)
    except Exception as e:
        log_file.close()
        return False, f"خطا در اجرا: {e}"
    NB_RUN_PROC = proc
    return True, f"اجرای «{p.name}» شروع شد — پس از پایان، خروجی‌ها همین‌جا نمایش داده می‌شوند."


def notebook_run_log_tail(tail=60):
    if not NB_RUN_LOG.exists():
        return "— هنوز اجرایی نبوده —"
    try:
        lines = NB_RUN_LOG.read_bytes().decode("utf-8", errors="replace").splitlines()
        return "\n".join(lines[-tail:])
    except OSError:
        return "— خطا در خواندن لاگ —"


def _backup(path):
    """بکاپ فایل قبل از تغییر در dashboard/backups"""
    import shutil
    p = Path(path)
    if not p.exists():
        return None
    bdir = Path(__file__).resolve().parent / "backups"
    bdir.mkdir(exist_ok=True)
    stamp = time.strftime("%Y%m%d_%H%M%S")
    dest = bdir / f"{stamp}_{p.name}"
    shutil.copy2(p, dest)
    return dest
