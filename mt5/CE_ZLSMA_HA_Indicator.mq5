//+------------------------------------------------------------------+
//|                                        CE_ZLSMA_HA_Indicator.mq5 |
//|   Chandelier Exit + Zero-Lag MA + Heikin Ashi - port of          |
//|   CE_ZLSMA_HA.py and CE_ZLSMA_HA_ATR.py (TraderBot magic 4)      |
//|                     (strategy by Alireza Sadabadi)               |
//|                                                                  |
//|  Logic (H4 in the author's setup, BITCOIN):                      |
//|    - Heikin Ashi: hclose=(O+H+L+C)/4, hopen=(prev hopen+hclose)/2|
//|    - ZLSMA over hclose with length 33:                           |
//|        lag = (33-1)/2 = 16,  de = 2*hclose - hclose[16]          |
//|        ZLSMA = EMA(de, 33) with SMA seed (pandas_ta zlma         |
//|        'simple' falls back to EMA in the author's version)       |
//|    - Chandelier Exit: atr = SMA(high-low, 3),                    |
//|        long  = max(high,3) - atr*1.95,  short = min(low,3)       |
//|        + atr*1.95                                                |
//|    - BUY : close crosses above 'short' + bullish HA candle       |
//|            + hclose above ZLSMA                                   |
//|    - SELL: close crosses below 'long' + bearish HA candle        |
//|            + hclose below ZLSMA                                   |
//|    - Exit: opposite HA/ZLSMA condition.                          |
//|    - SL/TP: CE_ZLSMA_HA uses percent (2%/1% via RiskReward,      |
//|      TP is set live for magic 4); CE_ZLSMA_HA_ATR uses           |
//|      SL = 1*ATR(7), TP = 2.16*SL (the author's intent).          |
//|                                                                  |
//|  IMPORTANT: with the CURRENT pandas-ta (>=0.4.67) the author's   |
//|  call zlma(mamode='simple') returns None and the Python bot      |
//|  produces no signals; this indicator implements the intended     |
//|  math of the original (0.3.x) pandas-ta, which the author used.  |
//|                                                                  |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "CE_ZLSMA_HA strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "Chandelier Exit + ZLSMA + Heikin Ashi signals (CE_ZLSMA_HA.py / CE_ZLSMA_HA_ATR.py port)"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

#property indicator_label1  "ZLSMA (HA)"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  2
#property indicator_label2  "CE long"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrSeaGreen
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_label3  "CE short"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrTomato
#property indicator_style3  STYLE_DOT
#property indicator_width3  1
#property indicator_label4  "CE_ZLSMA BUY"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2
#property indicator_label5  "CE_ZLSMA SELL"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrRed
#property indicator_width5  2
#property indicator_label6  "Exit long"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrSilver
#property indicator_width6  1
#property indicator_label7  "Exit short"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  clrSilver
#property indicator_width7  1

enum ENUM_SLTP_MODE
  {
   SLTP_ATR      = 0,   // ATR distances (CE_ZLSMA_HA_ATR: SL=1*ATR7, TP=2.16*SL)
   SLTP_PERCENT  = 1    // Percent via RiskReward (CE_ZLSMA_HA: TP 2% / SL 1%)
  };

//--- === Strategy (author's defaults) ===
input int            InpATRPeriod     = 3;      // Chandelier ATR period (rolling mean of range)
input double         InpATRMultiplier = 1.95;   // Chandelier multiplier
input int            InpZLSMALength   = 33;     // ZLSMA length
input ENUM_SLTP_MODE InpSLTPMode      = SLTP_ATR; // SL/TP mode
input int            InpSLATRLength   = 7;      // ATR length for the ATR SL/TP mode
input double         InpSLATRFactor   = 1.0;    // SL = factor * ATR (CE_ZLSMA_HA_ATR: 1.0)
input double         InpTPFactor      = 2.16;   // TP = factor * SL (CE_ZLSMA_HA_ATR: 2.16)
input double         InpLeverage      = 100;    // Leverage (percent mode RiskReward)
input double         InpPctTP         = 2.0;    // TP percent (percent mode)
input double         InpPctSL         = 1.0;    // SL percent (percent mode)
input bool           InpUseTrailing   = true;   // Emulate the bot's trailing stop

