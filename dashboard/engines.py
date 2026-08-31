# -*- coding: utf-8 -*-
"""
موتورهای بک‌تست — پورت‌شده از نوت‌بوک‌های ریپازیتوری تا بدون Jupyter اجرا شوند:
  1) Markov            (Markov.ipynb) — yfinance
  2) LeverageLongRun   (LeverageLongRun_SPY_UPRO.ipynb) — yfinance
  3) HA_RSI_Scalper    (HA_RSI_CE_EMA_Scalper_Backtesting.ipynb) — CSV/MT5
  4) SMA Optimizer     (SMABestPerformance.py) — CSV/MT5
"""
import numpy as np
import pandas as pd
import yfinance as yf
import ta.momentum
from backtesting import Backtest, Strategy


# ===========================================================================
# دریافت داده از یاهو فایننس
# ===========================================================================
def download_ohlc(tickers, start, end, interval="1d"):
    """دانلود OHLC برای یک یا چند تیکر؛ خروجی: دیکشنری {ticker: DataFrame}"""
    if isinstance(tickers, str):
        tickers = [tickers]
    raw = yf.download(
        tickers, start=start, end=end,
        group_by="ticker", auto_adjust=False, progress=False,
    )
    if raw is None or raw.empty:
        raise RuntimeError(
            "داده‌ای از یاهو فایننس دریافت نشد. اتصال اینترنت یا نمادها را بررسی کنید."
        )
    out = {}
    if len(tickers) == 1 and not isinstance(raw.columns, pd.MultiIndex):
        df = raw.copy()
        out[tickers[0]] = _clean_yf_df(df)
    else:
        for t in tickers:
            if t not in raw.columns.get_level_values(0):
                continue
            df = raw[t].copy()
            out[t] = _clean_yf_df(df)
    if not out:
        raise RuntimeError("هیچ نماد معتبری دریافت نشد.")
    return out


def _clean_yf_df(df):
    cols = [c for c in ["Open", "High", "Low", "Close", "Volume"] if c in df.columns]
    df = df[cols].dropna()
    df.columns = [c.lower() for c in cols]
    return df


# ===========================================================================
# ۱) بک‌تست مارکوف (کندل‌های هم‌رنگ پشت سرهم)
# ===========================================================================
class _ConsecutiveBuySellStrategy(Strategy):
    n = 2

    def init(self):
        pass

    def next(self):
        if len(self.data) < self.n:
            return
        open_ = self.data.Open
        close_ = self.data.Close
        if all(close_[-i] < open_[-i] for i in range(1, self.n + 1)):
            self.buy()
        elif all(close_[-i] > open_[-i] for i in range(1, self.n + 1)):
            self.sell()
        if self.position:
            self.position.close()


class _ConsecutiveBuyStrategy(Strategy):
    n = 4

    def init(self):
        pass

    def next(self):
        if len(self.data) < self.n:
            return
        if all(self.data.Close[-i] < self.data.Open[-i] for i in range(1, self.n + 1)):
            self.buy()
        if self.position:
            self.position.close()


def markov_metrics(data_by_ticker, n):
    """معیار آماری نوت‌بوک: بعد از n کندل هم‌رنگ، بعدی چه رنگی است؟"""
    downSimilar = upSimilar = buy_green = sell_red = 0
    for ticker, df in data_by_ticker.items():
        candleColor = (df["close"] > df["open"]).values
        i = 0
        while i < len(candles := candleColor) - n:
            if all(candles[i + j] for j in range(n)):
                upSimilar += 1
                if i + n < len(candles) and not candles[i + n]:
                    sell_red += 1
                i += n
            elif all(not candles[i + j] for j in range(n)):
                downSimilar += 1
                if i + n < len(candles) and candles[i + n]:
                    buy_green += 1
                i += n
            else:
                i += 1
    upFraction = sell_red / upSimilar if upSimilar > 0 else 0
    downFraction = buy_green / downSimilar if downSimilar > 0 else 0
    return {
        f"{n} کندل قرمز پشت‌سرهم ← کندل سبز (سیگنال خرید)": downFraction,
        f"{n} کندل سبز پشت‌سرهم ← کندل قرمز (سیگنال فروش)": upFraction,
        "تعداد الگوی صعودی دیده‌شده": upSimilar,
        "تعداد الگوی نزولی دیده‌شده": downSimilar,
    }


