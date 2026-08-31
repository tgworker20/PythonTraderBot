# -*- coding: utf-8 -*-
"""ویرایشگر فایل‌ها و پیکربندی ربات‌ها: تغییر نماد/حجم بدون خروج از اینترفیس"""
import re
import shutil
import time
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
CODE_DIR = REPO_ROOT / "code"
BACKUPS_DIR = Path(__file__).resolve().parent / "backups"
BACKUPS_DIR.mkdir(exist_ok=True)

TEXT_EXTS = {".py", ".txt", ".md", ".csv", ".json", ".toml", ".cfg", ".gitignore", ""}


# ---------------------------------------------------------------------------
# فایل‌ها
# ---------------------------------------------------------------------------
def list_repo_files():
    """همهٔ فایل‌های قابل مدیریت ریپو (به‌جز محیط مجازی/کش)"""
    files = []
    skip_dirs = {"myenv", "__pycache__", ".git", ".ipynb_checkpoints", "logs",
                 "toolkit", "backups", ".streamlit"}
    for base in [CODE_DIR, Path(__file__).resolve().parent]:
        if not base.exists():
            continue
        for p in sorted(base.rglob("*")):
            if p.is_dir():
                continue
            if any(part in skip_dirs for part in p.parts):
                continue
            files.append({
                "path": p,
                "rel": str(p.relative_to(REPO_ROOT)),
                "size_kb": p.stat().st_size / 1024,
                "suffix": p.suffix.lower(),
            })
    for p in sorted(REPO_ROOT.glob("*")):
        if p.is_file() and p.suffix.lower() in TEXT_EXTS:
            files.append({"path": p, "rel": p.name, "size_kb": p.stat().st_size / 1024,
                          "suffix": p.suffix.lower()})
    return files


def read_text(path):
    return Path(path).read_text(encoding="utf-8", errors="replace")


def write_text(path, content, backup=True):
    p = Path(path)
    if backup and p.exists():
        backup_file(p)
    p.write_text(content, encoding="utf-8")
    return True


def backup_file(path):
    p = Path(path)
    if not p.exists():
        return None
    stamp = time.strftime("%Y%m%d_%H%M%S")
    dest = BACKUPS_DIR / f"{stamp}_{p.name}"
    i = 0
    while dest.exists():
        i += 1
        dest = BACKUPS_DIR / f"{stamp}_{i}_{p.name}"
    shutil.copy2(p, dest)
    return dest


def list_backups():
    return sorted(BACKUPS_DIR.glob("*"), reverse=True)


# ---------------------------------------------------------------------------
# ویرایش نماد/حجم ربات‌ها
# ---------------------------------------------------------------------------
SYMBOL_BOTS = [
    # (id, مسیر فایل نسبت به code/, نوع کانفیگ)
    {"id": "easybot", "name": "EasyBot", "file": "EasyBot.py", "kind": "symbols_list"},
    {"id": "traderbot", "name": "TraderBot (۴ استراتژی)", "file": "TraderBot.py", "kind": "symbols_list"},
    {"id": "bb_full", "name": "BB_Full", "file": "BB_Full.py", "kind": "symbols_list"},
    {"id": "bb_half", "name": "BB_Half", "file": "BB_Half.py", "kind": "symbols_list"},
    {"id": "ce_zlsma_ha", "name": "CE_ZLSMA_HA", "file": "CE_ZLSMA_HA.py", "kind": "symbols_list"},
    {"id": "ce_zlsma_ha_atr", "name": "CE_ZLSMA_HA_ATR", "file": "CE_ZLSMA_HA_ATR.py", "kind": "symbols_list"},
    {"id": "ha_rsi_scalper", "name": "HA_RSI_CE_EMA_Scalper", "file": "HA_RSI_CE_EMA_Scalper.py", "kind": "symbols_list"},
    {"id": "vwap_bb_rsi", "name": "VWAP_BB_RSI", "file": "VWAP_BB_RSI.py", "kind": "symbols_list"},
    {"id": "sp2l_bot", "name": "SP2L_Bot", "file": "SP2L/SP2L_Bot.py", "kind": "symbols_list"},
    {"id": "sp2l_advanced", "name": "SP2L_Advanced_Bot", "file": "SP2L/SP2L_Advanced_Bot.py", "kind": "const+symbols_list"},
    {"id": "easybot_sr", "name": "EasyBot + حمایت/مقاومت", "file": "SupportResistance/EasyBotWithSupportResistance.py", "kind": "symbol_var"},
]