//--- === Display ===
input bool           InpShowLines     = true;   // Show ZLSMA / Chandelier lines
input int            InpExtendBars    = 20;     // How many bars the SL/TP/entry lines extend
input bool           InpShowLabels    = true;   // Show text labels
input int            InpMaxBars       = 3000;   // History depth to scan
input color          InpSLColor       = clrRed;         // SL line color
input color          InpTPColor       = clrGreen;       // TP line color
input color          InpEntryColor    = clrDodgerBlue;  // Entry line color

//--- === Alerts ===
input bool           InpAlerts        = true;   // Pop-up alert on a new signal
input bool           InpPushAlerts    = false;  // Push notification on a new signal

double BufZLSMA[];
double BufCELong[];
double BufCEShort[];
double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "CEZLSMA_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos = 0;
double gEntry = 0.0, gSL = 0.0, gSL0 = 0.0, gTP = 0.0;
double gExtPrice = 0.0;

// sliding window (the Python bot refetches ZLSMALength+40 bars every
// evaluation, so every series is seeded exactly like the bot's window)
int gWin = 73;
double wOpen[], wHigh[], wLow[], wClose[];
double wHOpen[], wHClose[], wZLSMA[], wCELong[], wCEShort[], wATR7[];

//+------------------------------------------------------------------+
double ArrowOffset(const double hi, const double lo)
  {
   return (0.3 * (hi - lo) + 3.0 * gPoint);
  }

//+------------------------------------------------------------------+
void CreateLevelLine(const string tag, const datetime t1, const double price,
                     const color clr, const ENUM_LINE_STYLE style, const int width,
                     const string tooltip)
  {
   string   name = gPrefix + tag;
   datetime t2   = t1 + (datetime)(InpExtendBars * PeriodSeconds(_Period));
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t1, price, t2, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, width);
   ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   ObjectSetInteger(0, name, OBJPROP_RAY_LEFT, false);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   ObjectSetString(0, name, OBJPROP_TOOLTIP, tooltip);
  }

//+------------------------------------------------------------------+
void CreateLabel(const string tag, const datetime t, const double price,
                 const string text, const color clr, const ENUM_ANCHOR_POINT anchor)
  {
   string name = gPrefix + tag;
   if(ObjectFind(0, name) >= 0)
      ObjectDelete(0, name);
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 8);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

//+------------------------------------------------------------------+
//| Wilder RMA of an array (ewm alpha=1/n, adjust=False)             |
//| out[j] = out[j-1] + (in[j]-out[j-1])/n, seeded with first valid  |
//+------------------------------------------------------------------+
void RmaArray(const double &src[], const int n, double &dst[])
  {
   int m = ArraySize(src);
   ArrayResize(dst, m);
   for(int j = 0; j < m; j++)
      dst[j] = EMPTY_VALUE;
   for(int j = 0; j < m; j++)
     {
      if(src[j] == EMPTY_VALUE)
         continue;
      if(j == 0 || dst[j - 1] == EMPTY_VALUE)
         dst[j] = src[j];
      else
         dst[j] = dst[j - 1] + (src[j] - dst[j - 1]) / n;
     }
  }

