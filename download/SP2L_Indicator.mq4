//+------------------------------------------------------------------+
//|                                               SP2L_Indicator.mq4 |
//|         SP2L (Spike + Pullback + Gap) indicator for MetaTrader 4 |
//|                                                                  |
//|  Faithful MQL4 port of the SP2L strategy by Alireza Sadabadi     |
//|  (PythonTraderBot repository - code/SP2L/):                      |
//|     - SP2L_Bot.py          (Simple trader)                       |
//|     - SP2L_Advanced_Bot.py (Advanced trader: EMA / trend / ADX / |
//|       session filters, max SL distance, TP_R, second entry)      |
//|  Author's tutorials: https://youtube.com/@alirezasadabadi        |
//|  Same logic and inputs as the MT5 version (SP2L_Indicator.mq5).  |
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
//|  Requires MT4 build 600 or newer (for MQL4 "strict" features).   |
//+------------------------------------------------------------------+
#property copyright   "SP2L strategy by Alireza Sadabadi - MQL4 port for PythonTraderBot Control Center"
#property link        "https://youtube.com/@alirezasadabadi"
#property version     "1.01"
#property strict
#property description "SP2L (Spike + Pullback + Gap) signals with SL / TP levels - exact port of the author's Python strategy"
#property indicator_chart_window
#property indicator_buffers 5

//--- plot 0 : EMA filter line
#property indicator_label1  "EMA filter"
#property indicator_color1  clrSilver
#property indicator_style1  STYLE_DOT
#property indicator_width1  1
//--- plot 1 : BUY entry arrow
#property indicator_label2  "SP2L BUY"
#property indicator_color2  clrLime
#property indicator_width2  2
//--- plot 2 : SELL entry arrow
#property indicator_label3  "SP2L SELL"
#property indicator_color3  clrRed
#property indicator_width3  2
//--- plot 3 : BUY setup marker (diamond on the spike candle)
#property indicator_label4  "SP2L BUY setup"
#property indicator_color4  clrAqua
#property indicator_width4  1
//--- plot 4 : SELL setup marker (diamond on the spike candle)
#property indicator_label5  "SP2L SELL setup"
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

//--- === Strategy ===
input ENUM_SP2L_MODE InpMode               = MODE_ADVANCED; // Strategy mode
input double         InpSpikeCandleSize    = 0.0;     // Spike candle size (0 = auto: Simple 2.0 / Advanced 1.5, the author's defaults)
input double         InpPGapPoints         = 100.0;   // Pullback gap in points (simple bot: 1.0 price unit = 100 pts on XAUUSD)
input double         InpMaxSLPoints        = 1000.0;  // Max SL distance in points (advanced mode)
input double         InpTP_R               = 1.0;     // Take profit as R multiple of risk

//--- === Advanced filters (SP2L_Advanced_Bot) ===
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

//--- === Display ===
input bool           InpShowEMA            = true;    // Show EMA filter line
input int            InpExtendBars         = 20;      // How many bars the SL/TP/entry lines extend
input bool           InpShowLabels         = true;    // Show text labels with entry/SL/TP values
input int            InpMaxBars            = 3000;    // History depth to scan
input color          InpSLColor            = clrRed;         // SL line color
input color          InpTPColor            = clrGreen;       // TP line color
input color          InpEntryColor         = clrDodgerBlue;  // Entry line color
input color          InpSecondColor        = clrOrange;      // Second entry line color

//--- === Alerts ===
input bool           InpAlerts             = true;    // Pop-up alert on a new signal
input bool           InpPushAlerts         = false;   // Push notification on a new signal

//--- indicator buffers
double BufEMA[];
double BufBuyArrow[];
double BufSellArrow[];
double BufBuySetup[];
double BufSellSetup[];

//--- state
string gPrefix     = "SP2L_";
double gPoint      = 0.0;
bool   gFullScan   = true;     // true during the initial history scan (suppresses alerts)

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
//| Helper : readable timeframe name for alerts                      |
//+------------------------------------------------------------------+
string PeriodToStr()
  {
   switch(Period())
     {
      case PERIOD_M1:  return "M1";
      case PERIOD_M5:  return "M5";
      case PERIOD_M15: return "M15";
      case PERIOD_M30: return "M30";
      case PERIOD_H1:  return "H1";
      case PERIOD_H4:  return "H4";
      case PERIOD_D1:  return "D1";
      case PERIOD_W1:  return "W1";
      case PERIOD_MN1: return "MN1";
     }
   return "M" + IntegerToString(Period());
  }