def run_markov_backtest(tickers, start, end, n=2, cash=1000, commission=0.0002,
                        mode="buy+sell", data_by_ticker=None):
    """اجرای بک‌تست مارکوف روی همهٔ تیکرها؛ خروجی: metrics + جدول نتایج
    اگر data_by_ticker داده شود (دیکشنری {نماد: DataFrame}) از دانلود صرف‌نظر می‌شود."""
    data = data_by_ticker if data_by_ticker else download_ohlc(tickers, start, end)
    metrics = markov_metrics(data, n)

    strategy_cls = _ConsecutiveBuySellStrategy if mode == "buy+sell" else _ConsecutiveBuyStrategy
    strategy_cls.n = n

    rows = []
    for symbol, df in data.items():
        bt_df = df.rename(columns={"open": "Open", "high": "High", "low": "Low",
                                   "close": "Close", "volume": "Volume"})
        if len(bt_df) < 30:
            continue
        bt = Backtest(bt_df, strategy_cls, cash=cash, commission=commission,
                      exclusive_orders=True, margin=1 / 1)
        stats = bt.run()
        rows.append({
            "نماد": symbol,
            "بازده [%]": stats["Return [%]"],
            "وین‌ریت [%]": _winrate(stats),
            "تعداد معامله": stats["# Trades"],
            "حداکثر افت سرمایه [%]": stats["Max. Drawdown [%]"],
            "ضریب شارپ": stats["Sharpe Ratio"],
            "سود خالص [$]": stats["Equity Final [$]"] - cash,
        })
    results = pd.DataFrame(rows)
    aggregate = {}
    if not results.empty:
        aggregate = {
            "مجموع بازده [%]": results["بازده [%]"].sum(),
            "میانگین بازده [%]": results["بازده [%]"].mean(),
            "بهترین نماد": results.loc[results["بازده [%]"].idxmax(), "نماد"],
            "بدترین نماد": results.loc[results["بازده [%]"].idxmin(), "نماد"],
            "میانگین وین‌ریت [%]": results["وین‌ریت [%]"].mean(),
            "بدترین افت سرمایه [%]": results["حداکثر افت سرمایه [%]"].min(),
        }
    return {"metrics": metrics, "results": results, "aggregate": aggregate}


# ===========================================================================
# ۲) بک‌تست Leverage for the Long Run (SPY → UPRO)
# ===========================================================================
def _sma_series(arr, n):
    return pd.Series(arr).rolling(int(n)).mean()


def run_leverage_backtest(base_ticker="SPY", leveraged_ticker="UPRO",
                          start="2023-01-01", end="2025-07-28",
                          sma_length=100, cash=100_000, commission=0.0002,
                          data_by_ticker=None):
    data = data_by_ticker if data_by_ticker else download_ohlc(
        [base_ticker, leveraged_ticker], start, end)
    df_base = data[base_ticker].rename(columns={
        "open": "open_BASE", "high": "high_BASE", "low": "low_BASE",
        "close": "close_BASE", "volume": "volume_BASE"})
    df_lev = data[leveraged_ticker].rename(columns={
        "open": "Open", "high": "High", "low": "Low",
        "close": "Close", "volume": "Volume"})
    merged = pd.concat([df_base, df_lev], axis=1).dropna()
    merged.index.name = "Date"

    sma_length = int(sma_length)

    class LeveragedLongRun(Strategy):
        SMA_Length = sma_length

        def init(self):
            self.sma = self.I(_sma_series, self.data.df["close_BASE"], self.SMA_Length)
            self.spy_close = self.data.df["close_BASE"].values

        def next(self):
            spy_close = self.spy_close[len(self.data) - 1]
            sma_value = self.sma[-1]
            if spy_close > sma_value:
                if not self.position:
                    self.buy()
            else:
                if self.position:
                    self.position.close()

    bt = Backtest(merged, LeveragedLongRun, cash=cash, commission=commission,
                  trade_on_close=False)
    stats = bt.run()
    return {"stats": stats, "df": merged}