//+------------------------------------------------------------------+
//| Compute every window series for the window ending at shift sEnd  |
//| (rows are chronological: row 0 = oldest, row gWin-1 = sEnd)      |
//+------------------------------------------------------------------+
bool ComputeWindow(const int sEnd, const datetime &time[], const double &open[],
                   const double &high[], const double &low[], const double &close[])
  {
   if(sEnd + gWin - 1 >= ArraySize(close))
      return false;

   ArrayResize(wOpen, gWin);
   ArrayResize(wHigh, gWin);
   ArrayResize(wLow, gWin);
   ArrayResize(wClose, gWin);
   for(int j = 0; j < gWin; j++)
     {
      int sh = sEnd + (gWin - 1) - j;
      wOpen[j]  = open[sh];
      wHigh[j]  = high[sh];
      wLow[j]   = low[sh];
      wClose[j] = close[sh];
     }

   //--- Heikin Ashi (exactly like the bot: seeded at the window start)
   ArrayResize(wHOpen, gWin);
   ArrayResize(wHClose, gWin);
   for(int j = 0; j < gWin; j++)
      wHClose[j] = (wOpen[j] + wHigh[j] + wLow[j] + wClose[j]) / 4.0;
   wHOpen[0] = wOpen[0];
   for(int j = 1; j < gWin; j++)
      wHOpen[j] = (wHOpen[j - 1] + wHClose[j - 1]) / 2.0;

   //--- ZLSMA: de = 2*hclose - hclose[lag]; EMA(de, len) with SMA seed
   int len = InpZLSMALength;
   int lag = (int)(0.5 * (len - 1));
   ArrayResize(wZLSMA, gWin);
   for(int j = 0; j < gWin; j++)
      wZLSMA[j] = EMPTY_VALUE;
   int seedIdx = len - 1;                       // row 32 for len 33
   if(gWin > seedIdx)
     {
      double s = 0.0;
      int cnt = 0;
      for(int j = 0; j <= seedIdx; j++)         // SMA of first `len` de values
        {
         if(j >= lag)
           {
            s += 2.0 * wHClose[j] - wHClose[j - lag];
            cnt++;
           }
        }
      if(cnt > 0)
         wZLSMA[seedIdx] = s / cnt;
      double k = 2.0 / (len + 1.0);
      for(int j = seedIdx + 1; j < gWin; j++)
         wZLSMA[j] = wZLSMA[j - 1] + k * ((2.0 * wHClose[j] - wHClose[j - lag]) - wZLSMA[j - 1]);
     }

   //--- Chandelier Exit (rolling mean of the simple range)
   int p = InpATRPeriod;
   ArrayResize(wATR7, gWin);
   ArrayResize(wCELong, gWin);
   ArrayResize(wCEShort, gWin);
   for(int j = 0; j < gWin; j++)
     {
      wATR7[j]   = EMPTY_VALUE;
      wCELong[j] = EMPTY_VALUE;
      wCEShort[j] = EMPTY_VALUE;
      if(j < p - 1)
         continue;
      double sumR = 0.0, mx = -DBL_MAX, mn = DBL_MAX;
      for(int i = j - p + 1; i <= j; i++)
        {
         sumR += wHigh[i] - wLow[i];
         if(wHigh[i] > mx) mx = wHigh[i];
         if(wLow[i]  < mn) mn = wLow[i];
        }
      double atr = sumR / p;
      wCELong[j]  = mx - atr * InpATRMultiplier;
      wCEShort[j] = mn + atr * InpATRMultiplier;
     }

   //--- ATR(7) Wilder for the ATR SL/TP mode (pandas_ta atr: rma of TR)
   if(InpSLTPMode == SLTP_ATR)
     {
      double tr[];
      ArrayResize(tr, gWin);
      for(int j = 0; j < gWin; j++)
        {
         if(j == 0)
            tr[j] = EMPTY_VALUE;      // prenan: first bar has no previous close
           else
            tr[j] = MathMax(wHigh[j] - wLow[j],
                            MathMax(MathAbs(wHigh[j] - wClose[j - 1]),
                                    MathAbs(wClose[j - 1] - wLow[j])));
        }
      RmaArray(tr, InpSLATRLength, wATR7);
     }

   return true;
  }

//+------------------------------------------------------------------+
void DrawEntry(const bool isBuy, const int s, const double entry, const double sl,
               const double tp, const datetime &time[], const double &high[],
               const double &low[])
  {
   datetime t  = time[s];
   string   id = TimeToString(t, TIME_DATE | TIME_MINUTES);
   StringReplace(id, ".", "-");
   StringReplace(id, ":", "-");
   StringReplace(id, " ", "_");
   string dirTxt = isBuy ? "BUY" : "SELL";

   if(isBuy)
      BufBuy[s]  = low[s] - ArrowOffset(high[s], low[s]);
   else
      BufSell[s] = high[s] + ArrowOffset(high[s], low[s]);

   CreateLevelLine(id + "_ENTRY", t, entry, InpEntryColor, STYLE_DOT, 1,
                   "CE_ZLSMA " + dirTxt + " entry");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "CE_ZLSMA SL");
   CreateLevelLine(id + "_TP", t, tp, InpTPColor, STYLE_SOLID, 2, "CE_ZLSMA TP");

   if(InpShowLabels)
     {
      string txt = StringFormat("CE_ZLSMA %s  E:%s SL:%s TP:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits));
      CreateLabel(id + "_TXT", t, tp, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("CE_ZLSMA %s on %s %s | entry %s SL %s TP %s",
                                dirTxt, _Symbol, EnumToString(_Period),
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits));
      if(InpAlerts)
         Alert(msg);
      if(InpPushAlerts)
         SendNotification(msg);
     }
  }

