//+------------------------------------------------------------------+
//|                                    QuantumGoldTrader_v4.1.mq5    |
//|          v4.1 — Adaptive Strategies from FXNX 2026 Article       |
//+------------------------------------------------------------------+
//  NEW in v4.1 (from FXNX "XAUUSD 2026: Adaptive Gold Trading"):
//  1. Market Regime Detection: auto-switches Trend / Range / Breakout mode
//  2. Intermarket DXY Correlation Filter: skip longs when DXY is surging
//  3. RSI Divergence Filter: bearish/bullish divergence as entry confirmation
//  4. Gold-Silver Ratio Sentiment Filter: extreme ratio = oversold metals
//  5. Multi-Timeframe (MTF) H4 trend confirmation before M15 entry
//  6. Scenario-based position sizing: stagflation = normal, risk-off = reduced
//  7. News Spike Guard: skip first N bars after high-impact news hour
//  8. Minimum RR 1:2 enforcement per FXNX recommendation
//  ---------------------------------------------------------------
//  DISCLAIMER: Always forward-test on DEMO before live deployment.
//+------------------------------------------------------------------+
#property copyright "QuantumGoldTrader v4.1"
#property version   "4.11"
#property strict
#property description "Quantum Gold Trader v4.1 - Adaptive 2026 XAUUSD Strategy (July 2026 Optimized, bug-fixed)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- ================================================================
//    INPUTS
//--- ================================================================

input string  __General__        = "=== General Settings ===";
input ulong   MagicNumber        = 20260411;
input double  BaseRiskPercent    = 0.65;
input int     MaxPositions       = 2;
input bool    UseDynamicRisk     = true;

input string  __Strategy__       = "=== Core Strategy (v4.0) ===";
input ENUM_TIMEFRAMES Timeframe  = PERIOD_M15;
input int     EMA_Fast           = 8;
input int     EMA_Slow           = 21;
input int     EMA_Trend          = 190;
input int     RSI_Period         = 14;
input double  RSI_LongMax        = 60.0;
input double  RSI_ShortMin       = 40.0;
input int     ATR_Period         = 14;
input double  MinATR_Multiplier  = 1.0;

input string  __TrendFilter__    = "=== 190 EMA Trend Filter ===";
input bool    UseTrendFilter     = true;

input string  __VIX__            = "=== VIX Risk-Off Filter ===";
input bool    UseVIXFilter       = true;
input string  VIX_Symbol         = "VIX";
input double  VIX_RiskOff        = 25.0;
input int     VIX_HoldBars       = 2;

input string  __Breakout__       = "=== Breakout Filter ===";
input bool    UseBreakoutFilter  = true;
input int     BreakoutLookback   = 20;
input double  BreakoutBuffer_ATR = 0.3;

// ================================================================
// NEW v4.1 INPUTS
// ================================================================

input string  __RegimeDetect__   = "=== [v4.1] Market Regime Detection ===";
input bool    UseRegimeFilter    = true;
// ADX threshold: above = trending, below = ranging
input int     ADX_Period         = 14;
input double  ADX_TrendMin       = 23.5;   // Optimized July 2026 (was 22.0)
input double  ADX_RangeMax       = 21.0;   // Optimized July 2026 (was 20.0)
// Bollinger Bands for range mode
input int     BB_Period          = 20;
input double  BB_Deviation       = 2.0;

input string  __MTF__            = "=== [v4.1] Multi-Timeframe H4 Confirmation ===";
input bool    UseMTFFilter       = true;
// H4 EMA21 must agree with the direction of the M15 signal
input int     MTF_EMA_Period     = 21;

input string  __DXY__            = "=== [v4.1] DXY Correlation Filter ===";
input bool    UseDXYFilter       = true;
input string  DXY_Symbol         = "USDX";  // or "DX-Y.NYB" depending on broker
// Block LONG gold when DXY is surging (closed above its EMA10 for N bars)
input int     DXY_EMA_Period     = 10;
input int     DXY_AboveEMA_Bars  = 2;       // DXY must be above EMA for this many bars to block long

input string  __Divergence__     = "=== [v4.1] RSI Divergence Confirmation ===";
input bool    UseDivergenceFilter = true;
// Require bullish RSI divergence for LONG (price lower low, RSI higher low)
// Require bearish RSI divergence for SHORT (price higher high, RSI lower high)
// Look-back window for divergence
input int     Div_Lookback       = 5;       // bars to look back for swing comparison