# ===========================================================================
# ۳) بک‌تست اسکالپر HA_RSI_CE_EMA
# ===========================================================================
def prepare_scalper_signal(df, rsi_length=7, ha_rsi_length=15, upper=66, lower=28,
                           atr_period=4, atr_multiplier=3):
    """ساخت ستون signal بر اساس منطق نوت‌بوک؛ df باید ستون‌های open/high/low/close داشته باشد."""
    data = df.copy()
    data["closeRsi"] = ta.momentum.RSIIndicator(data["close"], window=ha_rsi_length).rsi()
    data["openRsi"] = ta.momentum.RSIIndicator(data["open"], window=ha_rsi_length).rsi()
    data["highRsi_Raw"] = ta.momentum.RSIIndicator(data["high"], window=ha_rsi_length).rsi()
    data["lowRsi_Raw"] = ta.momentum.RSIIndicator(data["low"], window=ha_rsi_length).rsi()
    data["highRsi"] = data[["highRsi_Raw", "lowRsi_Raw"]].max(axis=1)
    data["lowRsi"] = data[["highRsi_Raw", "lowRsi_Raw"]].min(axis=1)
    data["hclose"] = (data["closeRsi"] + data["openRsi"] + data["highRsi"] + data["lowRsi"]) / 4
    data["hopen"] = data["openRsi"]
    data.dropna(inplace=True)
    data.reset_index(inplace=True)
    for i in range(1, len(data)):
        data.at[i, "hopen"] = (data.loc[i - 1]["hopen"] + data.loc[i - 1]["hclose"]) / 2
    time_col = data.columns[0]
    data.set_index(time_col, inplace=True)
    data["hhigh"] = data[["highRsi", "hopen", "hclose"]].max(axis=1)
    data["hlow"] = data[["lowRsi", "hopen", "hclose"]].min(axis=1)
    data["prehclose"] = data["hclose"].shift(1)
    data["prehopen"] = data["hopen"].shift(1)

    # Chandelier Exit
    data["atr"] = (data["high"] - data["low"]).rolling(window=atr_period).mean()
    data["long"] = data["high"].rolling(window=atr_period).max() - (data["atr"] * atr_multiplier)
    data["short"] = data["low"].rolling(window=atr_period).min() + (data["atr"] * atr_multiplier)
    data["ce"] = np.where(
        (data["close"] > data["short"]) & (data["close"].shift(1) <= data["short"].shift(1)),
        1, np.nan)
    data["ce"] = np.where(
        (data["close"] < data["long"]) & (data["close"].shift(1) >= data["long"].shift(1)),
        -1, data["ce"])
    data["ce"] = data["ce"].ffill().fillna(0)

    data["rsi"] = ta.momentum.RSIIndicator(data["close"], window=rsi_length).rsi()
    data["ema"] = data["close"].ewm(min_periods=200, span=200, adjust=False).mean()
    data.dropna(inplace=True)

    buy = ((data["prehclose"] < lower) &
           (data["prehclose"] < data["prehopen"]) &
           (data["hclose"] > data["hopen"]) &
           (data["close"] > data["ema"]) &
           (data["ce"] == 1))
    sell = ((data["prehclose"] > upper) &
            (data["prehclose"] > data["prehopen"]) &
            (data["hclose"] < data["hopen"]) &
            (data["close"] < data["ema"]) &
            (data["ce"] == -1))
    data["signal"] = np.where(buy, 1, np.nan)
    data["signal"] = np.where(sell, -1, data["signal"])
    return data


