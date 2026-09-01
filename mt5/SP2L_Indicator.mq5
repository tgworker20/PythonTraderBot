//+------------------------------------------------------------------+
//|                                               SP2L_Indicator.mq5 |
//|         SP2L (Spike + Pullback + Gap) indicator for MetaTrader 5 |
//|                                                                  |
//|  Faithful MQL5 port of the SP2L strategy by Alireza Sadabadi     |
//|  (PythonTraderBot repository - code/SP2L/):                      |
//|     - SP2L_Bot.py          (Simple trader)                       |
//|     - SP2L_Advanced_Bot.py (Advanced trader: EMA / trend / ADX / |
//|       session filters, max SL distance, TP_R, second entry)      |
//|  Author's tutorials: https://youtube.com/@alirezasadabadi        |
//|                                                                  |
//|  The indicator draws:                                            |
//|    - BUY / SELL arrows at the entry candle                       |
//|    - the SL level  (low/high of the candle BEFORE the spike)     |
//|    - the TP level  (entry +/- TP_R * risk)                       |
//|    - the entry level and the optional second-entry level         |
//|    - the EMA filter line                                         |
//|    - small diamonds marking the detected spike setups            |
//|                                                                  |
//|  Candle naming used below (same as the author's Python code):    |
//|    -1 = latest candle, -2 = candle after spike,                  |
//|    -3 = spike candle,    -4 = candle before spike                |
//|                                                                  |
//|  This file is a chart indicator only - it does NOT trade.        |
//+------------------------------------------------------------------+
#property copyright   "SP2L strategy by Alireza Sadabadi - MQL5 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.01"
#property description "SP2L (Spike + Pullback + Gap) signals with SL / TP levels - exact port of the author's Python strategy"
#property indicator_chart_window
#property indicator_buffers 5
#property indicator_plots   5

//--- plot 0 : EMA filter line
#property indicator_label1  "EMA filter"
#property indicator_type1   DRAW_LINE
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
//--- plot 1 : BUY entry arrow
#property indicator_label2  "SP2L BUY"
#property indicator_type2   DRAW_ARROW
#property indicator_color2  clrLime
#property indicator_width2  2
//--- plot 2 : SELL entry arrow
#property indicator_label3  "SP2L SELL"
#property indicator_type3   DRAW_ARROW
#property indicator_color3  clrRed
#property indicator_width3  2
//--- plot 3 : BUY setup marker (diamond on the spike candle)
#property indicator_label4  "SP2L BUY setup"
#property indicator_type4   DRAW_ARROW
#property indicator_color4  clrAqua
#property indicator_width4  1
//--- plot 4 : SELL setup marker (diamond on the spike candle)
#property indicator_label5  "SP2L SELL setup"
#property indicator_type5   DRAW_ARROW
#property indicator_color5  clrMagenta
#property indicator_width5  1

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
enum ENUM_SP2L_MODE
  {
   MODE_ADVANCED = 0,   // Advanced (pending setup + filters, like SP2L_Advanced_Bot)
   MODE_SIMPLE   = 1    // Simple (immediate entry, like SP2L_Bot)
  };

input group "=== Strategy ==="
input ENUM_SP2L_MODE InpMode               = MODE_ADVANCED; // Strategy mode
input double         InpSpikeCandleSize    = 0.0;     // Spike candle size (0 = auto: Simple 2.0 / Advanced 1.5, the author's defaults)
input double         InpPGapPoints         = 100.0;   // Pullback gap in points (simple bot: 1.0 price unit = 100 pts on XAUUSD)
input double         InpMaxSLPoints        = 1000.0;  // Max SL distance in points (advanced mode)
input double         InpTP_R               = 1.0;     // Take profit as R multiple of risk

input group "=== Advanced filters (SP2L_Advanced_Bot) ==="
input bool           InpUseEMAFilter       = true;    // Use EMA filter
input int            InpEMAPeriod          = 60;      // EMA period
input bool           InpUseTrendFilter     = true;    // Use trend structure filter
input int            InpMaxOppositeMoves   = 1;       // Max consecutive opposite moves
input bool           InpUseADXFilter       = false;   // Use ADX (range) filter
input int            InpADXPeriod          = 14;      // ADX period
input double         InpMinADX             = 20.0;    // Minimum ADX
input bool           InpUseSessionFilter   = false;   // Use session filter
input int            InpSessionStartHour   = 1;       // Session start hour
input int            InpSessionEndHour     = 5;       // Session end hour
input bool           InpSessionServerTime  = true;    // Hours in SERVER time (false = New York, server assumed UTC+3)
input bool           InpUseSecondEntry     = false;   // Show the second entry level (entry -/+ risk/2)
input bool           InpHideWhileTradeOpen = false;   // Skip new signals until the previous virtual trade hits SL or TP

