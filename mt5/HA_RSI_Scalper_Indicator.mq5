//+------------------------------------------------------------------+
//|                                     HA_RSI_Scalper_Indicator.mq5 |
//|   Heikin-Ashi-of-RSI scalper - port of HA_RSI_CE_EMA_Scalper.py  |
//|   (TraderBot strategy 3, by Alireza Sadabadi)                   |
//|                                                                  |
//|  Logic (M1 in the author's setup, BITCOIN):                      |
//|    - RSI(open/high/low/close) with length 15 -> Heikin Ashi      |
//|      candles built ON the RSI values                             |
//|    - BUY : previous HA-RSI candle below `lower` and bearish,     |
//|            signal HA-RSI candle bullish, close above EMA200,     |
//|            and the Chandelier-Exit state == 1                    |
//|    - SELL: mirror (above `upper`, close below EMA200, CE == -1)  |
//|    - Exit: RSI(7) above `upper` (long) / below `lower` (short)   |
//|    - SL = entry*(1 -/+ 0.06/leverage); no TP (magic 3);          |
//|      trailing stop used live.                                    |
//|                                                                  |
//|  The bot refetches ~390 bars each evaluation, so every series    |
//|  here is seeded exactly like the bot's 390-bar window.           |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "HA_RSI_CE_EMA scalper strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "Heikin-Ashi-of-RSI scalper signals (HA_RSI_CE_EMA_Scalper.py port) with SL and exits"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

#property indicator_label1  "EMA filter"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
#property indicator_label2  "Scalper BUY"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
#property indicator_label3  "Scalper SELL"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2
#property indicator_label4  "Exit long"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrSilver
#property indicator_width4  1
#property indicator_label5  "Exit short"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrSilver
#property indicator_width5  1

//--- === Strategy (HA_RSI_CE_EMA_Scalper.py defaults) ===
input int    InpRSILength     = 7;      // Exit RSI length (rsiLength)
input int    InpHARSILength   = 15;     // HA-RSI length (haRsiLength)
input double InpUpper         = 66.0;   // RSI upper level
input double InpLower         = 28.0;   // RSI lower level
input int    InpATRPeriod     = 4;      // Chandelier ATR period
input double InpATRMultiplier = 3.0;    // Chandelier multiplier
input int    InpEMALength     = 200;    // EMA filter length
input double InpLeverage      = 100;    // Account leverage (RiskReward SL)
input double InpPctTP         = 0.12;   // TP percent (not set live - reference)
input double InpPctSL         = 0.06;   // SL percent (pct_sl)
input bool   InpUseTrailing   = true;   // Emulate the bot's trailing stop

//--- === Display ===
input bool   InpShowEMA       = true;   // Show EMA filter line
input int    InpExtendBars    = 20;     // How many bars the SL/entry lines extend
input bool   InpShowLabels    = true;   // Show text labels
input int    InpMaxBars       = 3000;   // History depth to scan
input color  InpSLColor       = clrRed;         // SL line color
input color  InpEntryColor    = clrDodgerBlue;  // Entry line color

//--- === Alerts ===
input bool   InpAlerts        = true;   // Pop-up alert on a new signal
input bool   InpPushAlerts    = false;  // Push notification on a new signal

double BufEMA[];
double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "HARSI_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos = 0;
double gEntry = 0.0, gSL = 0.0, gSL0 = 0.0;
double gExtPrice = 0.0;

// sliding window (bot window = haRsiLength + 375 bars)
int gWin = 390;
double wOpen[], wHigh[], wLow[], wClose[];
double wRsiExit[], wHClose[], wHOpen[], wEMA[], wCE[];

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
//| Wilder RSI over a chronological array (pandas/ta compatible:     |
//| rma of gains/losses, ewm alpha=1/n, adjust=False)                |
//+------------------------------------------------------------------+
void RsiArray(const double &src[], const int n, double &dst[])
  {
   int m = ArraySize(src);
   ArrayResize(dst, m);
   for(int j = 0; j < m; j++)
      dst[j] = EMPTY_VALUE;
   int started = -1;
   double avgUp = 0.0, avgDn = 0.0;
   for(int j = 1; j < m; j++)
     {
      double ch = src[j] - src[j - 1];
      double up = (ch > 0.0) ? ch : 0.0;
      double dn = (ch < 0.0) ? -ch : 0.0;
      if(started < 0)
        {
         avgUp = up;
         avgDn = dn;
         started = j;
        }
      else
        {
         avgUp += (up - avgUp) / n;
         avgDn += (dn - avgDn) / n;
        }
      if(avgUp + avgDn > 0.0)
         dst[j] = 100.0 * avgUp / (avgUp + avgDn);
      else
         dst[j] = 50.0;
     }
  }