def run_scalper_backtest(df, cash=110_000, commission=0.0, size=0.01,
                         rsi_length=7, upper=66, lower=28,
                         risk_pct=0.06, reward_pct=0.12, leverage=100,
                         rsi_length_exit=7):
    """اجرای بک‌تست اسکالپر بر پایه نوت‌بوک HA_RSI_CE_EMA_Scalper_Backtesting"""
    data = prepare_scalper_signal(df, rsi_length=rsi_length_exit)
    data = data.loc[:, ["open", "high", "low", "close", "tick_volume", "signal", "rsi"]]
    data.reset_index(inplace=True)
    time_col = data.columns[0]
    data.columns = ["Local time", "Open", "High", "Low", "Close", "Volume", "signal", "rsi"]
    data.index = pd.DatetimeIndex(data["Local time"])
    bt_df = data.drop(columns=["Local time"])

    risk_pct = float(risk_pct)
    reward_pct = float(reward_pct)
    leverage = float(leverage)
    upper = float(upper)
    lower = float(lower)

    def RiskReward(price, buy=True):
        nb_decimal = str(price)[::-1].find(".") + 2
        varDown = risk_pct / leverage
        varUp = reward_pct / leverage
        if buy:
            tp = np.round(price + varUp * price, nb_decimal)
            sl = np.round(price - varDown * price, nb_decimal)
        else:
            tp = np.round(price - varUp * price, nb_decimal)
            sl = np.round(price + varDown * price, nb_decimal)
        return tp, sl

    signal_series = bt_df["signal"]

    # کتابخانهٔ backtesting حجم کسری را به تعداد «واحد کامل» تبدیل می‌کند
    # (margin_available * size // price)؛ اگر سرمایه برای حداقل ۱ واحد کافی نباشد
    # سفارش لغو می‌شود. پس حجم را خودکار به حداقلِ قابل‌معامله افزایش می‌دهیم.
    size = float(size)
    cash = float(cash)
    first_price = float(bt_df["Close"].iloc[0])
    size_note = ""
    if 0 < size < 1:
        min_frac = first_price / cash
        if size < min_frac:
            new_size = min(max(min_frac * 1.05, size), 0.999)
            size_note = (
                f"⚠️ حجم {size} برای خرید حداقل یک واحد (قیمت {first_price:,.2f} با سرمایه {cash:,.0f}) "
                f"کافی نبود و به‌صورت خودکار به {new_size:.3f} افزایش یافت."
            )
            size = new_size

    class MyStrategy(Strategy):
        def init(self):
            super().init()
            self.signal1 = self.I(lambda: signal_series)

        def next(self):
            super().next()
            if len(self.trades) > 0:
                if self.trades[-1].is_long and self.data.rsi[-1] > upper:
                    self.trades[-1].close()
                elif self.trades[-1].is_short and self.data.rsi[-1] < lower:
                    self.trades[-1].close()
            if self.signal1 == 1 and len(self.trades) == 0:
                tp, sl = RiskReward(self.data.Close[-1])
                self.buy(sl=sl, tp=tp, size=size)
            elif self.signal1 == -1 and len(self.trades) == 0:
                tp, sl = RiskReward(price=self.data.Close[-1], buy=False)
                self.sell(sl=sl, tp=tp, size=size)

    bt = Backtest(bt_df, MyStrategy, cash=cash, commission=commission)
    stats = bt.run()
    return {"stats": stats, "df": bt_df, "size_note": size_note}


# ===========================================================================
# ۴) بهینه‌ساز SMA (SMABestPerformance)
# ===========================================================================
def _rolling_mean_np(a, w):
    if w <= 1:
        return a.copy()
    c = np.cumsum(np.insert(a, 0, 0.0))
    out = np.full_like(a, np.nan, dtype=float)
    out[w - 1:] = (c[w:] - c[:-w]) / w
    return out


