//+------------------------------------------------------------------+
//|                                      VWAP_BB_RSI_Indicator.mq5 |
//|   VWAP + Bollinger + RSI scalper - port of VWAP_BB_RSI.py        |
//|   (TraderBot magic 5, by Alireza Sadabadi)                      |
//|                                                                  |
//|  Logic (M5 in the author's setup, altcoins):                     |
//|    - VWAP: typical price (H+L+C)/3 volume-weighted, cumulative,  |
//|      reset at each new day - computed over the bot's 50-bar      |
//|      window (the bot refetches 50 bars each evaluation).         |
//|    - trend: bodies fully below VWAP for the last 26 candles ->   |
//|      bullish reversion setup; fully above -> bearish.            |
//|    - BUY : trend below VWAP + close <= lower Bollinger band      |
//|            (15, 2.0 sample std) + RSI(16) < 46                   |
//|    - SELL: mirror (close >= upper band + RSI > 59)               |
//|    - Exit: RSI >= 90 (long) / <= 10 (short)                      |
//|    - SL = 1.2 * ATR(7), TP = 1.89 * SL (real price distances,    |
//|      stopLossWithAtr = True); trailing stop used live.           |
//|                                                                  |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "VWAP_BB_RSI strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "VWAP + Bollinger + RSI scalper signals (VWAP_BB_RSI.py port) with ATR SL/TP"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

#property indicator_label1  "VWAP"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrGold
#property indicator_width1  2
#property indicator_label2  "BB Upper"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDimGray
#property indicator_style2  STYLE_DOT
#property indicator_width2  1
#property indicator_label3  "BB Lower"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDimGray
#property indicator_style3  STYLE_DOT
#property indicator_width3  1
#property indicator_label4  "VWAP_BB BUY"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2
#property indicator_label5  "VWAP_BB SELL"
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

//--- === Strategy (VWAP_BB_RSI.py defaults) ===
input int    InpRSILength    = 16;     // RSI length
input int    InpBBLength     = 15;     // Bollinger length
input double InpBBStd        = 2.0;    // Bollinger std coefficient
input int    InpBackCandles  = 26;     // VWAP trend lookback candles
input double InpBuyRSIMax    = 46.0;   // BUY: RSI below this
input double InpSellRSIMin   = 59.0;   // SELL: RSI above this
input double InpExitRSIHigh  = 90.0;   // Exit long when RSI >= this
input double InpExitRSILow   = 10.0;   // Exit short when RSI <= this
input int    InpATRLength    = 7;      // ATR length (Wilder)
input double InpATRSLFactor  = 1.2;    // SL = factor * ATR
input double InpTPFactor     = 1.89;   // TP = factor * SL
input bool   InpUseTrailing  = true;   // Emulate the bot's trailing stop

//--- === Display ===
input bool   InpShowLines    = true;   // Show VWAP / Bollinger lines
input int    InpExtendBars   = 20;     // How many bars the SL/TP lines extend
input bool   InpShowLabels   = true;   // Show text labels
input int    InpMaxBars      = 3000;   // History depth to scan
input color  InpSLColor      = clrRed;         // SL line color
input color  InpTPColor      = clrGreen;       // TP line color
input color  InpEntryColor   = clrDodgerBlue;  // Entry line color

//--- === Alerts ===
input bool   InpAlerts       = true;   // Pop-up alert on a new signal
input bool   InpPushAlerts   = false;  // Push notification on a new signal

double BufVWAP[];
double BufUp[];
double BufLowB[];
double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "VWAPBB_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos = 0;
double gEntry = 0.0, gSL = 0.0, gSL0 = 0.0, gTP = 0.0;
double gExtPrice = 0.0;

