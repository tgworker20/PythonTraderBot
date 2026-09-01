# SP2L Control Center — MT5 Strategy Indicators (English)

Faithful MQL5 ports of **every live-trading strategy** in the PythonTraderBot
Control Center (strategies by Alireza Sadabadi). Each strategy is a separate
indicator file — copy the ones you want into `MQL5\Indicators`, compile (F7)
and drop them on a chart.

> All of them are chart **indicators only** — they never place orders.
> Recommended charts are the author's own setups, but every input is
> adjustable (symbol / timeframe do not matter to the code).

| File | Strategy (source) | Author's chart | What you get |
|---|---|---|---|
| `SP2L_Indicator.mq5` | SP2L_Bot.py + SP2L_Advanced_Bot.py | XAUUSD M1 | entry arrows, SL/TP/entry/second-entry levels, spike markers, filters (see its own README) |
| `EasyBot_SMA_Indicator.mq5` | EasyBot.py | BITCOIN M1 | SMA 20/200 cross entries + SL, opposite-cross exits |
| `BB_Full_Indicator.mq5` | BB_Full.py (TraderBot #1) | BITCOIN H4 | full Bollinger band reversal entries, SL, band-cross exits, trailing |
| `BB_Half_Indicator.mq5` | BB_Half.py (TraderBot #2) | BITCOIN H4 | half-band entries with the slope (range) filter, SL, middle-band exits |
| `CE_ZLSMA_HA_Indicator.mq5` | CE_ZLSMA_HA.py + CE_ZLSMA_HA_ATR.py (TraderBot #4) | BITCOIN H4 | Chandelier Exit + ZLSMA + Heikin Ashi entries, SL/TP (percent or ATR mode), HA/ZLSMA exits |
| `HA_RSI_Scalper_Indicator.mq5` | HA_RSI_CE_EMA_Scalper.py (TraderBot #3) | BITCOIN M1 | Heikin-Ashi-of-RSI scalps with the EMA200 filter, SL, RSI exits |
| `VWAP_BB_RSI_Indicator.mq5` | VWAP_BB_RSI.py (TraderBot #5) | altcoins M5 | VWAP-trend + Bollinger + RSI entries with ATR SL/TP |
| `MichaelHarris_Indicator.mq5` | run_michael_harris_backtest.py | CARDANO H4 | the 7-condition candle pattern with SL 2% / TP 9% |

## Installation (Windows, MT5)

1. In MetaTrader 5 open **File → Open Data Folder**.
2. Copy the `.mq5` files into `MQL5\Indicators\`.
3. Open **MetaEditor** (F4), open each file and press **Compile** (F7) — 0 errors expected.
4. In MT5 **Navigator → Indicators** drag the indicator onto the chart.

## How to read the charts

- **Green up / red down arrows** — strategy entry signals (as the Python bot would trade them).
- **Silver ✗ markers** — where the virtual position closed, with the reason
  in a small label (`SL/trailing`, `TP`, `band cross`, `RSI`, …).
- **Red line** — the stop loss the bot would send; **green line** — the take
  profit (only for the bots that actually set one); **blue dotted line** — the
  entry price; lines extend `ExtendBars` bars to the right.
- Each indicator emulates the bot's **one-position-at-a-time** state machine
  and its **trailing stop** (where the bot uses one), so signals are only
  drawn when the bot would actually be flat.

## Faithfulness notes (important)

- Formulas are replicated exactly as the Python computes them, including
  **pandas sample standard deviation** (ddof=1) for the Bollinger bands,
  **Wilder RMA** for RSI/ATR, **EMA-seeded ZLSMA**, Heikin Ashi seeding, and
  the **sliding evaluation window** of each bot (BB = 47/40 bars,
  CE_ZLSMA = 73 bars, scalper = 390 bars, VWAP bot = 50 bars) — every series
  is seeded exactly like the bot's own data window.
- Entry price = close of the signal candle (the live bot fills at the market
  ask/bid a few seconds later); exits are detected on closed bars, while the
  live bot reacts tick-by-tick — so occasional one-bar differences are normal.
- Percent SL/TP inputs follow the author's `Meta.RiskReward` formula:
  `distance = pct / leverage × price` — set `Leverage` to your account
  leverage. Bots with magic 1/2/3/0 (BB_Full, BB_Half, scalper, EasyBot) do
  **not** set a live TP; their TP line is drawn only as a reference.
- `CE_ZLSMA_HA_Indicator` defaults to the **ATR mode** of
  `CE_ZLSMA_HA_ATR.py` (SL = 1×ATR(7), TP = 2.16×SL). Switch `SL/TP mode`
  to *Percent* for the original `CE_ZLSMA_HA.py` (TP 2% / SL 1% via
  RiskReward). Note: in the ATR bot the author passes ATR values into the
  percent path (a known quirk of his code — flagged in the interface too);
  the indicator implements the intended ATR behaviour by default.
- ⚠️ **pandas-ta compatibility warning**: with the current pandas-ta
  (≥ 0.4.67) the author's `zlma(..., mamode='simple')` call returns `None`,
  so the Python CE_ZLSMA bots produce **no signals / crash** on modern
  installs. This indicator implements the math the original pandas-ta
  (0.3.x, which the author used) actually computed — EMA fallback with SMA
  seed — i.e. the strategy as the author knows it.
- The `MichaelHarris` indicator mirrors the backtest: SL/TP are computed
  from the signal candle's close; the backtest itself fills at the next
  open.
- Claimed win rates in the interface (84% SP2L, 62% VWAP, 1700% CE_ZLSMA…)
  are the **author's claims** — use the interface's backtest page to verify
  them on your own data before risking money.

## Quick input reference (author's defaults)

All inputs default to the author's values (BB body/gap filters 600/1100/100
are Bitcoin-calibrated — change them for other symbols; the scalper's
66/28 RSI bands, VWAP bot's 46/59 entry and 90/10 exit levels, CE
multiplier 1.95/3, ZLSMA 33, EMA 200, SMA 20/200 etc.). Every number that
is hardcoded in the Python files is an input here.