//+------------------------------------------------------------------+
//| Compute the window series for the window ending at shift sEnd    |
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

   //--- exit RSI (length 7) on close
   RsiArray(wClose, InpRSILength, wRsiExit);

   //--- HA-RSI: RSI(15) of open/high/low/close, Heikin Ashi on top
   double rsiC[], rsiO[], rsiH[], rsiL[];
   RsiArray(wClose, InpHARSILength, rsiC);
   RsiArray(wOpen,  InpHARSILength, rsiO);
   RsiArray(wHigh,  InpHARSILength, rsiH);
   RsiArray(wLow,   InpHARSILength, rsiL);

   ArrayResize(wHClose, gWin);
   ArrayResize(wHOpen, gWin);
   double highRsi, lowRsi;
   for(int j = 0; j < gWin; j++)
     {
      highRsi = MathMax(rsiH[j] == EMPTY_VALUE ? 50.0 : rsiH[j],
                        rsiL[j] == EMPTY_VALUE ? 50.0 : rsiL[j]);
      lowRsi  = MathMin(rsiH[j] == EMPTY_VALUE ? 50.0 : rsiH[j],
                        rsiL[j] == EMPTY_VALUE ? 50.0 : rsiL[j]);
      double c = rsiC[j] == EMPTY_VALUE ? 50.0 : rsiC[j];
      double o = rsiO[j] == EMPTY_VALUE ? 50.0 : rsiO[j];
      wHClose[j] = (c + o + highRsi + lowRsi) / 4.0;
     }
   // hopen seeded with openRsi at the window start, like the bot
   double o0 = rsiO[0] == EMPTY_VALUE ? 50.0 : rsiO[0];
   wHOpen[0] = o0;
   for(int j = 1; j < gWin; j++)
      wHOpen[j] = (wHOpen[j - 1] + wHClose[j - 1]) / 2.0;

   //--- Chandelier Exit state (atr = rolling mean of range, period 4)
   int p = InpATRPeriod;
   ArrayResize(wCE, gWin);
   int state = 0;
   for(int j = 0; j < gWin; j++)
     {
      double ceLong = EMPTY_VALUE, ceShort = EMPTY_VALUE;
      if(j >= p - 1)
        {
         double sumR = 0.0, mx = -DBL_MAX, mn = DBL_MAX;
         for(int i = j - p + 1; i <= j; i++)
           {
            sumR += wHigh[i] - wLow[i];
            if(wHigh[i] > mx) mx = wHigh[i];
            if(wLow[i]  < mn) mn = wLow[i];
           }
         double atr = sumR / p;
         ceLong  = mx - atr * InpATRMultiplier;
         ceShort = mn + atr * InpATRMultiplier;
        }
      if(ceLong != EMPTY_VALUE && j > 0)
        {
         double ceLongP = EMPTY_VALUE, ceShortP = EMPTY_VALUE;
         if(j - 1 >= p - 1)
           {
            double sumR = 0.0, mx = -DBL_MAX, mn = DBL_MAX;
            for(int i = j - p; i <= j - 1; i++)
              {
               sumR += wHigh[i] - wLow[i];
               if(wHigh[i] > mx) mx = wHigh[i];
               if(wLow[i]  < mn) mn = wLow[i];
              }
            double atrP = sumR / p;
            ceLongP  = mx - atrP * InpATRMultiplier;
            ceShortP = mn + atrP * InpATRMultiplier;
           }
         if(ceShortP != EMPTY_VALUE)
           {
            if(wClose[j] > ceShort && wClose[j - 1] <= ceShortP)
               state = 1;                 // cross above the short line
            else if(wClose[j] < ceLong && wClose[j - 1] >= ceLongP)
               state = -1;                // cross below the long line
           }
        }
      wCE[j] = state;                     // np.where + ffill + fillna(0)
     }

   //--- EMA200 with min_periods gating (valid from row 199)
   ArrayResize(wEMA, gWin);
   double k = 2.0 / (InpEMALength + 1.0);
   double e = wClose[0];
   for(int j = 0; j < gWin; j++)
     {
      if(j > 0)
         e = e + k * (wClose[j] - e);
      wEMA[j] = (j >= InpEMALength - 1) ? e : EMPTY_VALUE;
     }

   return true;
  }