def _find_block_bounds(lines, start_idx):
    """از خطی که با symbols_list = { شروع می‌شود، پایان بلوک را با شمارش آکولاد می‌یابد
    (خطوط کامنت نادیده گرفته می‌شوند)"""
    depth = 0
    opened = False
    for i in range(start_idx, len(lines)):
        code = lines[i]
        # حذف بخش کامنت (تقریبی — برای این فایل‌ها کافی است)
        if "#" in code:
            # داخل رشته می‌تواند # باشد؛ فقط اگر بعد از " یا ' نبود
            code = re.sub(r'(?<![\'"]#[^\'"]*[\'"])#.*$', '', code) if '"' in code or "'" in code else code.split("#")[0]
        else:
            code = code
        depth += code.count("{") - code.count("}")
        if "{" in code:
            opened = True
        if opened and depth <= 0:
            return start_idx, i
    return None


def parse_symbols_list(src):
    """پیدا کردن بلوک واقعی symbols_list = {...} (کامنت‌ها نادیده گرفته می‌شوند)"""
    lines = src.split("\n")
    start_idx = None
    for i, line in enumerate(lines):
        stripped = line.strip()
        if stripped.startswith("#"):
            continue
        if re.match(r"^symbols_list\s*=\s*\{", stripped):
            start_idx = i
            break
    if start_idx is None:
        return None
    bounds = _find_block_bounds(lines, start_idx)
    if bounds is None:
        return None
    s, e = bounds
    block = "\n".join(lines[s:e + 1])
    entries = []
    for ln in lines[s:e + 1]:
        ls = ln.strip()
        if ls.startswith("#") or ":" not in ls:
            continue
        em = re.match(r'["\']([^"\']*)["\']\s*:\s*\[([^\]]*)\]', ls)
        if not em:
            continue
        key = em.group(1)
        parts = [p.strip() for p in em.group(2).split(",")]
        symbol = parts[0].strip("\"'") if parts else ""
        try:
            lot = float(parts[1]) if len(parts) > 1 else 0.01
        except ValueError:
            lot = 0.01
        entries.append({"key": key, "symbol": symbol, "lot": lot})
    return {"block": block, "start_line": s, "end_line": e, "entries": entries}


def apply_symbols_list(src, entries, indent="    "):
    """بازنویسی بلوک symbols_list با ورودی‌های جدید"""
    parsed = parse_symbols_list(src)
    if parsed is None:
        return src, False
    lines = src.split("\n")
    new_lines = ["symbols_list = {"]
    for e in entries:
        new_lines.append(f'{indent}"{e["key"]}": ["{e["symbol"]}", {e["lot"]}],')
    new_lines.append("   }")
    out = lines[:parsed["start_line"]] + new_lines + lines[parsed["end_line"] + 1:]
    return "\n".join(out), True


def parse_const(src, varname):
    """پیدا کردن مقدار یک متغیر ساده مثل SYMBOL = "XAUUSD" یا symbol = 'BTC'"""
    m = re.search(rf'^{varname}\s*=\s*["\']([^"\']*)["\']', src, re.MULTILINE)
    if not m:
        return None
    return {"value": m.group(1), "start": m.start(), "end": m.end(), "line": m.group(0)}


def apply_const(src, varname, new_value):
    m = re.search(rf'^({varname}\s*=\s*)(["\'])([^"\']*)(["\'])', src, re.MULTILINE)
    if not m:
        return src, False
    return src[:m.start()] + m.group(1) + m.group(2) + new_value + m.group(4) + src[m.end():], True


def apply_symbol_var(src, new_value):
    """تغییر symbol = 'X' (استایل EasyBot)"""
    m = re.search(r"^(symbol\s*=\s*)(['\"])([^'\"]*)(['\"])", src, re.MULTILINE)
    if not m:
        return src, False
    return src[:m.start()] + m.group(1) + m.group(2) + new_value + m.group(4) + src[m.end():], True


def edit_bot_config(file_rel, edits):
    """اعمال ویرایش نماد/حجم روی فایل ربات — edits: dict طبق kind"""
    path = CODE_DIR / file_rel
    if not path.exists():
        return False, f"فایل یافت نشد: {path}"
    src = read_text(path)
    backup_file(path)
    kind = edits.get("kind", "symbols_list")

    if kind in ("symbols_list", "const+symbols_list"):
        entries = edits.get("entries")
        if entries:
            src, ok = apply_symbols_list(src, entries)
            if not ok:
                return False, "بلوک symbols_list در فایل پیدا نشد."
    if kind in ("const+symbols_list",):
        if edits.get("const_var") and edits.get("const_value"):
            src, ok = apply_const(src, edits["const_var"], edits["const_value"])
    if kind == "symbol_var":
        if edits.get("symbol"):
            src, ok = apply_symbol_var(src, edits["symbol"])
            if not ok:
                return False, "متغیر symbol در فایل پیدا نشد."
    write_text(path, src, backup=False)  # بکاپ قبلاً گرفته شد
    return True, f"✅ تغییرات در {file_rel} ذخیره شد (بکاپ گرفته شد)."


