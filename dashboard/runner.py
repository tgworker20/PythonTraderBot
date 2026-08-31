# -*- coding: utf-8 -*-
"""مدیریت اجرای ربات‌های لایو به‌صورت subprocess + لاگ زنده"""
import subprocess
import sys
import time
from pathlib import Path

from catalog import bot_script_path, get_bot, CODE_DIR

LOGS_DIR = Path(__file__).resolve().parent / "logs"
LOGS_DIR.mkdir(exist_ok=True)

# اسکریپت‌های ویژه (بک‌تست‌های MT5 که ربات دائمی نیستند)
SPECIAL_SCRIPTS = {
    "__mh_bt": {"name": "بک‌تست مایکل هریس", "script": "run_michael_harris_backtest.py", "folder": ""},
    "__sp_bt": {"name": "بک‌تست SP2L پیشرفته", "script": "run_sp2l_backtest.py", "folder": "SP2L"},
}

# دیکشنری ماژول-سطح تا در طول عمر سرور زنده بماند (بین rerunهای Streamlit)
_PROCS = {}


def is_running(bot_id):
    p = _PROCS.get(bot_id)
    if p is None:
        return False
    return p.poll() is None


def start_bot(bot_id):
    special = SPECIAL_SCRIPTS.get(bot_id)
    if special is not None:
        script = CODE_DIR / special["folder"] / special["script"]
        name = special["name"]
    else:
        bot = get_bot(bot_id)
        if bot is None:
            return False, "ربات یافت نشد."
        name = bot["name"]
        script = bot_script_path(bot)
    if is_running(bot_id):
        return True, "از قبل در حال اجراست."
    if not script.exists():
        return False, f"فایل یافت نشد: {script}"
    cwd = script.parent
    log_path = LOGS_DIR / f"{bot_id}.log"
    log_file = open(log_path, "ab")
    log_file.write(f"\n{'=' * 60}\n[{time.strftime('%Y-%m-%d %H:%M:%S')}] START {script.name}\n{'=' * 60}\n".encode("utf-8"))
    try:
        proc = subprocess.Popen(
            [sys.executable, "-u", script.name],
            cwd=str(cwd),
            stdout=log_file,
            stderr=subprocess.STDOUT,
            stdin=subprocess.DEVNULL,
        )
    except Exception as e:
        log_file.close()
        return False, f"خطا در اجرا: {e}"
    _PROCS[bot_id] = proc
    return True, f"{name} اجرا شد (PID {proc.pid})."


def stop_bot(bot_id):
    p = _PROCS.get(bot_id)
    if p is None or p.poll() is not None:
        _PROCS.pop(bot_id, None)
        return False, "این ربات در حال اجرا نیست."
    p.terminate()
    try:
        p.wait(timeout=5)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait(timeout=5)
    _PROCS.pop(bot_id, None)
    log_append(bot_id, f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] STOPPED by user\n")
    return True, "ربات متوقف شد."


def stop_all():
    stopped = []
    for bot_id in list(_PROCS.keys()):
        ok, _ = stop_bot(bot_id)
        if ok:
            stopped.append(bot_id)
    return stopped


def running_bots():
    return [bid for bid in _PROCS if is_running(bid)]


def log_path(bot_id):
    return LOGS_DIR / f"{bot_id}.log"


def log_append(bot_id, text):
    try:
        with open(log_path(bot_id), "ab") as f:
            f.write(text.encode("utf-8"))
    except OSError:
        pass


def read_log(bot_id, tail=80):
    """آخرین خطوط لاگ ربات"""
    path = log_path(bot_id)
    if not path.exists():
        return "— هنوز لاگی وجود ندارد —"
    try:
        with open(path, "rb") as f:
            lines = f.read().decode("utf-8", errors="replace").splitlines()
        return "\n".join(lines[-tail:])
    except OSError as e:
        return f"خطا در خواندن لاگ: {e}"


def process_info(bot_id):
    p = _PROCS.get(bot_id)
    if p is None:
        return {"state": "stopped", "pid": None, "returncode": None}
    rc = p.poll()
    return {
        "state": "running" if rc is None else "exited",
        "pid": p.pid,
        "returncode": rc,
    }
