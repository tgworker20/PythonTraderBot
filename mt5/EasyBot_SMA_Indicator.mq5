//+------------------------------------------------------------------+
//|                                        EasyBot_SMA_Indicator.mq5 |
//|        SMA fast/slow cross indicator - port of EasyBot.py        |
//|              (PythonTraderBot - strategy by Alireza Sadabadi)    |
//|                                                                  |
//|  EasyBot logic (M1 in the author's setup):                       |
//|    - BUY  when SMA(fast) crosses ABOVE  SMA(slow)                |
//|    - SELL when SMA(fast) crosses BELOW  SMA(slow)                |
//|    - SL  = entry * (1 -/+ PctSL/Leverage)   (Meta.RiskReward)    |
//|    - no TP is set by this bot; exits are the SL or the opposite  |
//|      cross. No trailing stop (EasyBot never calls it).           |
//|                                                                  |
//|  Chart indicator only - it does NOT trade.                       |
//+------------------------------------------------------------------+
#property copyright   "EasyBot strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.00"
#property description "SMA fast/slow cross signals (EasyBot.py port) with the bot's SL level"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots   6

#property indicator_label1  "SMA fast"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrDeepSkyBlue
#property indicator_width1  1
#property indicator_label2  "SMA slow"
#property indicator_type2   DRAW_LINE
#property indicator_color2  clrOrange
#property indicator_width2  1
#property indicator_label3  "EasyBot BUY"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrLime
#property indicator_width3  2
#property indicator_label4  "EasyBot SELL"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrRed
#property indicator_width4  2
#property indicator_label5  "Exit long"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrSilver
#property indicator_width5  1
#property indicator_label6  "Exit short"
#property indicator_type6   DRAW_ARROW
#property indicator_color6  clrSilver
#property indicator_width6  1

//--- === Strategy (EasyBot.py defaults) ===
input int    InpFastLength   = 20;     // SMA fast length
input int    InpSlowLength   = 200;    // SMA slow length
input double InpLeverage     = 100;    // Account leverage (for the RiskReward SL formula)
input double InpPctSL        = 0.06;   // SL percent (pct_sl in Meta.run)

//--- === Display ===
input bool   InpShowLines    = true;   // Show SMA lines
input int    InpExtendBars   = 20;     // How many bars the SL line extends
input bool   InpShowLabels   = true;   // Show text labels
input int    InpMaxBars      = 3000;   // History depth to scan
input color  InpSLColor      = clrRed;         // SL line color
input color  InpEntryColor   = clrDodgerBlue;  // Entry line color

//--- === Alerts ===
input bool   InpAlerts       = true;   // Pop-up alert on a new signal
input bool   InpPushAlerts   = false;  // Push notification on a new signal

double BufFast[];
double BufSlow[];
double BufBuy[];
double BufSell[];
double BufExitBuy[];
double BufExitSell[];

string gPrefix = "EasyBot_";
double gPoint  = 0.0;
int    gPrevCalculated = 0;