//+------------------------------------------------------------------+
//| Helper : delete every chart object created by this indicator     |
//+------------------------------------------------------------------+
void DeleteAllObjects()
  {
   for(int i = ObjectsTotal() - 1; i >= 0; i--)
     {
      string name = ObjectName(i);
      if(StringFind(name, gPrefix) == 0)
         ObjectDelete(name);
     }
  }

//+------------------------------------------------------------------+
//| Helper : create a horizontal segment object                      |
//+------------------------------------------------------------------+
void CreateLevelLine(const string tag, const datetime t1, const double price,
                     const color clr, const int style, const int width,
                     const string descr)
  {
   string   name = gPrefix + tag;
   datetime t2   = t1 + InpExtendBars * Period() * 60;
   if(ObjectFind(name) >= 0)
      ObjectDelete(name);
   if(!ObjectCreate(name, OBJ_TREND, 0, t1, price, t2, price))
      return;
   ObjectSet(name, OBJPROP_COLOR, clr);
   ObjectSet(name, OBJPROP_STYLE, style);
   ObjectSet(name, OBJPROP_WIDTH, width);
   ObjectSet(name, OBJPROP_RAY, false);
   ObjectSet(name, OBJPROP_BACK, false);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
   ObjectSetText(name, descr);
  }

//+------------------------------------------------------------------+
//| Helper : create a text label object                              |
//+------------------------------------------------------------------+
void CreateLabel(const string tag, const datetime t, const double price,
                 const string text, const color clr, const int anchor)
  {
   string name = gPrefix + tag;
   if(ObjectFind(name) >= 0)
      ObjectDelete(name);
   if(!ObjectCreate(name, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetText(name, text, 8, "Arial", clr);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSet(name, OBJPROP_SELECTABLE, false);
  }

//+------------------------------------------------------------------+
//| Helper : EMA filter value at a shift                             |
//+------------------------------------------------------------------+
double EmaValueAt(const int shift)
  {
   return iMA(NULL, 0, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, shift);
  }

//+------------------------------------------------------------------+
//| Helper : ADX value at a shift                                    |
//+------------------------------------------------------------------+
double AdxValueAt(const int shift)
  {
   return iADX(NULL, 0, InpADXPeriod, PRICE_CLOSE, MODE_MAIN, shift);
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
bool EntryFiltersValid(const int entry_shift, const bool isBuy)
  {
   //--- EMA filter
   if(InpUseEMAFilter)
     {
      double ema = EmaValueAt(entry_shift);
      if(ema <= 0.0)
         return false;
      if(isBuy)
        {
         if(Close[entry_shift] <= ema)
            return false;
        }
      else
        {
         if(Close[entry_shift] >= ema)
            return false;
        }
     }
   //--- ADX filter
   if(InpUseADXFilter)
     {
      double adx = AdxValueAt(entry_shift);
      if(adx < InpMinADX)
         return false;
     }
   //--- session filter
   if(InpUseSessionFilter)
     {
      if(!InSession(iTime(NULL, 0, entry_shift)))
         return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Trend structure filter - port of buy_trend_is_valid              |
//+------------------------------------------------------------------+
bool BuyTrendValid(const int setup_shift, const int entry_shift)
  {
   if(!InpUseTrendFilter)
      return true;
   int consecutiveOpposite = 0;
   // chronological order: from the bar after the setup bar down to the entry bar
   for(int k = setup_shift - 1; k >= entry_shift; k--)
     {
      if(High[k] > High[k + 1])
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
bool SellTrendValid(const int setup_shift, const int entry_shift)
  {
   if(!InpUseTrendFilter)
      return true;
   int consecutiveOpposite = 0;
   for(int k = setup_shift - 1; k >= entry_shift; k--)
     {
      if(Low[k] < Low[k + 1])
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
bool DetectBuySetup(const int s)
  {
   double pGap = InpPGapPoints * gPoint;
   // candle -1 = s, -2 = s+1, -3 = s+2 (spike), -4 = s+3
   if(Low[s] < Low[s + 1] &&                       // buy0
      Close[s + 1] > Close[s + 2] &&               // buy1
      Open[s + 1] > Open[s + 2] &&                 // buy2
      Close[s + 2] > Close[s + 3] &&               // buy3
      Open[s + 2] > Open[s + 3] &&                 // buy4
      Close[s + 1] > Open[s + 1] &&                // buy5
      Close[s + 2] > Open[s + 2] &&                // buy6
      Close[s + 3] > Open[s + 3] &&                // buy7
      Low[s + 1] > High[s + 3] + pGap)             // pGapBuy
     {
      double spikeBody = Close[s + 2] - Open[s + 2];
      if(spikeBody <= 0.0)
         return false;
      return (spikeBody > SpikeSizeFactor() * (Close[s + 1] - Open[s + 1]) &&
              spikeBody > SpikeSizeFactor() * (Close[s + 3] - Open[s + 3]) &&
              spikeBody > SpikeSizeFactor() * (Close[s] - Open[s]));
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Setup detection - port of detect_sell_setup                      |
//+------------------------------------------------------------------+
bool DetectSellSetup(const int s)
  {
   double pGap = InpPGapPoints * gPoint;
   if(High[s] > High[s + 1] &&                     // sell0
      Close[s + 1] < Close[s + 2] &&               // sell1
      Open[s + 1] < Open[s + 2] &&                 // sell2
      Close[s + 2] < Close[s + 3] &&               // sell3
      Open[s + 2] < Open[s + 3] &&                 // sell4
      Close[s + 1] < Open[s + 1] &&                // sell5
      Close[s + 2] < Open[s + 2] &&                // sell6
      Close[s + 3] < Open[s + 3] &&                // sell7
      High[s + 1] < Low[s + 3] - pGap)             // pGapSell
     {
      double spikeBody = Open[s + 2] - Close[s + 2];
      if(spikeBody <= 0.0)
         return false;
      return (spikeBody > SpikeSizeFactor() * (Open[s + 1] - Close[s + 1]) &&
              spikeBody > SpikeSizeFactor() * (Open[s + 3] - Close[s + 3]) &&
              spikeBody > SpikeSizeFactor() * (Open[s] - Close[s]));
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Draw one complete signal (entry arrow + SL/TP/entry lines)       |
//+------------------------------------------------------------------+
void DrawSignal(const bool isBuy, const int entry_shift, const double entry,
                const double sl, const double tp, const double second)
  {
   datetime t = Time[entry_shift];
   string id = TimeToString(t, TIME_DATE | TIME_MINUTES);
   StringReplace(id, ".", "-");
   StringReplace(id, ":", "-");
   StringReplace(id, " ", "_");
   string dirTxt = isBuy ? "BUY" : "SELL";

   //--- arrows (candle-relative offset)
   if(isBuy)
      BufBuyArrow[entry_shift]  = Low[entry_shift] - ArrowOffset(High[entry_shift], Low[entry_shift]);
   else
      BufSellArrow[entry_shift] = High[entry_shift] + ArrowOffset(High[entry_shift], Low[entry_shift]);

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
                                DoubleToString(entry, Digits),
                                DoubleToString(sl, Digits),
                                DoubleToString(tp, Digits));
      CreateLabel(id + "_TXT", t, tp, txt, isBuy ? clrLime : clrRed,
                  isBuy ? ANCHOR_LEFT_LOWER : ANCHOR_LEFT_UPPER);
     }

   //--- alerts (only for freshly closed bars, not during the history scan)
   if(entry_shift == 1 && !gFullScan)
     {
      string msg = StringFormat("SP2L %s on %s %s | entry %s SL %s TP %s",
                                dirTxt, Symbol(), PeriodToStr(),
                                DoubleToString(entry, Digits),
                                DoubleToString(sl, Digits),
                                DoubleToString(tp, Digits));
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
bool TryPendingEntry(const int s)
  {
   int setup_shift = iBarShift(NULL, 0, gPendSetupTime, false);
   if(setup_shift < 0)
     {
      gHasPending = false;   // setup bar fell out of the available history
      return false;
     }

   double maxSL = InpMaxSLPoints * gPoint;

   if(gPendDir > 0)
     {
      if(Low[s] >= Low[s + 1])
         return false;                                   // no low-break yet
      double risk = Low[s] - gPendSL;
      if(risk > maxSL)
        {
         gHasPending = false;                            // INVALID - too far
         return false;
        }
      if(risk <= 0.0)
         return false;
      if(!BuyTrendValid(setup_shift, s))
         return false;
      if(!EntryFiltersValid(s, true))
         return false;
      double entry  = Low[s];
      double tp     = entry + InpTP_R * risk;
      double second = InpUseSecondEntry ? entry - risk / 2.0 : 0.0;
      DrawSignal(true, s, entry, gPendSL, tp, second);
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
      if(High[s] <= High[s + 1])
         return false;                                   // no high-break yet
      double risk = gPendSL - High[s];
      if(risk > maxSL)
        {
         gHasPending = false;                            // INVALID - too far
         return false;
        }
      if(risk <= 0.0)
         return false;
      if(!SellTrendValid(setup_shift, s))
         return false;
      if(!EntryFiltersValid(s, false))
         return false;
      double entry  = High[s];
      double tp     = entry - InpTP_R * risk;
      double second = InpUseSecondEntry ? entry + risk / 2.0 : 0.0;
      DrawSignal(false, s, entry, gPendSL, tp, second);
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
void ProcessBar(const int s)
  {
   //--- 1) virtual trade management (HideWhileTradeOpen mode)
   if(gTradeActive)
     {
      if(gTradeDir > 0)
        {
         if(Low[s] <= gTradeSL || High[s] >= gTradeTP)
            gTradeActive = false;
        }
      else
        {
         if(High[s] >= gTradeSL || Low[s] <= gTradeTP)
            gTradeActive = false;
        }
      if(gTradeActive)
         return;   // still inside the previous trade - no new signals
     }

   //--- 2) advanced mode: try to trigger the pending setup
   if(InpMode == MODE_ADVANCED && gHasPending)
     {
      if(TryPendingEntry(s))
         return;   // an entry fired - the bot would not look for a new setup now
     }

   //--- 3) look for a new setup (a new exclusive setup overwrites the pending one,
   //---    exactly like the author's Strategy() flow)
   bool buySetup  = DetectBuySetup(s);
   bool sellSetup = DetectSellSetup(s);

   if(buySetup && !sellSetup)
     {
      BufBuySetup[s + 2] = High[s + 2] + ArrowOffset(High[s + 2], Low[s + 2]);  // mark the spike candle
      if(InpMode == MODE_ADVANCED)
        {
         gHasPending    = true;
         gPendDir       = 1;
         gPendSL        = Low[s + 3];        // SL = low of the candle before the spike
         gPendSetupTime = Time[s];
         // the live bot can fire on the very same candle (its low keeps breaking)
         TryPendingEntry(s);
        }
      else
        {
         //--- simple mode : immediate entry (like SP2L_Bot)
         double entry = Close[s];
         double sl    = Low[s + 3];
         double risk  = entry - sl;
         if(risk > 0.0)
           {
            double tp     = entry + InpTP_R * risk;
            double second = InpUseSecondEntry ? entry - risk / 2.0 : 0.0;
            DrawSignal(true, s, entry, sl, tp, second);
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
      BufSellSetup[s + 2] = Low[s + 2] - ArrowOffset(High[s + 2], Low[s + 2]);  // mark the spike candle
      if(InpMode == MODE_ADVANCED)
        {
         gHasPending    = true;
         gPendDir       = -1;
         gPendSL        = High[s + 3];       // SL = high of the candle before the spike
         gPendSetupTime = Time[s];
         TryPendingEntry(s);
        }
      else
        {
         double entry = Close[s];
         double sl    = High[s + 3];
         double risk  = sl - entry;
         if(risk > 0.0)
           {
            double tp     = entry - InpTP_R * risk;
            double second = InpUseSecondEntry ? entry + risk / 2.0 : 0.0;
            DrawSignal(false, s, entry, sl, tp, second);
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
   gPoint = Point;
   if(gPoint <= 0.0)
     {
      Print("SP2L: invalid symbol point");
      return INIT_FAILED;
     }

   IndicatorBuffers(5);

   SetIndexBuffer(0, BufEMA);
   SetIndexStyle(0, InpShowEMA ? DRAW_LINE : DRAW_NONE, STYLE_DOT, 1, clrSilver);
   SetIndexLabel(0, "EMA filter");
   SetIndexEmptyValue(0, EMPTY_VALUE);

   SetIndexBuffer(1, BufBuyArrow);
   SetIndexStyle(1, DRAW_ARROW, EMPTY, 2, clrLime);
   SetIndexArrow(1, 233);                    // up arrow
   SetIndexLabel(1, "SP2L BUY");
   SetIndexEmptyValue(1, EMPTY_VALUE);

   SetIndexBuffer(2, BufSellArrow);
   SetIndexStyle(2, DRAW_ARROW, EMPTY, 2, clrRed);
   SetIndexArrow(2, 234);                    // down arrow
   SetIndexLabel(2, "SP2L SELL");
   SetIndexEmptyValue(2, EMPTY_VALUE);

   SetIndexBuffer(3, BufBuySetup);
   SetIndexStyle(3, DRAW_ARROW, EMPTY, 1, clrAqua);
   SetIndexArrow(3, 68);                     // diamond
   SetIndexLabel(3, "SP2L BUY setup");
   SetIndexEmptyValue(3, EMPTY_VALUE);

   SetIndexBuffer(4, BufSellSetup);
   SetIndexStyle(4, DRAW_ARROW, EMPTY, 1, clrMagenta);
   SetIndexArrow(4, 68);                     // diamond
   SetIndexLabel(4, "SP2L SELL setup");
   SetIndexEmptyValue(4, EMPTY_VALUE);

   IndicatorShortName("SP2L (" + (InpMode == MODE_ADVANCED ? "Advanced" : "Simple") + ")");
   IndicatorDigits(Digits);

   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Custom indicator deinitialization                                |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   DeleteAllObjects();
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Custom indicator iteration (classic MQL4 handler)                |
//+------------------------------------------------------------------+
int start()
  {
   if(Bars < 10)
      return 0;

   int counted = IndicatorCounted();
   if(counted < 0)
      return -1;

   bool fullRecalc = (counted == 0);
   gFullScan = fullRecalc;

   int limit = Bars - counted - 1;
   if(limit < 0)
      limit = 0;
   if(limit > Bars - 5)
      limit = Bars - 5;
   if(fullRecalc && limit > InpMaxBars)
      limit = InpMaxBars;

   if(fullRecalc)
     {
      // reset runtime state and redraw everything
      ArrayInitialize(BufEMA, EMPTY_VALUE);
      ArrayInitialize(BufBuyArrow, EMPTY_VALUE);
      ArrayInitialize(BufSellArrow, EMPTY_VALUE);
      ArrayInitialize(BufBuySetup, EMPTY_VALUE);
      ArrayInitialize(BufSellSetup, EMPTY_VALUE);
      gHasPending  = false;
      gTradeActive = false;
      DeleteAllObjects();
     }
   else
     {
      // initialise the freshly added buffer cells (avoid garbage arrows)
      for(int i = limit; i >= 0; i--)
        {
         BufBuyArrow[i]  = EMPTY_VALUE;
         BufSellArrow[i] = EMPTY_VALUE;
         BufBuySetup[i]  = EMPTY_VALUE;
         BufSellSetup[i] = EMPTY_VALUE;
        }
     }

   //--- EMA filter line (updates the forming bar on every tick too)
   for(int i = limit; i >= 0; i--)
     {
      double e = iMA(NULL, 0, InpEMAPeriod, 0, MODE_EMA, PRICE_CLOSE, i);
      BufEMA[i] = (e > 0.0) ? e : EMPTY_VALUE;
     }

   //--- process the closed bars, oldest first (shift 1 = the bar that just closed)
   for(int s = limit; s >= 1; s--)
      ProcessBar(s);

   ChartRedraw();
   return 0;
  }
//+------------------------------------------------------------------+