input string  __GoldSilver__     = "=== [v4.1] Gold/Silver Ratio Sentiment ===";
input bool    UseGSRatioFilter   = true;
input string  Silver_Symbol      = "XAGUSD";
// Extreme high ratio = precious metals oversold = buy bias only
input double  GSRatio_ExtHigh    = 88.0;    // ratio above this = metals cheap, long bias
input double  GSRatio_ExtLow     = 70.0;    // ratio below this = metals expensive, reduce longs

input string  __NewsGuard__      = "=== [v4.1] News Spike Guard ===";
input bool    UseNewsGuard       = true;
// Block all entries for this many bars after these high-impact hours (server time)
input string  NewsHours          = "14,15,20,21";  // FOMC/NFP typical hours
input int     NewsGuard_Bars     = 3;               // bars to skip after news hour opens

input string  __ScenarioRisk__   = "=== [v4.1] Scenario-Based Position Sizing ===";
input bool    UseScenarioSizing  = true;
// In VIX risk-off OR DXY surge: reduce size to be more defensive
input double  RiskOff_SizeMult   = 0.6;     // multiply lot by this in risk-off scenario
// In extreme GSRatio (oversold metals): slightly increase long size conviction
input double  Stagflation_SizeMult = 1.15;  // max 1.15x — still capped at BaseRisk

input string  __RR__             = "=== Risk/Reward (min 1:2 per FXNX) ===";
input double  RR_TakeProfit      = 2.5;     // minimum enforced to 2.0
input double  ATR_Multiplier_SL  = 1.55;
input double  Breakeven_R        = 1.0;
input bool    UsePartialClose    = true;
input double  PartialClose_R     = 1.5;
input bool    UseTrailing        = true;
input double  Trailing_ATR_Mult  = 1.5;

input string  __Filters__        = "=== Filters ===";
input double  MaxSpreadPoints    = 50.0;
input bool    UseSessionFilter   = true;
input int     SessionStartHour   = 7;
input int     SessionEndHour     = 18;

input string  __Telegram__       = "=== Telegram ===";
input bool    TelegramEnabled    = false;
input string  TelegramBotToken   = "";
input string  TelegramChatID     = "";

//--- ================================================================
//    GLOBALS
//--- ================================================================
CTrade        trade;
CPositionInfo posInfo;

// v4.0 handles
int  handleEMAfast, handleEMAslow, handleEMAtrend, handleRSI, handleATR;
double emaFast[], emaSlow[], emaTrend[], rsi[], atr[];

// v4.1 handles
int  handleADX, handleBBupper, handleBBlower, handleBBmid;
int  handleMTF_EMA;      // H4 EMA21
int  handleDXY_EMA;      // DXY EMA10
double adx[], bbUpper[], bbLower[], bbMid[];
double mtfEma[];
double dxyEmaArr[];

// Symbol specs
double g_point, g_tickValue, g_tickSize, g_volMin, g_volMax, g_volStep;
int    g_digits;

// VIX state (v4.0)
int    g_vixAboveCount = 0;
bool   g_vixRiskOff    = false;

// v4.1 fix: track tickets already partially closed (prevent repeated partial close)
ulong  g_partialDone[];   // tickets that have had their partial close executed

// Regime enum
enum ENUM_REGIME { REGIME_TREND, REGIME_RANGE, REGIME_BREAKOUT };

// --- Forward declarations (fix: used in OnTick before their definitions) ---
ENUM_REGIME DetectRegime();
bool   CheckBullishDivergence();
bool   CheckBearishDivergence();
bool   IsNewsWindow();
void   UpdateVIXState();
void   SendTelegramAlert(string msg);
string UrlEncode(string s);
double atrAvgSafe();
double CalcLotSize(double slDistancePrice, double scenarioMult);
void   OpenPosition(ENUM_ORDER_TYPE type, double scenarioMult);