// sliding window (bot window = 50 bars)
int gWin = 50;
double wOpen[], wHigh[], wLow[], wClose[], wVol[];
datetime wTime[];
double wRSI[], wVWAP[], wBBU[], wBBL[], wATR[];

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
//| Wilder RSI over a chronological array (rma of gains/losses)      |
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
                   const double &high[], const double &low[], const double &close[],
                   const long &vol[])
  {
   if(sEnd + gWin - 1 >= ArraySize(close))
      return false;

   ArrayResize(wOpen, gWin);
   ArrayResize(wHigh, gWin);
   ArrayResize(wLow, gWin);
   ArrayResize(wClose, gWin);
   ArrayResize(wVol, gWin);
   ArrayResize(wTime, gWin);
   for(int j = 0; j < gWin; j++)
     {
      int sh = sEnd + (gWin - 1) - j;
      wOpen[j]  = open[sh];
      wHigh[j]  = high[sh];
      wLow[j]   = low[sh];
      wClose[j] = close[sh];
      wVol[j]   = (double)vol[sh];
      wTime[j]  = time[sh];
     }

   //--- RSI(16) over the window (seeded at the window start, like the bot)
   RsiArray(wClose, InpRSILength, wRSI);

   //--- VWAP: cumulative (typical*vol)/vol, reset at each new day
   ArrayResize(wVWAP, gWin);
   double cumPV = 0.0, cumV = 0.0;
   int curDay = -1;
   for(int j = 0; j < gWin; j++)
     {
      MqlDateTime st;
      TimeToStruct(wTime[j], st);
      int day = st.year * 10000 + st.mon * 100 + st.day;
      if(day != curDay)
        {
         cumPV = 0.0;
         cumV  = 0.0;
         curDay = day;
        }
      double tp = (wHigh[j] + wLow[j] + wClose[j]) / 3.0;
      cumPV += tp * wVol[j];
      cumV  += wVol[j];
      wVWAP[j] = (cumV > 0.0) ? cumPV / cumV : wClose[j];
     }

   //--- Bollinger (SMA + sample std) over the window
   ArrayResize(wBBU, gWin);
   ArrayResize(wBBL, gWin);
   int n = InpBBLength;
   for(int j = 0; j < gWin; j++)
     {
      wBBU[j] = EMPTY_VALUE;
      wBBL[j] = EMPTY_VALUE;
      if(j < n - 1)
         continue;
      double sum = 0.0;
      for(int i = j - n + 1; i <= j; i++)
         sum += wClose[i];
      double mid = sum / n;
      double ss = 0.0;
      for(int i = j - n + 1; i <= j; i++)
         ss += (wClose[i] - mid) * (wClose[i] - mid);
      double sd = MathSqrt(ss / (n - 1));
      wBBU[j] = mid + InpBBStd * sd;
      wBBL[j] = mid - InpBBStd * sd;
     }

   //--- ATR(7) Wilder (rma of true range, first bar has no TR)
   double tr[];
   ArrayResize(tr, gWin);
   for(int j = 0; j < gWin; j++)
     {
      if(j == 0)
         tr[j] = EMPTY_VALUE;
      else
         tr[j] = MathMax(wHigh[j] - wLow[j],
                         MathMax(MathAbs(wHigh[j] - wClose[j - 1]),
                                 MathAbs(wClose[j - 1] - wLow[j])));
     }
   ArrayResize(wATR, gWin);
   for(int j = 0; j < gWin; j++)
      wATR[j] = EMPTY_VALUE;
   for(int j = 0; j < gWin; j++)
     {
      if(tr[j] == EMPTY_VALUE)
         continue;
      if(j == 0 || wATR[j - 1] == EMPTY_VALUE)
         wATR[j] = tr[j];
      else
         wATR[j] = wATR[j - 1] + (tr[j] - wATR[j - 1]) / InpATRLength;
     }

   return true;
  }

