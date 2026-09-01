//+------------------------------------------------------------------+
//|                                          BB_Full_Indicator.mq5 |
//|      Bollinger full-band strategy - port of BB_Full.py /         |
//|      TraderBot BB_Full (strategy by Alireza Sadabadi)            |
//|                                                                  |
//|  BB_Full logic (H4 in the author's setup, BITCOIN):              |
//|    Middle = SMA(close, 22), bands = Middle +/- 2 * sample std    |
//|    BUY : previous candle closed below the Lower band (bearish),  |
//|          signal candle re-enters the band (bullish), opened      |
//|          below the band, still under the Middle band, plus the   |
//|          hardcoded body/gap size filters (BTC-calibrated).       |
//|    SELL: mirror around the Upper band.                           |
//|    Exit: close beyond the opposite band.                         |
//|    SL   = entry * (1 -/+ PctSL/Leverage)   (Meta.RiskReward)     |
//|    No TP for this bot (magic 1); trailing stop is used live.     |
//|                                                                  |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "BB_Full strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "Bollinger full-band signals (BB_Full.py port) with SL level and band-cross exits"
#property indicator_chart_window
#property indicator_buffers 7
#property indicator_plots   7

#property indicator_label1  "BB Upper"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDimGray
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
#property indicator_label2  "BB Middle"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrDarkGray
#property indicator_width2  1
#property indicator_label3  "BB Lower"
#property indicator_type3   DRAW_LINE
#property indicator_color3  clrDimGray
#property indicator_style3  STYLE_DOT
#property indicator_width3  1
#property indicator_label4  "BB_Full BUY"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrLime
#property indicator_width4  2
#property indicator_label5  "BB_Full SELL"
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

//--- === Strategy (BB_Full.py defaults) ===
input int    InpBBLength     = 22;     // Bollinger length (movingAverage)
input double InpBBCoef       = 2.0;    // Bollinger coefficient (coef)
input double InpOpenGap      = 100.0;  // Extra gap below/above the band for the open (BTC: 100)
input double InpBodyMin      = 600.0;  // Min signal candle body (BTC: 600)
input double InpPrevBodyMin  = 1100.0; // Min previous candle body (BTC: 1100)
input double InpLeverage     = 100;    // Account leverage (RiskReward SL formula)
input double InpPctTP        = 1.3;    // TP percent (not set live - reference only)
input double InpPctSL        = 0.65;   // SL percent (pct_sl in Meta.run)
input bool   InpUseTrailing  = true;   // Emulate the bot's trailing stop

//--- === Display ===
input bool   InpShowBands    = true;   // Show Bollinger bands
input int    InpExtendBars   = 20;     // How many bars the SL/entry lines extend
input bool   InpShowLabels   = true;   // Show text labels
input int    InpMaxBars      = 3000;   // History depth to scan
input color  InpSLColor      = clrRed;         // SL line color
input color  InpEntryColor   = clrDodgerBlue;  // Entry line color
input color  InpTPColor      = clrGreen;       // Reference TP line color

//--- === Alerts ===
input bool   InpAlerts       = true;   // Pop-up alert on a new signal
input bool   InpPushAlerts   = false;  // Push notification on a new signal