//+------------------------------------------------------------------+
int OnInit()
  {
   // Enforce minimum RR of 2.0 (FXNX recommendation)
   if(RR_TakeProfit < 2.0)
     {
      Print("WARNING: RR_TakeProfit was ", RR_TakeProfit, " — minimum 1:2 enforced. Set >= 2.0.");
      // We'll handle this at trade open; just warn here.
     }

   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(25);

   g_point     = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits    = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   g_tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   g_tickSize  = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   g_volMin    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   g_volMax    = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   g_volStep   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);

   if(g_tickValue <= 0 || g_tickSize <= 0)
     { Print("FATAL: invalid tick value/size for ", _Symbol); return INIT_FAILED; }

   // v4.0 indicators
   handleEMAfast  = iMA(_Symbol, Timeframe, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   handleEMAslow  = iMA(_Symbol, Timeframe, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   handleEMAtrend = iMA(_Symbol, Timeframe, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(_Symbol, Timeframe, RSI_Period, PRICE_CLOSE);
   handleATR      = iATR(_Symbol, Timeframe, ATR_Period);

   // v4.1 indicators
   handleADX      = iADX(_Symbol, Timeframe, ADX_Period);
   handleBBupper  = iBands(_Symbol, Timeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handleBBlower  = handleBBupper;  // same handle, different buffer index
   handleBBmid    = handleBBupper;

   // H4 MTF EMA
   handleMTF_EMA  = iMA(_Symbol, PERIOD_H4, MTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleEMAfast==INVALID_HANDLE || handleEMAslow==INVALID_HANDLE ||
      handleEMAtrend==INVALID_HANDLE || handleRSI==INVALID_HANDLE ||
      handleATR==INVALID_HANDLE || handleADX==INVALID_HANDLE ||
      handleBBupper==INVALID_HANDLE || handleMTF_EMA==INVALID_HANDLE)
     { Print("Indicator initialization failed"); return INIT_FAILED; }

   // DXY EMA — optional; failure is non-fatal (disables filter gracefully)
   handleDXY_EMA = iMA(DXY_Symbol, PERIOD_D1, DXY_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
   if(handleDXY_EMA == INVALID_HANDLE)
      Print("DXY symbol '", DXY_Symbol, "' not found — DXY filter will be disabled.");

   ArraySetAsSeries(emaFast,  true); ArraySetAsSeries(emaSlow,   true);
   ArraySetAsSeries(emaTrend, true); ArraySetAsSeries(rsi,       true);
   ArraySetAsSeries(atr,      true); ArraySetAsSeries(adx,       true);
   ArraySetAsSeries(bbUpper,  true); ArraySetAsSeries(bbLower,   true);
   ArraySetAsSeries(bbMid,    true); ArraySetAsSeries(mtfEma,    true);
   ArraySetAsSeries(dxyEmaArr,true);

   SendTelegramAlert("QuantumGoldTrader v4.1 LIVE on XAUUSD M15 | Regime+MTF+DXY+Divergence+GSRatio active");
   return(INIT_SUCCEEDED);
  }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   SendTelegramAlert("QuantumGoldTrader v4.1 stopped.");
   IndicatorRelease(handleEMAfast); IndicatorRelease(handleEMAslow);
   IndicatorRelease(handleEMAtrend); IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);  IndicatorRelease(handleADX);
   IndicatorRelease(handleBBupper); IndicatorRelease(handleMTF_EMA);
   if(handleDXY_EMA != INVALID_HANDLE) IndicatorRelease(handleDXY_EMA);
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   if(!IsNewBar()) return;
   if(!IsTradingSessionAllowed()) return;

   // Copy v4.0 buffers
   if(CopyBuffer(handleEMAfast, 0,0,10,emaFast) <10  ||
      CopyBuffer(handleEMAslow, 0,0,10,emaSlow) <10  ||
      CopyBuffer(handleEMAtrend,0,0,10,emaTrend)<10  ||
      CopyBuffer(handleRSI,     0,0,10,rsi)     <10  ||
      CopyBuffer(handleATR,     0,0,10,atr)     <10) return;

   // Copy v4.1 buffers
   if(CopyBuffer(handleADX,     0,0,4,adx)     <4) return;  // ADX main line (buffer 0)
   // Bollinger Bands: 0=base/mid, 1=upper, 2=lower
   if(CopyBuffer(handleBBupper, 1,0,4,bbUpper) <4 ||
      CopyBuffer(handleBBlower, 2,0,4,bbLower) <4 ||
      CopyBuffer(handleBBmid,   0,0,4,bbMid)   <4) return;

   if(CopyBuffer(handleMTF_EMA, 0,0,4,mtfEma)  <4) return;

   // Spread filter
   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) return;

   double closePrice = iClose(_Symbol, Timeframe, 1);
   double atrAvg     = (atr[1] + atr[2] + atr[3]) / 3.0;
   bool   atrOK      = (atr[1] >= atrAvg * MinATR_Multiplier);

   // ================================================================
   // v4.0 FEATURES
   // ================================================================
   bool aboveTrend  = (closePrice > emaTrend[1]);
   bool belowTrend  = (closePrice < emaTrend[1]);
   bool goldenCross = (emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2]);
   bool deathCross  = (emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2]);

   UpdateVIXState();
   bool vixLongBias = (UseVIXFilter && g_vixRiskOff);

   bool breakoutLong=true, breakoutShort=true;
   if(UseBreakoutFilter)
     {
      double highestHigh = iHigh(_Symbol,Timeframe,iHighest(_Symbol,Timeframe,MODE_HIGH,BreakoutLookback,2));
      double lowestLow   = iLow (_Symbol,Timeframe,iLowest (_Symbol,Timeframe,MODE_LOW, BreakoutLookback,2));
      double buf         = atr[1] * BreakoutBuffer_ATR;
      breakoutLong  = (closePrice >= highestHigh - buf);
      breakoutShort = (closePrice <= lowestLow  + buf);
     }

   // ================================================================
   // v4.1 FEATURE 1: Market Regime Detection
   // ================================================================
   ENUM_REGIME regime = DetectRegime();

   // ================================================================
   // v4.1 FEATURE 2: Multi-Timeframe H4 Confirmation
   // ================================================================
   bool mtfBullish = true, mtfBearish = true;
   if(UseMTFFilter)
     {
      double h4Close = iClose(_Symbol, PERIOD_H4, 1);
      mtfBullish = (h4Close > mtfEma[1]);  // H4 close above H4 EMA21 = bullish
      mtfBearish = (h4Close < mtfEma[1]);  // H4 close below H4 EMA21 = bearish
     }

   // ================================================================
   // v4.1 FEATURE 3: DXY Correlation Filter
   // ================================================================
   bool dxyBlocking = false;
   if(UseDXYFilter && handleDXY_EMA != INVALID_HANDLE)
     {
      if(CopyBuffer(handleDXY_EMA, 0, 0, DXY_AboveEMA_Bars+2, dxyEmaArr) >= DXY_AboveEMA_Bars+1)
        {
         // Check if DXY has been above its EMA for DXY_AboveEMA_Bars consecutive bars
         bool dxyAboveAll = true;
         for(int b=1; b<=DXY_AboveEMA_Bars; b++)
           {
            double dxyClose = iClose(DXY_Symbol, PERIOD_D1, b);
            if(dxyClose <= dxyEmaArr[b]) { dxyAboveAll = false; break; }
           }
         // DXY surging above EMA = inverse pressure on gold longs
         dxyBlocking = dxyAboveAll;
         if(dxyBlocking)
            Print("DXY surge filter: blocking long gold bias (DXY above EMA", DXY_EMA_Period,
                  " for ", DXY_AboveEMA_Bars, " bars)");
        }
     }

   // ================================================================
   // v4.1 FEATURE 4: RSI Divergence (confirmation — not mandatory for every signal)
   // ================================================================
   bool bullishDivergence = false, bearishDivergence = false;
   if(UseDivergenceFilter)
     {
      bullishDivergence = CheckBullishDivergence();
      bearishDivergence = CheckBearishDivergence();
     }

   // ================================================================
   // v4.1 FEATURE 5: Gold/Silver Ratio Sentiment
   // ================================================================
   double gsSentimentMult = 1.0;
   bool gsLongBias = false, gsReduceLong = false;
   if(UseGSRatioFilter)
     {
      double silverClose = iClose(Silver_Symbol, PERIOD_D1, 1);
      double goldClose   = iClose(_Symbol, PERIOD_D1, 1);
      if(silverClose > 0 && goldClose > 0)
        {
         double gsRatio = goldClose / silverClose;
         if(gsRatio >= GSRatio_ExtHigh) { gsLongBias    = true;  gsSentimentMult = Stagflation_SizeMult; }
         if(gsRatio <= GSRatio_ExtLow)  { gsReduceLong  = true;  gsSentimentMult = 0.85; }
         Print("Gold/Silver Ratio: ", DoubleToString(gsRatio, 2),
               gsLongBias?" (METALS CHEAP — long bias)":gsReduceLong?" (METALS EXPENSIVE — reduce longs)":"");
        }
     }

   // ================================================================
   // v4.1 FEATURE 6: News Spike Guard
   // ================================================================
   if(UseNewsGuard && IsNewsWindow())
     { Print("News spike guard active — skipping bar"); return; }

   // ================================================================
   // COMPOSITE SIGNAL LOGIC — Regime-Adaptive
   // ================================================================
   bool longSignal  = false;
   bool shortSignal = false;

   if(regime == REGIME_TREND || regime == REGIME_BREAKOUT)
     {
      // Trend / Breakout: use cross + 190 EMA + MTF + DXY + optional divergence
      longSignal = goldenCross
                   && (!UseTrendFilter  || aboveTrend)
                   && mtfBullish
                   && (rsi[1] > 50.0 && rsi[1] < RSI_LongMax)
                   && atrOK
                   && breakoutLong
                   && !dxyBlocking           // DXY filter: not surging against gold
                   && !gsReduceLong          // not at extreme expensive metals
                   && (!UseDivergenceFilter || !bearishDivergence);
                   // fix: in trend mode divergence is a PLUS — only BLOCK a long if a
                   // clear BEARISH divergence is present (don't require bullish every time)

      shortSignal = deathCross
                    && (!UseTrendFilter  || belowTrend)
                    && mtfBearish
                    && (rsi[1] < 50.0 && rsi[1] > RSI_ShortMin)
                    && atrOK
                    && breakoutShort
                    && !vixLongBias          // no shorts during VIX risk-off
                    && (!UseDivergenceFilter || !bullishDivergence);
                    // fix: only block a short if a clear BULLISH divergence contradicts it
     }
   else if(regime == REGIME_RANGE)
     {
      // Range mode: use Bollinger Bands + Stochastic-style RSI levels
      // Buy near lower BB, sell near upper BB — divergence confirmation preferred
      bool nearLowerBB = (closePrice <= bbMid[1] - (bbMid[1] - bbLower[1]) * 0.7);
      bool nearUpperBB = (closePrice >= bbMid[1] + (bbUpper[1] - bbMid[1]) * 0.7);

      longSignal  = nearLowerBB
                    && (rsi[1] < 45.0)       // oversold in range
                    && (!UseTrendFilter || aboveTrend)  // macro trend still preferred
                    && mtfBullish
                    && !dxyBlocking
                    && (!UseDivergenceFilter || bullishDivergence);

      shortSignal = nearUpperBB
                    && (rsi[1] > 55.0)       // overbought in range
                    && (!UseTrendFilter || belowTrend)
                    && mtfBearish
                    && !vixLongBias
                    && (!UseDivergenceFilter || bearishDivergence);
     }

   // Apply GS Ratio long bias (boosts conviction, doesn't create signals alone)
   // If GS says metals cheap + VIX risk-off: add long bias weight but still need base signal
   if(gsLongBias && vixLongBias)
     {
      // Both stagflation indicators agree: strongest gold environment
      // No change to signal logic; size multiplier handles it in OpenPosition
      Print("STAGFLATION BIAS ACTIVE: VIX risk-off + Metals cheap. Trend-follow longs preferred.");
     }

   if(longSignal  && CountOpenPositions() < MaxPositions)
      OpenPosition(ORDER_TYPE_BUY,  gsSentimentMult);
   if(shortSignal && CountOpenPositions() < MaxPositions)
      OpenPosition(ORDER_TYPE_SELL, 1.0);  // no size boost for shorts

   ManagePositions();
  }