# ---------------------------------------------------------------------------
# تعمیر/سازگاری با آپدیت‌های نویسنده
# ---------------------------------------------------------------------------
def repair_report():
    """بررسی سلامت فایل‌های لازم وقتی پوشهٔ dashboard داخل ریپوی جدید نویسنده قرار می‌گیرد"""
    issues = []
    if not (CODE_DIR / "Meta.py").exists():
        if (CODE_DIR / "SP2L" / "Meta.py").exists():
            issues.append({"id": "copy_meta", "fixable": True,
                           "text": "فایل code/Meta.py موجود نیست (ریپوی نویسنده آن را جدا نگه می‌دارد) — می‌توان از code/SP2L/Meta.py کپی کرد."})
        else:
            issues.append({"id": "no_meta", "fixable": False,
                           "text": "Meta.py نه در code/ و نه در code/SP2L/ پیدا شد — ریپوی Meta نویسنده (PythonTraderBotMeta) لازم است."})
    if not (CODE_DIR / "TelegramBot.py").exists():
        if (CODE_DIR / "SP2L" / "TelegramBot.py").exists():
            issues.append({"id": "copy_telebot", "fixable": True,
                           "text": "فایل code/TelegramBot.py موجود نیست — از code/SP2L/TelegramBot.py قابل کپی است."})
    if not (CODE_DIR / "SupportResistance" / "Meta.py").exists():
        if (CODE_DIR / "SP2L" / "Meta.py").exists():
            issues.append({"id": "copy_meta_sr", "fixable": True,
                           "text": "فایل code/SupportResistance/Meta.py موجود نیست — قابل کپی از code/SP2L/."})
    # اسکریپت‌های تبدیل‌شدهٔ بک‌تست
    if (CODE_DIR / "MichaelHarrisSplit.ipynb").exists() and not (CODE_DIR / "run_michael_harris_backtest.py").exists():
        issues.append({"id": "gen_mh", "fixable": True,
                       "text": "اسکریپت اجرای مستقل بک‌تست مایکل هریس ساخته نشده — قابل تولید از خود نوت‌بوک نویسنده."})
    if (CODE_DIR / "SP2L" / "SP2L2_Advanced_Backtest.ipynb").exists() and not (CODE_DIR / "SP2L" / "run_sp2l_backtest.py").exists():
        issues.append({"id": "gen_sp2l", "fixable": True,
                       "text": "اسکریپت اجرای مستقل بک‌تست SP2L ساخته نشده — قابل تولید از خود نوت‌بوک نویسنده."})
    return issues


def run_repair(issue_id):
    """اجرای یک تعمیر"""
    import shutil as sh
    try:
        if issue_id == "copy_meta":
            sh.copy2(CODE_DIR / "SP2L" / "Meta.py", CODE_DIR / "Meta.py")
            # دو اصلاح کوچک نسخهٔ ریشه
            src = read_text(CODE_DIR / "Meta.py")
            src = src.replace("TeleBot.SendMessage(exceptMessage)", "TeleBot().SendMessage(exceptMessage)")
            src = src.replace("def TrailingStopLoss(magicList):", "def TrailingStopLoss(magicList=None):")
            write_text(CODE_DIR / "Meta.py", src, backup=False)
            return True, "Meta.py کپی و اصلاح شد."
        if issue_id == "copy_telebot":
            sh.copy2(CODE_DIR / "SP2L" / "TelegramBot.py", CODE_DIR / "TelegramBot.py")
            return True, "TelegramBot.py کپی شد."
        if issue_id == "copy_meta_sr":
            for f in ["Meta.py", "TelegramBot.py"]:
                src_p = CODE_DIR / "SP2L" / f
                if src_p.exists():
                    sh.copy2(src_p, CODE_DIR / "SupportResistance" / f)
            return True, "فایل‌های SupportResistance کپی شد."
        if issue_id == "gen_mh":
            from convert_notebooks import generate_michael_harris
            return generate_michael_harris()
        if issue_id == "gen_sp2l":
            from convert_notebooks import generate_sp2l
            return generate_sp2l()
    except Exception as e:
        return False, f"خطا در تعمیر: {e}"
    return False, "تعمیر ناشناخته."
