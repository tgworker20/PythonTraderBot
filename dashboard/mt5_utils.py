# -*- coding: utf-8 -*-
"""ابزارهای اتصال به متاتریدر ۵ (با محافظ در برابر نبود پکیج در لینوکس)"""
import os
from datetime import datetime, timezone, timedelta

# ---------------------------------------------------------------------------
MT5_AVAILABLE = False
MT5_IMPORT_ERROR = ""
try:
    import MetaTrader5 as mt5  # فقط روی ویندوز نصب می‌شود
    MT5_AVAILABLE = True
except Exception as e:  # noqa
    MT5_IMPORT_ERROR = str(e)


TIMEFRAMES = {}
SYMBOLS = {}
if MT5_AVAILABLE:
    TIMEFRAMES = {
        "M1 (یک دقیقه)": mt5.TIMEFRAME_M1,
        "M5 (پنج دقیقه)": mt5.TIMEFRAME_M5,
        "M15 (۱۵ دقیقه)": mt5.TIMEFRAME_M15,
        "M30 (۳۰ دقیقه)": mt5.TIMEFRAME_M30,
        "H1 (یک ساعت)": mt5.TIMEFRAME_H1,
        "H4 (چهار ساعت)": mt5.TIMEFRAME_H4,
        "D1 (روزانه)": mt5.TIMEFRAME_D1,
        "W1 (هفتگی)": mt5.TIMEFRAME_W1,
        "MN1 (ماهانه)": mt5.TIMEFRAME_MN1,
    }


def mt5_status():
    """وضعیت اتصال: پیام فارسی + اطلاعات حساب در صورت اتصال"""
    info = {"available": MT5_AVAILABLE, "import_error": MT5_IMPORT_ERROR,
            "initialized": False, "account": None}
    if not MT5_AVAILABLE:
        return info
    try:
        if not mt5.initialize():
            info["initialize_error"] = str(mt5.last_error())
            return info
        info["initialized"] = True
        acc = mt5.account_info()
        if acc is not None:
            info["account"] = {
                "login": acc.login,
                "server": acc.server,
                "leverage": acc.leverage,
                "balance": acc.balance,
                "equity": acc.equity,
                "profit": acc.profit,
                "currency": acc.currency,
            }
        positions = mt5.positions_get() or []
        info["open_positions"] = len(positions)
    except Exception as e:
        info["error"] = str(e)
    return info


def fetch_rates(symbol, timeframe, count, from_date=None):
    """دریافت کندل‌ها — خروجی: DataFrame با ستون‌های time/open/high/low/close/tick_volume"""
    if not MT5_AVAILABLE:
        raise RuntimeError("پکیج MetaTrader5 در دسترس نیست (فقط ویندوز).")
    import pandas as pd
    if from_date is None:
        # متاتریدر تایم سرور (روسیه) دارد؛ +۳ ساعت جابجایی مطابق Meta.py نویسنده
        from_date = datetime.now(timezone.utc) + timedelta(hours=3)
    rates = mt5.copy_rates_from(symbol, timeframe, from_date, int(count))
    if rates is None or len(rates) == 0:
        raise RuntimeError(f"داده‌ای برای {symbol} دریافت نشد. نماد را در Market Watch چک کنید.")
    df = pd.DataFrame(rates)
    df["time"] = pd.to_datetime(df["time"], unit="s")
    df = df.set_index("time")
    return df[["open", "high", "low", "close", "tick_volume", "spread", "real_volume"]]


def get_positions_df():
    """پوزیشن‌های باز حساب"""
    if not MT5_AVAILABLE:
        return None
    import pandas as pd
    positions = mt5.positions_get() or []
    if not positions:
        return pd.DataFrame()
    rows = [{
        "ticket": p.ticket, "symbol": p.symbol, "type": "خرید" if p.type == 0 else "فروش",
        "volume": p.volume, "price_open": p.price_open, "price_current": p.price_current,
        "sl": p.sl, "tp": p.tp, "profit": p.profit, "magic": p.magic,
    } for p in positions]
    return pd.DataFrame(rows)


def symbol_lookup(symbol):
    """بررسی وجود نماد در بروکر + پیشنهاد نام‌های مشابه.
    نام نماد در هر بروکر متفاوت است (طلا: XAUUSD / XAUUSDzero / GOLD.micro ...)."""
    res = {"available": MT5_AVAILABLE, "initialized": False, "found": False,
           "info": None, "matches": [], "error": ""}
    if not MT5_AVAILABLE:
        return res
    try:
        if not mt5.initialize():
            res["error"] = str(mt5.last_error())
            return res
        res["initialized"] = True
        si = mt5.symbol_info(symbol)
        if si is not None:
            try:
                mt5.symbol_select(symbol, True)  # اضافه به Market Watch برای دریافت داده
            except Exception:
                pass
            res["found"] = True
            res["info"] = {
                "name": si.name,
                "description": getattr(si, "description", ""),
                "digits": si.digits,
                "point": si.point,
                "volume_min": si.volume_min,
                "trade_mode": si.trade_mode,
            }
            return res
        # پیدا نشد → جستجوی نام‌های مشابه
        q = str(symbol).upper().strip()
        names = []
        try:
            names = sorted(s.name for s in (mt5.symbols_get() or []))
        except Exception:
            names = []
        seen = []
        for pat in [q] + ([q[:3]] if len(q) >= 4 else []):
            for n in names:
                if pat in n.upper() and n not in seen:
                    seen.append(n)
        res["matches"] = seen[:40]
    except Exception as e:
        res["error"] = str(e)
    return res
