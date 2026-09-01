//+------------------------------------------------------------------+
//|                                     MichaelHarris_Indicator.mq5 |
//|   Michael Harris candle pattern - port of                        |
//|   run_michael_harris_backtest.py (strategy by Alireza Sadabadi)  |
//|                                                                  |
//|  Logic (H4 in the author's backtest, CARDANO default):           |
//|    BUY  (7 conditions, no overlaps between the last 4 candles):  |
//|      high > high[1] > low, low > high[2], high[2] > low[1],      |
//|      low[1] > high[3], high[3] > low[2], low[2] > low[3]         |
//|    SELL: exact mirror.                                           |
//|    SL = entry*(1 -/+ 2%), TP = entry*(1 +/- 9%) (backtest        |
//|    defaults: slPct=0.02, tpPct=0.09 with leverage=1).            |
//|    One position at a time; exits only via SL/TP (no trailing).   |
//|                                                                  |
//|  Note: the Python backtest fills orders at the NEXT bar open;    |
//|  this indicator marks the signal candle and computes SL/TP from  |
//|  its close (exactly what RiskReward receives in the backtest).   |
//|                                                                  |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "Michael Harris pattern strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "Michael Harris candle-pattern signals (run_michael_harris_backtest.py port) with SL/TP"
#property indicator_chart_window
#property indicator_buffers 4
#property indicator_plots   4

#property indicator_label1  "MH BUY"
#property indicator_type1   DRAW_ARROW
#property indicator_color1  clrLime
#property indicator_width1  2
#property indicator_label2  "MH SELL"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrRed
#property indicator_width2  2
#property indicator_label3  "Exit long"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrSilver
#property indicator_width3  1
#property indicator_label4  "Exit short"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrSilver
#property indicator_width4  1

//--- === Strategy (backtest defaults) ===
input double InpSlPct      = 2.0;     // SL percent (slPct = 0.02 with leverage 1)
input double InpTpPct      = 9.0;     // TP percent (tpPct = 0.09 with leverage 1)

//--- === Display ===
input int    InpExtendBars = 20;      // How many bars the SL/TP lines extend
input bool   InpShowLabels = true;    // Show text labels
input int    InpMaxBars    = 3000;    // History depth to scan
input color  InpSLColor    = clrRed;         // SL line color
input color  InpTPColor    = clrGreen;       // TP line color
input color  InpEntryColor = clrDodgerBlue;  // Entry line color

//--- === Alerts ===
input bool   InpAlerts     = true;    // Pop-up alert on a new signal
input bool   InpPushAlerts = false;   // Push notification on a new signal

double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "MHarris_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos = 0;
double gEntry = 0.0, gSL = 0.0, gTP = 0.0;

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
                   "MichaelHarris " + dirTxt + " entry (signal close)");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "MichaelHarris SL");
   CreateLevelLine(id + "_TP", t, tp, InpTPColor, STYLE_SOLID, 2, "MichaelHarris TP");

   if(InpShowLabels)
     {
      string txt = StringFormat("MH %s  E:%s SL:%s TP:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits));
      CreateLabel(id + "_TXT", t, tp, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("MichaelHarris %s on %s %s | entry %s SL %s TP %s",
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
      Alert(StringFormat("MichaelHarris EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
                         _Symbol, EnumToString(_Period), reason));
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
  {
   // current row = s, lags 1..3 = s+1..s+3
   double h0 = high[s],     l0 = low[s];
   double h1 = high[s + 1], l1 = low[s + 1];
   double h2 = high[s + 2], l2 = low[s + 2];
   double h3 = high[s + 3], l3 = low[s + 3];

   bool buy  = (h0 > h1) && (h1 > l0) && (l0 > h2) && (h2 > l1) &&
               (l1 > h3) && (h3 > l2) && (l2 > l3);
   bool sell = (l0 < l1) && (l1 < h0) && (h0 < l2) && (l2 < h1) &&
               (h1 < l3) && (l3 < h2) && (h2 < h3);

   //--- manage the open virtual position (SL/TP exits only)
   if(gPos != 0)
     {
      if(gPos > 0 && low[s] <= gSL)
        {
         DrawExit(true, s, "SL", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && high[s] >= gSL)
        {
         DrawExit(false, s, "SL", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos > 0 && high[s] >= gTP)
        {
         DrawExit(true, s, "TP", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && low[s] <= gTP)
        {
         DrawExit(false, s, "TP", time, high, low);
         gPos = 0;
         return;
        }
      return;   // one position at a time (len(self.trades) == 0)
     }

   if(buy)
     {
      gEntry = close[s];
      gSL    = gEntry * (1.0 - InpSlPct / 100.0);
      gTP    = gEntry * (1.0 + InpTpPct / 100.0);
      gPos   = 1;
      DrawEntry(true, s, gEntry, gSL, gTP, time, high, low);
     }
   else if(sell)
     {
      gEntry = close[s];
      gSL    = gEntry * (1.0 + InpSlPct / 100.0);
      gTP    = gEntry * (1.0 - InpTpPct / 100.0);
      gPos   = -1;
      DrawEntry(false, s, gEntry, gSL, gTP, time, high, low);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   gPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0)
      return INIT_FAILED;

   SetIndexBuffer(0, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(1, BufSell, INDICATOR_DATA);
   SetIndexBuffer(2, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(3, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufExitBuy, true);
   ArraySetAsSeries(BufExitSell, true);

   PlotIndexSetInteger(0, PLOT_ARROW, 233);
   PlotIndexSetInteger(1, PLOT_ARROW, 234);
   PlotIndexSetInteger(2, PLOT_ARROW, 251);
   PlotIndexSetInteger(3, PLOT_ARROW, 251);
   for(int i = 0; i < 4; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("MichaelHarris (SL %.1f%%, TP %.1f%%)", InpSlPct, InpTpPct));
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
   if(rates_total < 10)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufExitBuy, EMPTY_VALUE);
      ArrayInitialize(BufExitSell, EMPTY_VALUE);
      gPos = 0;
      ObjectsDeleteAll(0, gPrefix);

      int maxShift = MathMin(InpMaxBars, rates_total - 5);
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
      for(int s = newBars; s >= 1; s--)
        {
         if(s <= rates_total - 5)
            ProcessBar(s, time, open, high, low, close);
        }
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