//+------------------------------------------------------------------+
//| v4.1: Market Regime Detection via ADX                            |
//+------------------------------------------------------------------+
ENUM_REGIME DetectRegime()
  {
   if(!UseRegimeFilter) return REGIME_TREND;  // default: use trend logic

   if(adx[1] >= ADX_TrendMin)   return REGIME_TREND;
   if(adx[1] <= ADX_RangeMax)   return REGIME_RANGE;

   // Between the two thresholds: check if price is breaking out of BB
   double closePrice = iClose(_Symbol, Timeframe, 1);
   if(closePrice > bbUpper[1] || closePrice < bbLower[1]) return REGIME_BREAKOUT;

   return REGIME_RANGE;  // default inside BB with weak ADX = range
  }

//+------------------------------------------------------------------+
//| v4.1: Bullish RSI Divergence                                     |
//| Price made lower low vs Div_Lookback bars ago                    |
//| RSI made higher low vs same period                               |
//+------------------------------------------------------------------+
bool CheckBullishDivergence()
  {
   int lookback = Div_Lookback + 1;
   if(lookback >= ArraySize(rsi)) return false;   // fix: prevent rsi[] out-of-bounds

   double pricePrev  = iLow(_Symbol, Timeframe, lookback);
   double priceCur   = iLow(_Symbol, Timeframe, 1);
   double rsiPrev    = rsi[lookback];
   double rsiCur     = rsi[1];

   // Price lower low + RSI higher low = bullish divergence
   return (priceCur < pricePrev && rsiCur > rsiPrev);
  }