input group "=== Display ==="
input bool           InpShowEMA            = true;    // Show EMA filter line
input int            InpExtendBars         = 20;      // How many bars the SL/TP/entry lines extend
input bool           InpShowLabels         = true;    // Show text labels with entry/SL/TP values
input int            InpMaxBars            = 3000;    // History depth to scan
input color          InpSLColor            = clrRed;         // SL line color
input color          InpTPColor            = clrGreen;       // TP line color
input color          InpEntryColor         = clrDodgerBlue;  // Entry line color
input color          InpSecondColor        = clrOrange;      // Second entry line color

input group "=== Alerts ==="
input bool           InpAlerts             = true;    // Pop-up alert on a new signal
input bool           InpPushAlerts         = false;   // Push notification on a new signal

//--- indicator buffers
double BufEMA[];
double BufBuyArrow[];
double BufSellArrow[];
double BufBuySetup[];
double BufSellSetup[];

//--- handles / state
int    gEmaHandle = INVALID_HANDLE;
int    gAdxHandle = INVALID_HANDLE;
string gPrefix    = "SP2L_";
double gPoint     = 0.0;

// global copy of prev_calculated (used to detect freshly closed bars for alerts)
int gPrevCalculated = 0;

// pending setup (advanced mode) - stored by time, shift-independent
bool     gHasPending    = false;
int      gPendDir       = 0;       // +1 buy, -1 sell
double   gPendSL        = 0.0;
datetime gPendSetupTime = 0;

// virtual open trade (only used when InpHideWhileTradeOpen = true)
bool   gTradeActive = false;
int    gTradeDir    = 0;
double gTradeSL     = 0.0;
double gTradeTP     = 0.0;

//+------------------------------------------------------------------+
//| Helper : vertical offset for arrows (candle-relative)            |
//+------------------------------------------------------------------+
double ArrowOffset(const double hi, const double lo)
  {
   return (0.3 * (hi - lo) + 3.0 * gPoint);
  }

//+------------------------------------------------------------------+
//| Helper : spike size factor (0 = auto per mode, author's values)  |
//+------------------------------------------------------------------+
double SpikeSizeFactor()
  {
   if(InpSpikeCandleSize > 0.0)
      return InpSpikeCandleSize;
   return (InpMode == MODE_SIMPLE) ? 2.0 : 1.5;
  }