def run_sma_optimizer(df, fast_max=60, slow_max=60, fast_min=1, slow_min=1,
                      progress_cb=None):
    """بهینه‌سازی وکتوری استراتژی SMA cross — خروجی: DataFrame نتایج مرتب‌شده"""
    close = df["close"].values.astype(float)
    if len(close) < 50:
        raise RuntimeError("داده برای بهینه‌سازی کافی نیست (حداقل ۵۰ کندل).")
    logret = np.log(close[1:] / close[:-1])
    logret = np.insert(logret, 0, np.nan)

    combos = [(f, s) for f in range(int(fast_min), int(fast_max) + 1)
              for s in range(int(slow_min), int(slow_max) + 1)]
    total = len(combos)
    results = np.empty(total)
    cache = {}
    for idx, (f, s) in enumerate(combos):
        if f not in cache:
            cache[f] = _rolling_mean_np(close, f)
        if s not in cache:
            cache[s] = _rolling_mean_np(close, s)
        fast_ma, slow_ma = cache[f], cache[s]
        valid = ~np.isnan(fast_ma) & ~np.isnan(slow_ma)
        pos = np.where(fast_ma > slow_ma, 1.0, -1.0)
        strat = np.where(valid[1:], pos[:-1], np.nan) * logret[1:]
        strat = strat[~np.isnan(strat)]
        results[idx] = np.exp(np.nansum(strat))
        if progress_cb and idx % 500 == 0:
            progress_cb(idx / total)

    out = pd.DataFrame({
        "SMA_FAST": [c[0] for c in combos],
        "SMA_SLOW": [c[1] for c in combos],
        "performance": results,
    }).sort_values("performance", ascending=False).reset_index(drop=True)
    return out


# =========================================================================# ===========================================================================
# ابزار مشترک
# ===========================================================================
def _winrate(stats):
    trades = stats["_trades"]
    if trades is None or len(trades) == 0:
        return 0.0
    wins = (trades["PnL"] > 0).sum()
    return 100.0 * wins / len(trades)


def stats_summary(stats):
    """خلاصهٔ فارسی آمار بک‌تست برای نمایش در UI"""
    trades = stats["_trades"]
    winrate = _winrate(stats)
    ec = stats["_equity_curve"]
    initial = ec["Equity"].iloc[0]
    summary = {
        "بازده کل [%]": stats["Return [%]"],
        "وین‌ریت [%]": winrate,
        "تعداد معاملات": int(stats["# Trades"]),
        "سود خالص [$]": stats["Equity Final [$]"] - initial,
        "ارزش نهایی حساب [$]": stats["Equity Final [$]"],
        "حداکثر افت سرمایه [%]": stats["Max. Drawdown [%]"],
        "میانگین طول معامله": str(stats["Avg. Trade Duration"]),
        "بهترین معامله [%]": stats["Best Trade [%]"],
        "بدترین معامله [%]": stats["Worst Trade [%]"],
        "ضریب شارپ": stats["Sharpe Ratio"],
        "ضریب سورتینو": stats["Sortino Ratio"],
        "بازده خرید-نگهداری [%]": stats["Buy & Hold Return [%]"],
    }
    if len(trades) > 0:
        gross_win = trades.loc[trades["PnL"] > 0, "PnL"].sum()
        gross_loss = -trades.loc[trades["PnL"] < 0, "PnL"].sum()
        summary["پروفیت فاکتور"] = (gross_win / gross_loss) if gross_loss > 0 else float("inf")
    return summary


def equity_curve(stats):
    ec = stats["_equity_curve"]
    if "DrawdownPct" in ec.columns:      # backtesting >= 0.6
        dd = -ec["DrawdownPct"] * 100
    elif "Drawdown" in ec.columns:       # نسخه‌های قدیمی
        dd = ec["Drawdown"] * 100
    else:
        dd = pd.Series(0.0, index=ec.index)
    return pd.DataFrame({"Equity": ec["Equity"], "Drawdown %": dd})


def trades_table(stats, limit=200):
    trades = stats["_trades"]
    if trades is None or len(trades) == 0:
        return pd.DataFrame()
    t = trades.copy()
    t = t.tail(limit)
    cols_map = {}
    for c in t.columns:
        cl = c.lower()
        if cl == "size": cols_map[c] = "حجم"
        elif cl == "entrybar": cols_map[c] = "کندل ورود"
        elif cl == "exitbar": cols_map[c] = "کندل خروج"
        elif cl == "entryprice": cols_map[c] = "قیمت ورود"
        elif cl == "exitprice": cols_map[c] = "قیمت خروج"
        elif cl == "pnl": cols_map[c] = "سود/زیان"
        elif cl == "returnpct": cols_map[c] = "بازده ٪"
        elif cl == "entrytime": cols_map[c] = "زمان ورود"
        elif cl == "exittime": cols_map[c] = "زمان خروج"
        elif cl == "duration": cols_map[c] = "مدت"
    t = t.rename(columns=cols_map)
    return t