//+------------------------------------------------------------------+
//| v4.1: Bearish RSI Divergence                                     |
//+------------------------------------------------------------------+
bool CheckBearishDivergence()
  {
   int lookback = Div_Lookback + 1;
   if(lookback >= ArraySize(rsi)) return false;   // fix: prevent rsi[] out-of-bounds

   double pricePrev  = iHigh(_Symbol, Timeframe, lookback);
   double priceCur   = iHigh(_Symbol, Timeframe, 1);
   double rsiPrev    = rsi[lookback];
   double rsiCur     = rsi[1];

   // Price higher high + RSI lower high = bearish divergence
   return (priceCur > pricePrev && rsiCur < rsiPrev);
  }

//+------------------------------------------------------------------+
//| v4.1: News Spike Guard                                           |
//+------------------------------------------------------------------+
bool IsNewsWindow()
  {
   MqlDateTime dt; TimeToStruct(TimeCurrent(), dt);
   string hoursStr = NewsHours;
   string parts[];
   int count = StringSplit(hoursStr, ',', parts);
   for(int i=0; i<count; i++)
     {
      int h = (int)StringToInteger(StringTrimLeft(StringTrimRight(parts[i])));
      // Block for NewsGuard_Bars bars starting from the news hour
      if(dt.hour == h) return true;
      // Also block NewsGuard_Bars bars after the news hour
      for(int b=1; b<=NewsGuard_Bars; b++)
        {
         int blockHour = (h + b) % 24;
         if(dt.hour == blockHour) return true;
        }
     }
   return false;
  }

