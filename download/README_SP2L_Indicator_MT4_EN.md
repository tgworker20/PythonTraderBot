# SP2L Indicator for MetaTrader 4 (English)

The **MT4 (MQL4) version** of the SP2L indicator - same logic, same inputs and
same default settings as the MT5 version (`mt5/SP2L_Indicator.mq5`).

It is a faithful port of the **SP2L strategy** (Spike + Pullback + Gap) by
Alireza Sadabadi, taken directly from his Python code in `code/SP2L/`
(`SP2L_Bot.py` and `SP2L_Advanced_Bot.py`).

The indicator draws **BUY / SELL arrows together with the exact SL and TP
levels** of the strategy on the chart - the same levels the Python bot would
send to the broker.

> This is a chart **indicator only** - it never places orders.
> Requires MT4 **build 600 or newer** (any MT4 from 2014 onwards).

---

## Installation (Windows)

1. In MetaTrader 4 open **File → Open Data Folder**.
2. Go to `MQL4\Indicators\` and copy `SP2L_Indicator.mq4` there.
3. Open **MetaEditor** (F4 from MT4), open `MQL4\Indicators\SP2L_Indicator.mq4`
   and press **Compile** (F7). It should show *0 errors*.
4. Back in MT4, open **Navigator → Indicators** (refresh if needed) and drag
   **SP2L** onto your chart (the strategy is designed for **XAUUSD, M1** - but
   it works on any symbol/timeframe you set it on).

## What you see on the chart

| Object | Meaning |
|---|---|
| Green up arrow | SP2L BUY entry |
| Red down arrow | SP2L SELL entry |
| Red solid line | **SL** - low (buy) / high (sell) of the candle **before** the spike |
| Green solid line | **TP** - entry ± `TP_R` × risk |
| Blue dotted line | Entry level (advanced mode) |
| Orange dotted line | Optional second entry level (entry ∓ risk/2) |
| Aqua / magenta diamond | The detected spike candle of a setup |
| Silver dotted line | EMA filter line (period 60 by default) |
| Text label | `SP2L BUY E:… SL:… TP:…` values of the signal |

## Strategy modes

- **Advanced** (default) - exact port of `SP2L_Advanced_Bot.py`:
  - spike setup detection (spike body ≥ `SpikeCandleSize` × neighbours,
    pullback gap ≥ `PGapPoints` points, all 8 candle-pattern conditions),
  - **pending setup** that waits for the first valid entry candle
    (low/high break vs the previous candle), exactly like the bot,
  - max SL distance filter (`MaxSLPoints`),
  - EMA filter (close above/below EMA),
  - trend-structure filter (max consecutive opposite moves),
  - optional ADX filter, optional New-York session filter,
  - TP as `TP_R` × risk and the optional second-entry level.
- **Simple** - exact port of `SP2L_Bot.py`: immediate entry at the signal
  candle, SL = low/high of the candle before the spike, TP = 1R.

## Main inputs (defaults = the author's settings)

| Input | Default | Meaning |
|---|---|---|
| `Strategy mode` | Advanced | Advanced (SP2L_Advanced_Bot) or Simple (SP2L_Bot) |
| `Spike candle size` | 0 (auto) | Spike body must be ≥ x times the neighbours. 0 = auto: Simple uses 2.0, Advanced uses 1.5 (the author's values) |
| `Pullback gap in points` | 100 | Gap between candle -2 and candle -4 (simple bot: 1.0 price unit = 100 pts on XAUUSD) |
| `Max SL distance in points` | 1000 | Advanced mode: setups with a larger risk are invalidated |
| `Take profit as R multiple` | 1.0 | TP = entry ± R × risk |
| `Use EMA filter` / `EMA period` | true / 60 | Entry only in the EMA direction |
| `Use trend structure filter` / `Max opposite moves` | true / 1 | Max consecutive lower-highs (buy) / higher-lows (sell) |
| `Use ADX filter` / `ADX period` / `Min ADX` | false / 14 / 20 | Optional range filter |
| `Use session filter` / hours | false / 1-5 | Optional session window (server or New-York time) |
| `Show the second entry level` | false | Draws entry ∓ risk/2 |
| `Skip signals while trade open` | false | Emulates the bot's "one trade at a time" behaviour |
| `History depth to scan` | 3000 | How many bars back to draw signals |
| `Pop-up alert` / `Push notification` | true / false | Alerts when a new signal appears |

## Notes

- Signals are evaluated on **closed candles**; the live Python bot evaluates
  the forming candle every 10 seconds, so on very rare occasions a live
  signal can appear one candle earlier/later than the indicator's historical
  drawing.
- In Simple mode the entry price is the close of the signal candle (the bot
  uses the live ask/bid of that moment).
- The session filter assumes the broker server is UTC+3 (same assumption as
  the author's `Meta.py`); you can switch the hours to server time instead.
- MT4 has no strategy tester for custom-indicator logic; use the interface's
  Python backtest (📈 Backtest page) to measure the real historical win rate.