// virtual position state
int    gPos   = 0;      // 0 none, +1 long, -1 short
double gEntry = 0.0;
double gSL    = 0.0;

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
//| SMA of close over n bars ending at shift s                       |
//+------------------------------------------------------------------+
double SmaAt(const int s, const int n, const double &close[])
  {
   if(s + n - 1 >= ArraySize(close))
      return EMPTY_VALUE;
   double sum = 0.0;
   for(int i = s; i < s + n; i++)
      sum += close[i];
   return sum / n;
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
                   "EasyBot " + dirTxt + " entry (close of signal candle)");
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2, "EasyBot SL");

   if(InpShowLabels)
     {
      string txt = StringFormat("EasyBot %s  E:%s SL:%s", dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits));
      CreateLabel(id + "_TXT", t, isBuy ? sl : sl, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }

   if(s == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("EasyBot %s on %s %s | entry %s SL %s (no TP in this strategy)",
                                dirTxt, _Symbol, EnumToString(_Period),
                                DoubleToString(entry, _Digits), DoubleToString(sl, _Digits));
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
     {
      string txt = StringFormat("EXIT (%s)", reason);
      CreateLabel(id + "_TXT", t, wasLong ? high[s] : low[s], txt, clrSilver,
                  wasLong ? ANCHOR_LEFT_UPPER : ANCHOR_LEFT_LOWER);
     }

   if(s == 1 && gPrevCalculated > 0 && InpAlerts)
      Alert(StringFormat("EasyBot EXIT %s on %s %s (%s)", wasLong ? "long" : "short",
                         _Symbol, EnumToString(_Period), reason));
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
  {
   double fast = SmaAt(s, InpFastLength, close);
   double slow = SmaAt(s, InpSlowLength, close);
   double fastPrev = SmaAt(s + 1, InpFastLength, close);
   double slowPrev = SmaAt(s + 1, InpSlowLength, close);
   if(fast == EMPTY_VALUE || slow == EMPTY_VALUE ||
      fastPrev == EMPTY_VALUE || slowPrev == EMPTY_VALUE)
      return;

   bool buyCross  = (fast > slow) && (fastPrev < slowPrev);
   bool sellCross = (fast < slow) && (fastPrev > slowPrev);

   //--- manage the open virtual position
   if(gPos != 0)
     {
      // SL hit?
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
      // opposite cross closes the position
      if(gPos > 0 && sellCross)
        {
         DrawExit(true, s, "opposite cross", time, high, low);
         gPos = 0;
         return;
        }
      if(gPos < 0 && buyCross)
        {
         DrawExit(false, s, "opposite cross", time, high, low);
         gPos = 0;
         return;
        }
      return;   // still in the trade - no new entries (EasyBot keeps one position)
     }

   //--- new entry
   if(buyCross)
     {
      gEntry = close[s];
      gSL    = gEntry * (1.0 - InpPctSL / InpLeverage);
      gPos   = 1;
      DrawEntry(true, s, gEntry, gSL, time, high, low);
     }
   else if(sellCross)
     {
      gEntry = close[s];
      gSL    = gEntry * (1.0 + InpPctSL / InpLeverage);
      gPos   = -1;
      DrawEntry(false, s, gEntry, gSL, time, high, low);
     }
  }

//+------------------------------------------------------------------+
int OnInit()
  {
   gPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0)
      return INIT_FAILED;

   SetIndexBuffer(0, BufFast, INDICATOR_DATA);
   SetIndexBuffer(1, BufSlow, INDICATOR_DATA);
   SetIndexBuffer(2, BufBuy, INDICATOR_DATA);
   SetIndexBuffer(3, BufSell, INDICATOR_DATA);
   SetIndexBuffer(4, BufExitBuy, INDICATOR_DATA);
   SetIndexBuffer(5, BufExitSell, INDICATOR_DATA);
   ArraySetAsSeries(BufFast, true);
   ArraySetAsSeries(BufSlow, true);
   ArraySetAsSeries(BufBuy, true);
   ArraySetAsSeries(BufSell, true);
   ArraySetAsSeries(BufExitBuy, true);
   ArraySetAsSeries(BufExitSell, true);

   PlotIndexSetInteger(2, PLOT_ARROW, 233);
   PlotIndexSetInteger(3, PLOT_ARROW, 234);
   PlotIndexSetInteger(4, PLOT_ARROW, 251);   // x marker
   PlotIndexSetInteger(5, PLOT_ARROW, 251);
   for(int i = 0; i < 6; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);
   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowLines ? DRAW_LINE : DRAW_NONE);
   PlotIndexSetInteger(1, PLOT_DRAW_TYPE, InpShowLines ? DRAW_LINE : DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("EasyBot SMA (%d/%d)", InpFastLength, InpSlowLength));
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
   if(rates_total < InpSlowLength + 5)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufFast, EMPTY_VALUE);
      ArrayInitialize(BufSlow, EMPTY_VALUE);
      ArrayInitialize(BufBuy, EMPTY_VALUE);
      ArrayInitialize(BufSell, EMPTY_VALUE);
      ArrayInitialize(BufExitBuy, EMPTY_VALUE);
      ArrayInitialize(BufExitSell, EMPTY_VALUE);
      gPos = 0;
      ObjectsDeleteAll(0, gPrefix);

      int maxShift = MathMin(InpMaxBars, rates_total - InpSlowLength - 2);
      // lines
      for(int s = maxShift; s >= 0; s--)
        {
         BufFast[s] = SmaAt(s, InpFastLength, close);
         BufSlow[s] = SmaAt(s, InpSlowLength, close);
        }
      // signals (oldest first)
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
         BufFast[i] = SmaAt(i, InpFastLength, close);
         BufSlow[i] = SmaAt(i, InpSlowLength, close);
        }
      for(int s = newBars; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }

   ChartRedraw();
   return rates_total;
  }
//+------------------------------------------------------------------+