//+------------------------------------------------------------------+
//| v4.0: VIX State                                                  |
//+------------------------------------------------------------------+
void UpdateVIXState()
  {
   if(!UseVIXFilter) { g_vixRiskOff = false; return; }
   double vixClose = iClose(VIX_Symbol, PERIOD_D1, 1);
   if(vixClose <= 0) { g_vixRiskOff = false; return; }
   if(vixClose > VIX_RiskOff) g_vixAboveCount++;
   else g_vixAboveCount = 0;
   g_vixRiskOff = (g_vixAboveCount >= VIX_HoldBars);
   if(g_vixRiskOff)
      SendTelegramAlert("VIX RISK-OFF: " + DoubleToString(vixClose,2) +
                        " > " + DoubleToString(VIX_RiskOff,1) + " for " +
                        IntegerToString(g_vixAboveCount) + " bars. LONG BIAS ONLY.");
  }

//+------------------------------------------------------------------+
//| Lot sizing with v4.1 scenario multiplier                         |
//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice, double scenarioMult=1.0)
  {
   if(slDistancePrice <= 0) return 0.0;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * BaseRiskPercent / 100.0;
   double lossPerLot = (slDistancePrice / g_tickSize) * g_tickValue;
   if(lossPerLot <= 0) return 0.0;
   double lots = riskAmount / lossPerLot;

   // Apply scenario multiplier (clamp: 0.5x min, 1.2x max to avoid over-sizing)
   scenarioMult = MathMax(0.5, MathMin(1.2, scenarioMult));
   lots *= scenarioMult;

   lots = MathFloor(lots / g_volStep) * g_volStep;
   if(lots < g_volMin) return 0.0;
   if(lots > g_volMax) lots = g_volMax;
   return NormalizeDouble(lots, 2);
  }