double BufUp[];
double BufMid[];
double BufLow[];
double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "BBFull_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos = 0;
double gEntry = 0.0, gSL = 0.0, gSL0 = 0.0, gTP = 0.0;
double gExtPrice = 0.0;    // max (long) / min (short) since entry, for trailing

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
//| Bollinger values at shift s (SMA + SAMPLE std, like pandas)      |
//+------------------------------------------------------------------+
bool BBAt(const int s, const int n, const double &close[],
          double &mid, double &lower, double &upper)
  {
   if(s + n - 1 >= ArraySize(close))
      return false;
   double sum = 0.0;
   for(int i = s; i < s + n; i++)
      sum += close[i];
   mid = sum / n;
   double ss = 0.0;
   for(int i = s; i < s + n; i++)
      ss += (close[i] - mid) * (close[i] - mid);
   double sd = MathSqrt(ss / (n - 1));      // sample std (pandas ddof=1)
   lower = mid - InpBBCoef * sd;
   upper = mid + InpBBCoef * sd;
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
                   "BB_Full " + dirTxt + " entry");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "BB_Full SL");
   // reference TP (this bot has no live TP - exits are band cross / SL)
   double tpRef = isBuy ? entry * (1.0 + InpPctTP / InpLeverage)
                        : entry * (1.0 - InpPctTP / InpLeverage);
   CreateLevelLine(id + "_TPREF", t, tpRef, InpTPColor, STYLE_DOT, 1,
                   "BB_Full reference TP (not set live)");

   if(InpShowLabels)
     {
      string txt = StringFormat("BB_Full %s  E:%s SL:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits));
      CreateLabel(id + "_TXT", t, sl, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("BB_Full %s on %s %s | entry %s SL %s",
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
      Alert(StringFormat("BB_Full EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
                         _Symbol, EnumToString(_Period), reason));
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
  {
   double mid, lower, upper;
   if(!BBAt(s, InpBBLength, close, mid, lower, upper))
      return;
   double midP, lowerP, upperP;                    // previous candle (iloc[-3])
   if(!BBAt(s + 1, InpBBLength, close, midP, lowerP, upperP))
      return;

   //--- manage the open virtual position
   if(gPos != 0)
     {
      // trailing stop level (Meta.TrailingStopLoss: SL0 + distance travelled
      // by the extreme price since entry, never moving against the trade)
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
      // SL hit?
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
      // band-cross exit (evaluated on the closed candle, like the bot)
      if(gPos > 0 && close[s] > upper)
        {
         DrawExit(true, s, "upper band", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && close[s] < lower)
        {
         DrawExit(false, s, "lower band", time, high, low);
         gPos = 0;
         return;
        }
      return;   // position still open - no new signals (status flag)
     }

   //--- entry signals (status == False)
   double body      = MathAbs(close[s] - open[s]);
   double bodyPrev  = MathAbs(open[s + 1] - close[s + 1]);

   bool buy = (close[s + 1] < lowerP) &&
              (close[s + 1] < open[s + 1]) &&
              (close[s] > lower) &&
              (close[s] > open[s]) &&
              (open[s] < lower) &&
              (close[s] < mid) &&
              (open[s] < lower - InpOpenGap) &&
              (body > InpBodyMin) &&
              (bodyPrev > InpPrevBodyMin);

   bool sell = (close[s + 1] > upperP) &&
               (close[s + 1] > open[s + 1]) &&
               (close[s] < upper) &&
               (close[s] < open[s]) &&
               (open[s] > upper) &&
               (close[s] > mid) &&
               (open[s] > upper + InpOpenGap) &&
               (body > InpBodyMin) &&
               (bodyPrev > InpPrevBodyMin);

   if(buy)
     {
      gEntry    = close[s];
      gSL       = gEntry * (1.0 - InpPctSL / InpLeverage);
      gSL0      = gSL;
      gTP       = 0.0;
      gExtPrice = gEntry;
      gPos      = 1;
      DrawEntry(true, s, gEntry, gSL, time, high, low);
     }
   else if(sell)
     {
      gEntry    = close[s];
      gSL       = gEntry * (1.0 + InpPctSL / InpLeverage);
      gSL0      = gSL;
      gTP       = 0.0;
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

   SetIndexBuffer(0, BufUp, INDICATOR_DATA);
   SetIndexBuffer(1, BufMid, INDICATOR_DATA);
   SetIndexBuffer(2, BufLow, INDICATOR_DATA);
   SetIndexBuffer(3, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(4, BufSell, INDICATOR_DATA);
   SetIndexBuffer(5, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(6, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufUp, true);
   ArraySetAsSeries(BufMid, true);
   ArraySetAsSeries(BufLow, true);
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
   int dt = InpShowBands ? DRAW_LINE : DRAW_NONE;
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, dt);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, dt);
   PlotIndexSetInteger(2, PLOT_DRAW_TYPE, dt);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("BB_Full (%d, %.1f)", InpBBLength, InpBBCoef));
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
   if(rates_total < InpBBLength + 10)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufUp, EMPTY_VALUE);
      ArrayInitialize(BufMid, EMPTY_VALUE);
      ArrayInitialize(BufLow, EMPTY_VALUE);
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufExitBuy, EMPTY_VALUE);
      ArrayInitialize(BufExitSell, EMPTY_VALUE);
      gPos = 0;
      ObjectsDeleteAll(0, gPrefix);

      int maxShift = MathMin(InpMaxBars, rates_total - InpBBLength - 3);
      double mid, lo, up;
      for(int s = maxShift; s >= 0; s--)
        {
         if(BBAt(s, InpBBLength, close, mid, lo, up))
           {
            BufUp[s]  = up;
            BufMid[s] = mid;
            BufLow[s] = lo;
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
      double mid, lo, up;
      for(int i = newBars; i >= 0; i--)
        {
         if(BBAt(i, InpBBLength, close, mid, lo, up))
           {
            BufUp[i]  = up;
            BufMid[i] = mid;
            BufLow[i] = lo;
           }
        }
      for(int s = newBars; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