//+------------------------------------------------------------------+
void DrawEntry(const bool isBuy, const int s, const double entry, const double sl,
               const datetime &time[], const double &high[], const double &low[])
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
                   "Scalper " + dirTxt + " entry");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "Scalper SL");

   if(InpShowLabels)
     {
      string txt = StringFormat("HA_RSI %s  E:%s SL:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits));
      CreateLabel(id + "_TXT", t, sl, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("HA_RSI Scalper %s on %s %s | entry %s SL %s",
                                dirTxt, _Symbol, EnumToString(_Period),
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits));
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
      Alert(StringFormat("HA_RSI Scalper EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
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
   int cur = gWin - 1;      // iloc[-2]
   int prv = gWin - 2;      // iloc[-3]

   if(wEMA[cur] == EMPTY_VALUE || wEMA[prv] == EMPTY_VALUE ||
      wRsiExit[cur] == EMPTY_VALUE)
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
      if(gPos > 0 && wRsiExit[cur] > InpUpper)
        {
         DrawExit(true, s, "RSI overbought", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && wRsiExit[cur] < InpLower)
        {
         DrawExit(false, s, "RSI oversold", time, high, low);
         gPos = 0;
         return;
        }
      return;   // position still open - no new signals
     }

   //--- entry signals
   bool buy  = (wHClose[prv] < InpLower) &&
               (wHClose[prv] < wHOpen[prv]) &&
               (wHClose[cur] > wHOpen[cur]) &&
               (wClose[cur] > wEMA[cur]) &&
               (wCE[cur] == 1.0);

   bool sell = (wHClose[prv] > InpUpper) &&
               (wHClose[prv] > wHOpen[prv]) &&
               (wHClose[cur] < wHOpen[cur]) &&
               (wClose[cur] < wEMA[cur]) &&
               (wCE[cur] == -1.0);

   if(buy)
     {
      gEntry    = close[s];
      gSL0      = gEntry * (1.0 - InpPctSL / InpLeverage);
      gSL       = gSL0;
      gExtPrice = gEntry;
      gPos      = 1;
      DrawEntry(true, s, gEntry, gSL, time, high, low);
     }
   else if(sell)
     {
      gEntry    = close[s];
      gSL0      = gEntry * (1.0 + InpPctSL / InpLeverage);
      gSL       = gSL0;
      gExtPrice = gEntry;
      gPos      = -1;
      DrawEntry(false, s, gEntry, gSL, time, high, low);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   gPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0)
      return INIT_FAILED;
   gWin = InpHARSILength + 375;      // exactly like the bot (number_of_data)

   SetIndexBuffer(0, BufEMA, INDICATOR_DATA);
   SetIndexBuffer(1, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(2, BufSell, INDICATOR_DATA);
   SetIndexBuffer(3, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(4, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufEMA, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufExitBuy, true);
   ArraySetAsSeries(BufExitSell, true);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);
   PlotIndexSetInteger(2, PLOT_ARROW, 234);
   PlotIndexSetInteger(3, PLOT_ARROW, 251);
   PlotIndexSetInteger(4, PLOT_ARROW, 251);
   for(int i = 0; i < 5; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowEMA ? DRAW_LINE : DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("HA_RSI Scalper (%d/%d)", InpHARSILength, InpRSILength));
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
      ArrayInitialize(BufEMA, EMPTY_VALUE);
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
            if(wEMA[cur] != EMPTY_VALUE)
               BufEMA[s] = wEMA[cur];
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
            if(wEMA[cur] != EMPTY_VALUE)
               BufEMA[i] = wEMA[cur];
           }
        }
      for(int s = newBars; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