//+------------------------------------------------------------------+
//| Helper : create a horizontal segment object                      |
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
//| Helper : create a text label object                              |
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
//| Helper : read one EMA value at a shift (false = not available)   |
//+------------------------------------------------------------------+
bool EmaValueAt(const int shift, double &value)
  {
   double tmp[];
   if(gEmaHandle == INVALID_HANDLE)
      return false;
   if(CopyBuffer(gEmaHandle, 0, shift, 1, tmp) != 1)
      return false;
   value = tmp[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Helper : read one ADX value at a shift                           |
//+------------------------------------------------------------------+
bool AdxValueAt(const int shift, double &value)
  {
   double tmp[];
   if(gAdxHandle == INVALID_HANDLE)
      return false;
   if(CopyBuffer(gAdxHandle, 0, shift, 1, tmp) != 1)
      return false;
   value = tmp[0];
   return true;
  }

//+------------------------------------------------------------------+
//| Session filter - same idea as the author's New York filter       |
//+------------------------------------------------------------------+
bool InSession(const datetime bar_time)
  {
   MqlDateTime st;
   if(InpSessionServerTime)
     {
      TimeToStruct(bar_time, st);
     }
   else
     {
      // server assumed UTC+3 (author's Meta.py assumption), New York = UTC-5 (EST)
      TimeToStruct((datetime)((long)bar_time - 8 * 3600), st);
     }
   return (st.hour >= InpSessionStartHour && st.hour < InpSessionEndHour);
  }

//+------------------------------------------------------------------+
//| Entry filters (advanced mode) - port of entry_filters_are_valid  |
//+------------------------------------------------------------------+
bool EntryFiltersValid(const int entry_shift, const double &close[], const bool isBuy)
  {
   //--- EMA filter
   if(InpUseEMAFilter)
     {
      double ema = 0.0;
      if(!EmaValueAt(entry_shift, ema))
         return false;
      if(isBuy)
        {
         if(close[entry_shift] <= ema)
            return false;
        }
      else
        {
         if(close[entry_shift] >= ema)
            return false;
        }
     }
   //--- ADX filter
   if(InpUseADXFilter)
     {
      double adx = 0.0;
      if(!AdxValueAt(entry_shift, adx))
         return false;
      if(adx < InpMinADX)
         return false;
     }
   //--- session filter
   if(InpUseSessionFilter)
     {
      if(!InSession(iTime(_Symbol, _Period, entry_shift)))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Trend structure filter - port of buy_trend_is_valid              |
//+------------------------------------------------------------------+
bool BuyTrendValid(const int setup_shift, const int entry_shift, const double &high[])
  {
   if(!InpUseTrendFilter)
      return true;
   int consecutiveOpposite = 0;
   // chronological order: from the bar after the setup bar down to the entry bar
   for(int k = setup_shift - 1; k >= entry_shift; k--)
     {
      if(high[k] > high[k + 1])
         consecutiveOpposite = 0;
      else
        {
         consecutiveOpposite++;
         if(consecutiveOpposite > InpMaxOppositeMoves)
            return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Trend structure filter - port of sell_trend_is_valid             |
//+------------------------------------------------------------------+
bool SellTrendValid(const int setup_shift, const int entry_shift, const double &low[])
  {
   if(!InpUseTrendFilter)
      return true;
   int consecutiveOpposite = 0;
   for(int k = setup_shift - 1; k >= entry_shift; k--)
     {
      if(low[k] < low[k + 1])
         consecutiveOpposite = 0;
      else
        {
         consecutiveOpposite++;
         if(consecutiveOpposite > InpMaxOppositeMoves)
            return false;
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Setup detection - port of detect_buy_setup                       |
//| s = shift of the latest candle (the "-1" candle in Python code)  |
//+------------------------------------------------------------------+
bool DetectBuySetup(const int s, const double &open[], const double &high[],
                    const double &low[], const double &close[])
  {
   double pGap = InpPGapPoints * gPoint;
   // candle -1 = s, -2 = s+1, -3 = s+2 (spike), -4 = s+3
   if(low[s] < low[s + 1] &&                    // buy0
      close[s + 1] > close[s + 2] &&            // buy1
      open[s + 1] > open[s + 2] &&              // buy2
      close[s + 2] > close[s + 3] &&            // buy3
      open[s + 2] > open[s + 3] &&              // buy4
      close[s + 1] > open[s + 1] &&             // buy5
      close[s + 2] > open[s + 2] &&             // buy6
      close[s + 3] > open[s + 3] &&             // buy7
      low[s + 1] > high[s + 3] + pGap)          // pGapBuy
     {
      double spikeBody = close[s + 2] - open[s + 2];
      if(spikeBody <= 0.0)
         return false;
      return (spikeBody > SpikeSizeFactor() * (close[s + 1] - open[s + 1]) &&
              spikeBody > SpikeSizeFactor() * (close[s + 3] - open[s + 3]) &&
              spikeBody > SpikeSizeFactor() * (close[s] - open[s]));
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Setup detection - port of detect_sell_setup                      |
//+------------------------------------------------------------------+
bool DetectSellSetup(const int s, const double &open[], const double &high[],
                     const double &low[], const double &close[])
  {
   double pGap = InpPGapPoints * gPoint;
   if(high[s] > high[s + 1] &&                  // sell0
      close[s + 1] < close[s + 2] &&            // sell1
      open[s + 1] < open[s + 2] &&              // sell2
      close[s + 2] < close[s + 3] &&            // sell3
      open[s + 2] < open[s + 3] &&              // sell4
      close[s + 1] < open[s + 1] &&             // sell5
      close[s + 2] < open[s + 2] &&             // sell6
      close[s + 3] < open[s + 3] &&             // sell7
      high[s + 1] < low[s + 3] - pGap)          // pGapSell
     {
      double spikeBody = open[s + 2] - close[s + 2];
      if(spikeBody <= 0.0)
         return false;
      return (spikeBody > SpikeSizeFactor() * (open[s + 1] - close[s + 1]) &&
              spikeBody > SpikeSizeFactor() * (open[s + 3] - close[s + 3]) &&
              spikeBody > SpikeSizeFactor() * (open[s] - close[s]));
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Draw one complete signal (entry arrow + SL/TP/entry lines)       |
//+------------------------------------------------------------------+
void DrawSignal(const bool isBuy, const int entry_shift, const double entry,
                const double sl, const double tp, const double second,
                const datetime &time[], const double &high[], const double &low[])
  {
   datetime t = time[entry_shift];
   string id = TimeToString(t, TIME_DATE | TIME_MINUTES);
   StringReplace(id, ".", "-");
   StringReplace(id, ":", "-");
   StringReplace(id, " ", "_");
   string dirTxt = isBuy ? "BUY" : "SELL";

   //--- arrows (candle-relative offset)
   if(isBuy)
      BufBuyArrow[entry_shift]  = low[entry_shift] - ArrowOffset(high[entry_shift], low[entry_shift]);
   else
      BufSellArrow[entry_shift] = high[entry_shift] + ArrowOffset(high[entry_shift], low[entry_shift]);

   //--- lines : SL / TP / entry / second entry
   CreateLevelLine(id + "_SL", t, sl, InpSLColor, STYLE_SOLID, 2,
                   "SP2L " + dirTxt + " SL");
   CreateLevelLine(id + "_TP", t, tp, InpTPColor, STYLE_SOLID, 2,
                   "SP2L " + dirTxt + " TP");
   if(InpMode == MODE_ADVANCED)
      CreateLevelLine(id + "_ENTRY", t, entry, InpEntryColor, STYLE_DOT, 1,
                      "SP2L " + dirTxt + " entry");
   if(InpUseSecondEntry && second > 0.0)
      CreateLevelLine(id + "_SECOND", t, second, InpSecondColor, STYLE_DOT, 1,
                      "SP2L second entry");

   //--- text label
   if(InpShowLabels)
     {
      string txt = StringFormat("SP2L %s  E:%s SL:%s TP:%s",
                                dirTxt,
                                DoubleToString(entry, _Digits),
                                DoubleToString(sl, _Digits),
                                DoubleToString(tp, _Digits));
      CreateLabel(id + "_TXT", t, tp, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   //--- alerts (only for freshly closed bars, not during the history scan)
   if(entry_shift == 1 && gPrevCalculated > 0)
     {
      string msg = StringFormat("SP2L %s on %s %s | entry %s SL %s TP %s",
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
//| Try to trigger the pending setup at bar s (advanced mode)        |
//| returns true if the entry fired                                  |
//+------------------------------------------------------------------+
bool TryPendingEntry(const int s, const datetime &time[], const double &high[],
                     const double &low[], const double &close[])
  {
   int setup_shift = iBarShift(_Symbol, _Period, gPendSetupTime, false);
   if(setup_shift < 0)
     {
      gHasPending = false;   // setup bar fell out of the available history
      return false;
     }

   double maxSL = InpMaxSLPoints * gPoint;

   if(gPendDir > 0)
     {
      if(low[s] >= low[s + 1])
         return false;                                   // no low-break yet
      double risk = low[s] - gPendSL;
      if(risk > maxSL)
        {
         gHasPending = false;                            // INVALID - too far
         return false;
        }
      if(risk <= 0.0)
         return false;
      if(!BuyTrendValid(setup_shift, s, high))
         return false;
      if(!EntryFiltersValid(s, close, true))
         return false;
      double entry  = low[s];
      double tp     = entry + InpTP_R * risk;
      double second = InpUseSecondEntry ? entry - risk / 2.0 : 0.0;
      DrawSignal(true, s, entry, gPendSL, tp, second, time, high, low);
      gHasPending = false;
      if(InpHideWhileTradeOpen)
        {
         gTradeActive = true;
         gTradeDir    = 1;
         gTradeSL     = gPendSL;
         gTradeTP     = tp;
        }
      return true;
     }
   else
     {
      if(high[s] <= high[s + 1])
         return false;                                   // no high-break yet
      double risk = gPendSL - high[s];
      if(risk > maxSL)
        {
         gHasPending = false;                            // INVALID - too far
         return false;
        }
      if(risk <= 0.0)
         return false;
      if(!SellTrendValid(setup_shift, s, low))
         return false;
      if(!EntryFiltersValid(s, close, false))
         return false;
      double entry  = high[s];
      double tp     = entry - InpTP_R * risk;
      double second = InpUseSecondEntry ? entry + risk / 2.0 : 0.0;
      DrawSignal(false, s, entry, gPendSL, tp, second, time, high, low);
      gHasPending = false;
      if(InpHideWhileTradeOpen)
        {
         gTradeActive = true;
         gTradeDir    = -1;
         gTradeSL     = gPendSL;
         gTradeTP     = tp;
        }
      return true;
     }
  }

//+------------------------------------------------------------------+
//| Process one closed bar (shift s)                                 |
//+------------------------------------------------------------------+
void ProcessBar(const int s, const datetime &time[], const double &open[],
                const double &high[], const double &low[], const double &close[])
  {
   //--- 1) virtual trade management (HideWhileTradeOpen mode)
   if(gTradeActive)
     {
      if(gTradeDir > 0)
        {
         if(low[s] <= gTradeSL || high[s] >= gTradeTP)
            gTradeActive = false;
        }
      else
        {
         if(high[s] >= gTradeSL || low[s] <= gTradeTP)
            gTradeActive = false;
        }
      if(gTradeActive)
         return;   // still inside the previous trade - no new signals
     }

   //--- 2) advanced mode: try to trigger the pending setup
   if(InpMode == MODE_ADVANCED && gHasPending)
     {
      if(TryPendingEntry(s, time, high, low, close))
         return;   // an entry fired - the bot would not look for a new setup now
     }

   //--- 3) look for a new setup (a new exclusive setup overwrites the pending one,
   //---    exactly like the author's Strategy() flow)
   bool buySetup  = DetectBuySetup(s, open, high, low, close);
   bool sellSetup = DetectSellSetup(s, open, high, low, close);

   if(buySetup && !sellSetup)
     {
      BufBuySetup[s + 2] = high[s + 2] + ArrowOffset(high[s + 2], low[s + 2]);  // mark the spike candle
      if(InpMode == MODE_ADVANCED)
        {
         gHasPending    = true;
         gPendDir       = 1;
         gPendSL        = low[s + 3];        // SL = low of the candle before the spike
         gPendSetupTime = time[s];
         // the live bot can fire on the very same candle (its low keeps breaking)
         TryPendingEntry(s, time, high, low, close);
        }
      else
        {
         //--- simple mode : immediate entry (like SP2L_Bot)
         double entry = close[s];
         double sl    = low[s + 3];
         double risk  = entry - sl;
         if(risk > 0.0)
           {
            double tp     = entry + InpTP_R * risk;
            double second = InpUseSecondEntry ? entry - risk / 2.0 : 0.0;
            DrawSignal(true, s, entry, sl, tp, second, time, high, low);
            if(InpHideWhileTradeOpen)
              {
               gTradeActive = true;
               gTradeDir    = 1;
               gTradeSL     = sl;
               gTradeTP     = tp;
              }
           }
        }
     }
   else if(sellSetup && !buySetup)
     {
      BufSellSetup[s + 2] = low[s + 2] - ArrowOffset(high[s + 2], low[s + 2]);  // mark the spike candle
      if(InpMode == MODE_ADVANCED)
        {
         gHasPending    = true;
         gPendDir       = -1;
         gPendSL        = high[s + 3];       // SL = high of the candle before the spike
         gPendSetupTime = time[s];
         TryPendingEntry(s, time, high, low, close);
        }
      else
        {
         double entry = close[s];
         double sl    = high[s + 3];
         double risk  = sl - entry;
         if(risk > 0.0)
           {
            double tp     = entry - InpTP_R * risk;
            double second = InpUseSecondEntry ? entry + risk / 2.0 : 0.0;
            DrawSignal(false, s, entry, sl, tp, second, time, high, low);
            if(InpHideWhileTradeOpen)
              {
               gTradeActive = true;
               gTradeDir    = -1;
               gTradeSL     = sl;
               gTradeTP     = tp;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Custom indicator initialization                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   gPoint = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   if(gPoint <= 0.0)
     {
      Print("SP2L: invalid symbol point");
      return INIT_FAILED;
     }

   SetIndexBuffer(0, BufEMA, INDICATOR_DATA);
   SetIndexBuffer(1, BufBuyArrow, INDICATOR_DATA);
   SetIndexBuffer(2, BufSellArrow, INDICATOR_DATA);
   SetIndexBuffer(3, BufBuySetup, INDICATOR_DATA);
   SetIndexBuffer(4, BufSellSetup, INDICATOR_DATA);

   ArraySetAsSeries(BufEMA, true);
   ArraySetAsSeries(BufBuyArrow, true);
   ArraySetAsSeries(BufSellArrow, true);
   ArraySetAsSeries(BufBuySetup, true);
   ArraySetAsSeries(BufSellSetup, true);

   PlotIndexSetInteger(1, PLOT_ARROW, 233);   // up arrow
   PlotIndexSetInteger(2, PLOT_ARROW, 234);   // down arrow
   PlotIndexSetInteger(3, PLOT_ARROW, 68);    // diamond
   PlotIndexSetInteger(4, PLOT_ARROW, 68);    // diamond

   for(int i = 0; i < 5; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   PlotIndexSetInteger(0, PLOT_DRAW_TYPE, InpShowEMA ? DRAW_LINE : DRAW_NONE);

   IndicatorSetString(INDICATOR_SHORTNAME,
                      "SP2L (" + (InpMode == MODE_ADVANCED ? "Advanced" : "Simple") + ")");
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);

   gEmaHandle = iMA(_Symbol, _Period, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE);
   if(gEmaHandle == INVALID_HANDLE)
     {
      Print("SP2L: failed to create the EMA handle");
      return INIT_FAILED;
     }

   if(InpUseADXFilter)
     {
      gAdxHandle = iADX(_Symbol, _Period, InpADXPeriod);
      if(gAdxHandle == INVALID_HANDLE)
        {
         Print("SP2L: failed to create the ADX handle");
         return INIT_FAILED;
        }
     }

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   if(gEmaHandle != INVALID_HANDLE)
      IndicatorRelease(gEmaHandle);
   if(gAdxHandle != INVALID_HANDLE)
      IndicatorRelease(gAdxHandle);
   ObjectsDeleteAll(0, gPrefix);
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration                                       |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   gPrevCalculated = prev_calculated;

   if(rates_total < 10)
      return 0;

   ArraySetAsSeries(time, true);
   ArraySetAsSeries(open, true);
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);
   ArraySetAsSeries(close, true);

   //--- copy the EMA (same source as the filter, so plot and filter always match)
   int toCopy = (prev_calculated == 0) ? rates_total : (rates_total - prev_calculated + 1);
   double emaTmp[];
   ArraySetAsSeries(emaTmp, true);
   if(CopyBuffer(gEmaHandle, 0, 0, toCopy, emaTmp) < toCopy)
      return 0;   // EMA not ready yet - try again on the next tick

   if(prev_calculated == 0)
     {
      ArrayInitialize(BufEMA, EMPTY_VALUE);
      ArrayInitialize(BufBuyArrow, EMPTY_VALUE);
      ArrayInitialize(BufSellArrow, EMPTY_VALUE);
      ArrayInitialize(BufBuySetup, EMPTY_VALUE);
      ArrayInitialize(BufSellSetup, EMPTY_VALUE);

      // reset runtime state and redraw everything
      gHasPending   = false;
      gTradeActive  = false;
      ObjectsDeleteAll(0, gPrefix);

      for(int i = 0; i < toCopy; i++)
         BufEMA[i] = emaTmp[i];

      int maxShift = MathMin(InpMaxBars, rates_total - 5);
      for(int s = maxShift; s >= 1; s--)
         ProcessBar(s, time, open, high, low, close);
     }
   else
     {
      int newBars = rates_total - prev_calculated;

      // initialise the freshly added buffer cells (avoid garbage arrows)
      for(int i = 0; i <= newBars && i < rates_total; i++)
        {
         BufBuyArrow[i]  = EMPTY_VALUE;
         BufSellArrow[i] = EMPTY_VALUE;
         BufBuySetup[i]  = EMPTY_VALUE;
         BufSellSetup[i] = EMPTY_VALUE;
        }
      for(int i = 0; i < toCopy; i++)
         BufEMA[i] = emaTmp[i];

      // process the newly closed bars (shift 1 = the bar that just closed)
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