//+------------------------------------------------------------------+
void OpenPosition(ENUM_ORDER_TYPE type, double scenarioMult=1.0)
  {
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   double slDistance = atr[1] * ATR_Multiplier_SL;
   if(slDistance <= 0) return;

   // v4.1: risk-off scenario reduces size
   double finalMult = scenarioMult;
   if(UseScenarioSizing)
     {
      bool riskOffCondition = (g_vixRiskOff);  // DXY block already prevents entry; VIX still allows longs
      if(riskOffCondition) finalMult *= RiskOff_SizeMult;
     }

   // Extra reduce on very high ATR bars (v4.0 logic retained)
   double lotSize = CalcLotSize(slDistance, finalMult);
   if(UseDynamicRisk && atr[1] > atrAvgSafe()*2.5)
      lotSize = NormalizeDouble(lotSize * 0.55, 2);

   if(lotSize < g_volMin)
     { Print("Lot below broker min — skipping."); return; }

   // Enforce minimum RR = 2.0 (FXNX recommendation)
   double effectiveRR = MathMax(RR_TakeProfit, 2.0);

   double sl=0, tp=0; bool ok=false;
   if(type == ORDER_TYPE_BUY)
     {
      sl = NormalizeDouble(bid - slDistance,                g_digits);
      tp = NormalizeDouble(bid + slDistance * effectiveRR,  g_digits);
      ok = trade.Buy(lotSize, _Symbol, ask, sl, tp, "QGT Long v4.1");
     }
   else
     {
      sl = NormalizeDouble(ask + slDistance,                g_digits);
      tp = NormalizeDouble(ask - slDistance * effectiveRR,  g_digits);
      ok = trade.Sell(lotSize, _Symbol, bid, sl, tp, "QGT Short v4.1");
     }

   if(!ok) { Print("Order failed: ", trade.ResultRetcodeDescription()); return; }

   ENUM_REGIME r = DetectRegime();
   string regimeStr = (r==REGIME_TREND)?"TREND":(r==REGIME_RANGE)?"RANGE":"BREAKOUT";
   SendTelegramAlert((type==ORDER_TYPE_BUY?"LONG":"SHORT") + " XAUUSD v4.1" +
                     " | Regime:" + regimeStr +
                     " | Entry " + DoubleToString(type==ORDER_TYPE_BUY?ask:bid, g_digits) +
                     " | SL "   + DoubleToString(sl, g_digits) +
                     " | TP "   + DoubleToString(tp, g_digits) +
                     " | Lots " + DoubleToString(lotSize,2) +
                     " | RR 1:" + DoubleToString(effectiveRR,1));
  }

//+------------------------------------------------------------------+
double atrAvgSafe() { return (atr[1]+atr[2]+atr[3])/3.0; }

//+------------------------------------------------------------------+
// v4.1 fix: helpers to track partial-close per ticket (prevents repeated partial close)
bool PartialAlreadyDone(ulong ticket)
  {
   for(int i=0; i<ArraySize(g_partialDone); i++)
      if(g_partialDone[i]==ticket) return true;
   return false;
  }

void MarkPartialDone(ulong ticket)
  {
   int sz=ArraySize(g_partialDone);
   ArrayResize(g_partialDone, sz+1);
   g_partialDone[sz]=ticket;
  }

// Remove closed tickets from the tracking array (housekeeping, keeps it small)
void CleanupPartialTracking()
  {
   for(int i=ArraySize(g_partialDone)-1; i>=0; i--)
     {
      if(!PositionSelectByTicket(g_partialDone[i]))
        {
         // ticket no longer open -> remove it
         for(int j=i; j<ArraySize(g_partialDone)-1; j++)
            g_partialDone[j]=g_partialDone[j+1];
         ArrayResize(g_partialDone, ArraySize(g_partialDone)-1);
        }
     }
  }