//+------------------------------------------------------------------+
void DrawExit(const bool wasLong, const int s, const string reason,
              const datetime &time[], const double &high[], const double &low[])
  {
   datetime t  = time[s];
   string   id = TimeToString(t, TIME_DATE | TIME_MINUTES) + "_X";
   StringReplace(id, ".", "-");
   StringReplace(id, ":", "-");
   StringReplace(id, " ", "_");
   if(wasLong)
      BufExitBuy[s]  = high[s] + ArrowOffset(high[s], low[s]);
   else
      BufExitSell[s] = low[s] - ArrowOffset(high[s], low[s]);
   if(InpShowLabels)
      CreateLabel(id + "_TXT", t, wasLong ? high[s] : low[s],
                  StringFormat("EXIT (%s)", reason), clrSilver,
                  wasLong ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
   if(s == 1 && gPrevCalculated > 0 && InpAlerts)
      Alert(StringFormat("CE_ZLSMA EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
                         _Symbol, EnumToString(_Period), reason));
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
  {
   if(!ComputeWindow(s, time, open, high, low, close))
      return;
   int cur = gWin - 1;     // signal candle = iloc[-2] of the bot's window
   int prv = gWin - 2;     // iloc[-3]

   if(wZLSMA[cur] == EMPTY_VALUE || wZLSMA[prv] == EMPTY_VALUE ||
      wCEShort[cur] == EMPTY_VALUE || wCEShort[prv] == EMPTY_VALUE ||
      wCELong[cur] == EMPTY_VALUE || wCELong[prv] == EMPTY_VALUE)
      return;

   //--- manage the open virtual position
   if(gPos != 0)
     {
      if(InpUseTrailing)
        {
         if(gPos > 0)
           {
            if(high[s] > gExtPrice)
               gExtPrice = high[s];
            gSL = gSL0 + (gExtPrice - gEntry);
           }
         else
           {
            if(low[s] < gExtPrice)
               gExtPrice = low[s];
            gSL = gSL0 - (gEntry - gExtPrice);
           }
        }
      if(gPos > 0 && low[s] <= gSL)
        {
         DrawExit(true, s, "SL/trailing", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && high[s] >= gSL)
        {
         DrawExit(false, s, "SL/trailing", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos > 0 && gTP > 0.0 && high[s] >= gTP)
        {
         DrawExit(true, s, "TP", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && gTP > 0.0 && low[s] <= gTP)
        {
         DrawExit(false, s, "TP", time, high, low);
         gPos = 0;
         return;
        }
      // strategy exit: opposite HA/ZLSMA condition
      if(gPos > 0 && wHClose[cur] < wHOpen[cur] && wHClose[cur] < wZLSMA[cur])
        {
         DrawExit(true, s, "HA/ZLSMA", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && wHClose[cur] > wHOpen[cur] && wHClose[cur] > wZLSMA[cur])
        {
         DrawExit(false, s, "HA/ZLSMA", time, high, low);
         gPos = 0;
         return;
        }
      return;   // position still open - no new signals (status flag)
     }

   //--- entry signals (status == False)
   bool crossUp   = (wClose[cur] > wCEShort[cur]) && (wClose[prv] <= wCEShort[prv]);
   bool crossDown = (wClose[cur] < wCELong[cur]) && (wClose[prv] >= wCELong[prv]);

   bool buy  = crossUp && (wHClose[cur] > wHOpen[cur]) && (wHClose[cur] > wZLSMA[cur]);
   bool sell = crossDown && (wHClose[cur] < wHOpen[cur]) && (wHClose[cur] < wZLSMA[cur]);

   if(buy || sell)
     {
      gEntry    = close[s];
      gExtPrice = gEntry;
      if(InpSLTPMode == SLTP_ATR)
        {
         double atr = (wATR7[cur] == EMPTY_VALUE) ? 0.0 : wATR7[cur];
         double slDist = InpSLATRFactor * atr;
         if(slDist <= 0.0)
            return;
         gSL0 = buy ? (gEntry - slDist) : (gEntry + slDist);
         gSL  = gSL0;
         gTP  = buy ? (gEntry + InpTPFactor * slDist) : (gEntry - InpTPFactor * slDist);
        }
      else
        {
         gSL0 = buy ? gEntry * (1.0 - InpPctSL / InpLeverage)
                    : gEntry * (1.0 + InpPctSL / InpLeverage);
         gSL  = gSL0;
         gTP  = buy ? gEntry * (1.0 + InpPctTP / InpLeverage)
                    : gEntry * (1.0 - InpPctTP / InpLeverage);
        }
      gPos = buy ? 1 : -1;
      DrawEntry(buy, s, gEntry, gSL, gTP, time, high, low);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   gPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0)
      return INIT_FAILED;
   gWin = InpZLSMALength + 40;      // exactly like the bot (number_of_data)

   SetIndexBuffer(0, BufZLSMA, INDICATOR_DATA);
   SetIndexBuffer(1, BufCELong, INDICATOR_DATA);
   SetIndexBuffer(2, BufCEShort, INDICATOR_DATA);
   SetIndexBuffer(3, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(4, BufSell, INDICATOR_DATA);
   SetIndexBuffer(5, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(6, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufZLSMA, true);
   ArraySetAsSeries(BufCELong, true);
   ArraySetAsSeries(BufCEShort, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufExitBuy, true);
   ArraySetAsSeries(BufExitSell, true);

   PlotIndexSetInteger(3, PLOT_ARROW, 233);
   PlotIndexSetInteger(4, PLOT_ARROW, 234);
   PlotIndexSetInteger(5, PLOT_ARROW, 251);
   PlotIndexSetInteger(6, PLOT_ARROW, 251);
   for(int i = 0; i < 7; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   int dt = InpShowLines ? DRAW_LINE : DRAW_NONE;
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, dt);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, dt);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, dt);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("CE_ZLSMA_HA (%d, %.2f)", InpZLSMALength, InpATRMultiplier));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, gPrefix);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total, const int prev_calculated,
                const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &tick_volume[], const long &volume[], const int &spread[])
  {
   gPrevCalculated = prev_calculated;
   if(rates_total < gWin + 5)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufZLSMA, EMPTY_VALUE);
      ArrayInitialize(BufCELong, EMPTY_VALUE);
      ArrayInitialize(BufCEShort, EMPTY_VALUE);
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufExitBuy, EMPTY_VALUE);
      ArrayInitialize(BufExitSell, EMPTY_VALUE);
      gPos = 0;
      ObjectsDeleteAll(0, gPrefix);

      int maxShift = MathMin(InpMaxBars, rates_total - gWin - 1);
      for(int s = maxShift; s >= 0; s--)
        {
         if(ComputeWindow(s, time, open, high, low, close))
           {
            int cur = gWin - 1;
            if(wZLSMA[cur] != EMPTY_VALUE)
               BufZLSMA[s] = wZLSMA[cur];
            if(wCELong[cur] != EMPTY_VALUE)
               BufCELong[s] = wCELong[cur];
            if(wCEShort[cur] != EMPTY_VALUE)
               BufCEShort[s] = wCEShort[cur];
           }
        }
      for(int s = maxShift; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }
   else
     {
      int newBars = rates_total - prev_calculated;
      for(int i = 0; i <= newBars && i < rates_total; i++)
        {
         BufBuy[i] = EMPTY_VALUE;
         BufSell[i] = EMPTY_VALUE;
         BufExitBuy[i] = EMPTY_VALUE;
         BufExitSell[i] = EMPTY_VALUE;
        }
      for(int i = newBars; i >= 0; i--)
        {
         if(ComputeWindow(i, time, open, high, low, close))
           {
            int cur = gWin - 1;
            if(wZLSMA[cur] != EMPTY_VALUE)
               BufZLSMA[i] = wZLSMA[cur];
            if(wCELong[cur] != EMPTY_VALUE)
               BufCELong[i] = wCELong[cur];
            if(wCEShort[cur] != EMPTY_VALUE)
               BufCEShort[i] = wCEShort[cur];
           }
        }
      for(int s = newBars; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