//+------------------------------------------------------------------+
//| VWAP trend state at row j (vwapsignal of the bot)                |
//| returns 1 (all bodies below VWAP), -1 (all above), 0 otherwise   |
//+------------------------------------------------------------------+
double VwapSignalAt(const int j)
  {
   int lookback = InpBackCandles + 1;
   if(j < lookback - 1)
      return 0.0;
   bool upAll = true, downAll = true;    // uptrend / downtrend rolling min == 1
   for(int i = j - lookback + 1; i <= j; i++)
     {
      double maxOC = MathMax(wOpen[i], wClose[i]);
      double minOC = MathMin(wOpen[i], wClose[i]);
      if(maxOC >= wVWAP[i])
         downAll = false;                // downtrend = 0
      if(minOC <= wVWAP[i])
         upAll = false;                  // uptrend = 0
     }
   if(upAll && downAll)
      return 3.0;
   if(!upAll && downAll)
      return 1.0;
   if(upAll && !downAll)
      return -1.0;
   return 0.0;
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
                   "VWAP_BB " + dirTxt + " entry");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "VWAP_BB SL (ATR)");
   CreateLevelLine(id + "_TP", t, tp, InpTPColor, STYLE_SOLID, 2, "VWAP_BB TP");

   if(InpShowLabels)
     {
      string txt = StringFormat("VWAP_BB %s  E:%s SL:%s TP:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits));
      CreateLabel(id + "_TXT", t, tp, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("VWAP_BB %s on %s %s | entry %s SL %s TP %s",
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
      Alert(StringFormat("VWAP_BB EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
                         _Symbol, EnumToString(_Period), reason));
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[],
                const long &vol[])
  {
   if(!ComputeWindow(s, time, open, high, low, close, vol))
      return;
   int cur = gWin - 1;      // iloc[-2]

   if(wRSI[cur] == EMPTY_VALUE || wBBL[cur] == EMPTY_VALUE || wATR[cur] == EMPTY_VALUE)
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
      if(gPos > 0 && wRSI[cur] >= InpExitRSIHigh)
        {
         DrawExit(true, s, "RSI extreme", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && wRSI[cur] <= InpExitRSILow)
        {
         DrawExit(false, s, "RSI extreme", time, high, low);
         gPos = 0;
         return;
        }
      return;   // position still open - no new signals
     }

   //--- entry signals
   double vwapSig = VwapSignalAt(cur);

   bool buy  = (vwapSig == 1.0) &&
               (wClose[cur] <= wBBL[cur]) &&
               (wRSI[cur] < InpBuyRSIMax);

   bool sell = (vwapSig == -1.0) &&
               (wClose[cur] >= wBBU[cur]) &&
               (wRSI[cur] > InpSellRSIMin);

   if(buy || sell)
     {
      gEntry    = close[s];
      gExtPrice = gEntry;
      double slDist = InpATRSLFactor * wATR[cur];
      if(slDist <= 0.0)
         return;
      gSL0 = buy ? (gEntry - slDist) : (gEntry + slDist);
      gSL  = gSL0;
      gTP  = buy ? (gEntry + InpTPFactor * slDist) : (gEntry - InpTPFactor * slDist);
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
   gWin = 50;      // exactly like the bot (number_of_data)

   SetIndexBuffer(0, BufVWAP, INDICATOR_DATA);
   SetIndexBuffer(1, BufUp, INDICATOR_DATA);
   SetIndexBuffer(2, BufLowB, INDICATOR_DATA);
   SetIndexBuffer(3, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(4, BufSell, INDICATOR_DATA);
   SetIndexBuffer(5, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(6, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufVWAP, true);
   ArraySetAsSeries(BufUp, true);
   ArraySetAsSeries(BufLowB, true);
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
                      StringFormat("VWAP_BB_RSI (%d,%d,%.1f)", InpBBLength, InpRSILength, InpBBStd));
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
   if(rates_total < gWin + InpBackCandles + 5)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);
   ArraySetAsSeries(tick_volume, true);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufVWAP, EMPTY_VALUE);
      ArrayInitialize(BufUp, EMPTY_VALUE);
      ArrayInitialize(BufLowB, EMPTY_VALUE);
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufExitBuy, EMPTY_VALUE);
      ArrayInitialize(BufExitSell, EMPTY_VALUE);
      gPos = 0;
      ObjectsDeleteAll(0, gPrefix);

      int maxShift = MathMin(InpMaxBars, rates_total - gWin - 1);
      for(int s = maxShift; s >= 0; s--)
        {
         if(ComputeWindow(s, time, open, high, low, close, tick_volume))
           {
            int cur = gWin - 1;
            BufVWAP[s] = wVWAP[cur];
            if(wBBU[cur] != EMPTY_VALUE)
               BufUp[s] = wBBU[cur];
            if(wBBL[cur] != EMPTY_VALUE)
               BufLowB[s] = wBBL[cur];
           }
        }
      for(int s = maxShift; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close, tick_volume);
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
         if(ComputeWindow(i, time, open, high, low, close, tick_volume))
           {
            int cur = gWin - 1;
            BufVWAP[i] = wVWAP[cur];
            if(wBBU[cur] != EMPTY_VALUE)
               BufUp[i] = wBBU[cur];
            if(wBBL[cur] != EMPTY_VALUE)
               BufLowB[i] = wBBL[cur];
           }
        }
      for(int s = newBars; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close, tick_volume);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