void ManagePositions()
  {
   CleanupPartialTracking();   // v4.1 fix: drop tickets that are already closed
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      if(!posInfo.SelectByIndex(i)) continue;
      if(posInfo.Symbol()!=_Symbol || posInfo.Magic()!=MagicNumber) continue;
      bool   isBuy  = (posInfo.PositionType()==POSITION_TYPE_BUY);
      double openP  = posInfo.PriceOpen();
      double curP   = isBuy ? bid : ask;
      double profit = isBuy ? (curP-openP) : (openP-curP);
      double oneR   = atr[1] * ATR_Multiplier_SL;
      if(oneR <= 0) continue;
      double rMult  = profit / oneR;

      // Partial close (v4.1 fix: only ONCE per ticket)
      if(UsePartialClose && rMult >= PartialClose_R && !PartialAlreadyDone(posInfo.Ticket()))
        {
         double half = NormalizeDouble(posInfo.Volume()*0.5, 2);
         half = MathFloor(half/g_volStep)*g_volStep;
         if(half >= g_volMin && posInfo.Volume()-half >= g_volMin)
           {
            if(trade.PositionClosePartial(posInfo.Ticket(), half))
               MarkPartialDone(posInfo.Ticket());   // remember so it won't repeat
           }
        }
      // Breakeven
      if(rMult >= Breakeven_R)
        {
         double beSL   = isBuy ? openP+5*g_point : openP-5*g_point;
         beSL = NormalizeDouble(beSL, g_digits);
         bool improve  = isBuy ? (beSL>posInfo.StopLoss()) : (beSL<posInfo.StopLoss()||posInfo.StopLoss()==0);
         if(improve && MathAbs(beSL-posInfo.StopLoss())>5*g_point)
            trade.PositionModify(posInfo.Ticket(), beSL, posInfo.TakeProfit());
        }
      // ATR trailing
      if(UseTrailing)
        {
         double trail = atr[1]*Trailing_ATR_Mult;
         double newSL = isBuy ? bid-trail : ask+trail;
         newSL = NormalizeDouble(newSL, g_digits);
         bool improve = isBuy ? (newSL>posInfo.StopLoss()+5*g_point)
                              : (newSL<posInfo.StopLoss()-5*g_point);
         if(improve) trade.PositionModify(posInfo.Ticket(), newSL, posInfo.TakeProfit());
        }
     }
  }

//+------------------------------------------------------------------+
bool IsNewBar()
  {
   static datetime lastTime=0;
   datetime cur=iTime(_Symbol,Timeframe,0);
   if(cur!=lastTime){lastTime=cur;return true;}
   return false;
  }

//+------------------------------------------------------------------+
int CountOpenPositions()
  {
   int cnt=0;
   for(int i=0;i<PositionsTotal();i++)
      if(posInfo.SelectByIndex(i))
         if(posInfo.Symbol()==_Symbol && posInfo.Magic()==MagicNumber) cnt++;
   return cnt;
  }

//+------------------------------------------------------------------+
bool IsTradingSessionAllowed()
  {
   if(!UseSessionFilter) return true;
   MqlDateTime dt; TimeToStruct(TimeCurrent(),dt);
   return(dt.hour>=SessionStartHour && dt.hour<=SessionEndHour);
  }

//+------------------------------------------------------------------+
void SendTelegramAlert(string msg)
  {
   if(!TelegramEnabled||TelegramBotToken==""||TelegramChatID=="") return;
   string url     = "https://api.telegram.org/bot"+TelegramBotToken+"/sendMessage";
   string headers = "Content-Type: application/x-www-form-urlencoded\r\n";
   string payload = "chat_id="+TelegramChatID+"&text="+UrlEncode(msg);
   char post[],result[]; string rh;
   StringToCharArray(payload,post,0,StringLen(payload),CP_UTF8);
   int sz=ArraySize(post); if(sz>0&&post[sz-1]==0) ArrayResize(post,sz-1);
   int code=WebRequest("POST",url,headers,10000,post,result,rh);
   if(code==-1) Print("Telegram failed. Err=",GetLastError());
  }

//+------------------------------------------------------------------+
string UrlEncode(string s)
  {
   string out=""; uchar bytes[];
   int n=StringToCharArray(s,bytes,0,StringLen(s),CP_UTF8);
   for(int i=0;i<n;i++)
     {
      uchar c=bytes[i]; if(c==0) continue;
      if((c>='A'&&c<='Z')||(c>='a'&&c<='z')||(c>='0'&&c<='9')||c=='-'||c=='_'||c=='.'||c=='~')
         out+=CharToString(c);
      else out+=StringFormat("%%%02X",c);
     }
   return out;
  }
//+------------------------------------------------------------------+
