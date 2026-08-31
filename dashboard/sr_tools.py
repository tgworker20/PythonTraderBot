# -*- coding: utf-8 -*-
"""ابزار تشخیص سطوح حمایت و مقاومت — پورت‌شده از SupportResistance/Helper.py"""
import numpy as np
import pandas as pd


def is_support(data, cc, before, after):
    """cc کندل جاری است؛ اگر کف محلی باشد ۱ برمی‌گرداند"""
    for i in range(cc - before + 1, cc + 1):
        if data["low"].iloc[i] > data["low"].iloc[i - 1]:
            return 0
    for i in range(cc + 1, cc + after + 1):
        if data["low"].iloc[i] < data["low"].iloc[i - 1]:
            return 0
    return 1


def is_resistance(data, cc, before, after):
    """cc کندل جاری است؛ اگر سقف محلی باشد ۱ برمی‌گرداند"""
    for i in range(cc - before + 1, cc + 1):
        if data["high"].iloc[i] < data["high"].iloc[i - 1]:
            return 0
    for i in range(cc + 1, cc + after + 1):
        if data["high"].iloc[i] > data["high"].iloc[i - 1]:
            return 0
    return 1


def find_support_resistance(df, before=3, after=2, round_digits=-3):
    """پورت SupportResistance.py: خروجی دو لیست سطح + زمان تشخیص"""
    df = df.loc[:, ["open", "high", "low", "close"]].dropna()
    support, resistance = [], []
    for row in range(before, len(df) - after):
        if is_support(df, row, before, after):
            support.append((round(float(df["low"].iloc[row]), round_digits),
                            df.index[row]))
        if is_resistance(df, row, before, after):
            resistance.append((round(float(df["high"].iloc[row]), round_digits),
                               df.index[row]))
    return support, resistance


def levels_to_csv_rows(levels):
    return [lvl for lvl, _ in levels]


def cluster_levels(levels, tolerance_pct=0.15, min_touches=1):
    """خوشه‌بندی سطوح نزدیک و شمارش تعداد برخورد (touch) — برای رتبه‌بندی قوی‌ترین سطوح
    levels می‌تواند لیست اعداد یا لیست تاپل (عدد، زمان) باشد."""
    if not levels:
        return pd.DataFrame(columns=["level", "touches"])
    if isinstance(levels[0], (tuple, list)):
        values = [v for v, _ in levels]
    else:
        values = list(levels)
    values = np.array(sorted(values), dtype=float)
    clusters = []
    current = [values[0]]
    for v in values[1:]:
        if abs(v - np.mean(current)) / max(abs(v), 1e-9) * 100 <= tolerance_pct:
            current.append(v)
        else:
            clusters.append(current)
            current = [v]
    clusters.append(current)
    rows = [{"level": float(np.mean(c)), "touches": len(c)} for c in clusters]
    df = pd.DataFrame(rows).sort_values("touches", ascending=False).reset_index(drop=True)
    if min_touches > 1:
        df = df[df["touches"] >= min_touches].reset_index(drop=True)
    return df


def normalize_candles(df):
    """سازگارسازی ستون‌های کندل (با CSVهای متاتریدر/یاهو)"""
    df = df.copy()
    df.columns = [str(c).strip().lower().replace("<", "").replace(">", "") for c in df.columns]
    rename = {"open": "open", "high": "high", "low": "low", "close": "close",
              "volume": "tick_volume", "tick_volume": "tick_volume", "vol": "tick_volume"}
    df = df.rename(columns=rename)
    for col in ["open", "high", "low", "close"]:
        if col not in df.columns:
            raise ValueError(f"ستون {col} در فایل کندل پیدا نشد.")
        df[col] = pd.to_numeric(df[col], errors="coerce")
    if "tick_volume" not in df.columns:
        df["tick_volume"] = 0
    # ستون زمان
    time_col = None
    for cand in ["time", "date", "local time", "datetime", "index"]:
        if cand in df.columns:
            time_col = cand
            break
    if time_col:
        df["time"] = pd.to_datetime(df[time_col], errors="coerce")
        df = df.drop(columns=[time_col]).set_index("time")
    else:
        try:
            df.index = pd.to_datetime(df.index, errors="coerce")
        except Exception:
            pass
    df = df.dropna(subset=["open", "high", "low", "close"])
    return df[["open", "high", "low", "close", "tick_volume"]]
