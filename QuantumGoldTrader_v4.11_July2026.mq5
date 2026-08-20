//+------------------------------------------------------------------+
//|                          QuantumGoldTrader_v4.11_Fixed.mq5       |
//|          v4.11 Fixed — Robust symbol handling (VIX/DXY/XAGUSD)   |
//+------------------------------------------------------------------+
#property copyright "QuantumGoldTrader v4.11 Fixed"
#property version   "4.12"
#property strict
#property description "Quantum Gold Trader v4.11 Fixed - Adaptive XAUUSD Strategy (symbols safe)"

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>
#include <Trade\SymbolInfo.mqh>

//--- INPUTS
input string  __General__        = "=== General Settings ===";
input ulong   MagicNumber        = 20260411;
input double  BaseRiskPercent    = 0.65;
input int     MaxPositions       = 2;
input bool    UseDynamicRisk     = true;

input string  __Strategy__       = "=== Core Strategy ===";
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

input string  __RegimeDetect__   = "=== Market Regime Detection ===";
input bool    UseRegimeFilter    = true;
input int     ADX_Period         = 14;
input double  ADX_TrendMin       = 23.5;
input double  ADX_RangeMax       = 21.0;
input int     BB_Period          = 20;
input double  BB_Deviation       = 2.0;

input string  __MTF__            = "=== Multi-Timeframe H4 Confirmation ===";
input bool    UseMTFFilter       = true;
input int     MTF_EMA_Period     = 21;

input string  __DXY__            = "=== DXY Correlation Filter ===";
input bool    UseDXYFilter       = true;
input string  DXY_Symbol         = "USDX";          // try also "DX-Y.NYB" or "DXY" depending on broker
input int     DXY_EMA_Period     = 10;
input int     DXY_AboveEMA_Bars  = 2;

input string  __Divergence__     = "=== RSI Divergence Confirmation ===";
input bool    UseDivergenceFilter = true;
input int     Div_Lookback       = 5;

input string  __GoldSilver__     = "=== Gold/Silver Ratio Sentiment ===";
input bool    UseGSRatioFilter   = true;
input string  Silver_Symbol      = "XAGUSD";
input double  GSRatio_ExtHigh    = 88.0;
input double  GSRatio_ExtLow     = 70.0;

input string  __NewsGuard__      = "=== News Spike Guard ===";
input bool    UseNewsGuard       = true;
input string  NewsHours          = "14,15,20,21";
input int     NewsGuard_Bars     = 3;

input string  __ScenarioRisk__   = "=== Scenario-Based Position Sizing ===";
input bool    UseScenarioSizing  = true;
input double  RiskOff_SizeMult   = 0.6;
input double  Stagflation_SizeMult = 1.15;

input string  __RR__             = "=== Risk/Reward ===";
input double  RR_TakeProfit      = 2.5;
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

//--- GLOBALS
CTrade        trade;
CPositionInfo posInfo;

int  handleEMAfast, handleEMAslow, handleEMAtrend, handleRSI, handleATR;
int  handleADX, handleBB, handleMTF_EMA, handleDXY_EMA;

double emaFast[], emaSlow[], emaTrend[], rsi[], atr[];
double adx[], bbUpper[], bbLower[], bbMid[], mtfEma[], dxyEmaArr[];

double g_point, g_tickValue, g_tickSize, g_volMin, g_volMax, g_volStep;
int    g_digits;

int    g_vixAboveCount = 0;
bool   g_vixRiskOff    = false;
bool   g_vixAvailable  = false;
bool   g_dxyAvailable  = false;
bool   g_silverAvailable = false;

ulong  g_partialDone[];

enum ENUM_REGIME { REGIME_TREND, REGIME_RANGE, REGIME_BREAKOUT };

// Forward declarations
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
   if(RR_TakeProfit < 2.0)
      Print("WARNING: RR_TakeProfit < 2.0 — minimum 1:2 will be enforced.");

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
   {
      Print("FATAL: invalid tick value/size for ", _Symbol);
      return INIT_FAILED;
   }

   // Core indicators
   handleEMAfast  = iMA(_Symbol, Timeframe, EMA_Fast,  0, MODE_EMA, PRICE_CLOSE);
   handleEMAslow  = iMA(_Symbol, Timeframe, EMA_Slow,  0, MODE_EMA, PRICE_CLOSE);
   handleEMAtrend = iMA(_Symbol, Timeframe, EMA_Trend, 0, MODE_EMA, PRICE_CLOSE);
   handleRSI      = iRSI(_Symbol, Timeframe, RSI_Period, PRICE_CLOSE);
   handleATR      = iATR(_Symbol, Timeframe, ATR_Period);
   handleADX      = iADX(_Symbol, Timeframe, ADX_Period);
   handleBB       = iBands(_Symbol, Timeframe, BB_Period, 0, BB_Deviation, PRICE_CLOSE);
   handleMTF_EMA  = iMA(_Symbol, PERIOD_H4, MTF_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);

   if(handleEMAfast==INVALID_HANDLE || handleEMAslow==INVALID_HANDLE ||
      handleEMAtrend==INVALID_HANDLE || handleRSI==INVALID_HANDLE ||
      handleATR==INVALID_HANDLE || handleADX==INVALID_HANDLE ||
      handleBB==INVALID_HANDLE || handleMTF_EMA==INVALID_HANDLE)
   {
      Print("Core indicator initialization failed");
      return INIT_FAILED;
   }

   // --- Optional symbols (safe handling) ---
   // DXY
   handleDXY_EMA = INVALID_HANDLE;
   if(UseDXYFilter)
   {
      if(SymbolSelect(DXY_Symbol, true))
      {
         handleDXY_EMA = iMA(DXY_Symbol, PERIOD_D1, DXY_EMA_Period, 0, MODE_EMA, PRICE_CLOSE);
         if(handleDXY_EMA != INVALID_HANDLE)
         {
            g_dxyAvailable = true;
            Print("DXY filter enabled using symbol: ", DXY_Symbol);
         }
      }
      if(!g_dxyAvailable)
         Print("DXY symbol '", DXY_Symbol, "' not available → DXY filter DISABLED");
   }

   // VIX
   g_vixAvailable = false;
   if(UseVIXFilter)
   {
      if(SymbolSelect(VIX_Symbol, true))
      {
         double test = iClose(VIX_Symbol, PERIOD_D1, 1);
         if(test > 0)
         {
            g_vixAvailable = true;
            Print("VIX filter enabled using symbol: ", VIX_Symbol);
         }
      }
      if(!g_vixAvailable)
         Print("VIX symbol '", VIX_Symbol, "' not available → VIX filter DISABLED");
   }

   // Silver (XAGUSD)
   g_silverAvailable = false;
   if(UseGSRatioFilter)
   {
      if(SymbolSelect(Silver_Symbol, true))
      {
         double test = iClose(Silver_Symbol, PERIOD_D1, 1);
         if(test > 0)
         {
            g_silverAvailable = true;
            Print("Gold/Silver filter enabled using symbol: ", Silver_Symbol);
         }
      }
      if(!g_silverAvailable)
         Print("Silver symbol '", Silver_Symbol, "' not available → Gold/Silver filter DISABLED");
   }

   ArraySetAsSeries(emaFast, true);  ArraySetAsSeries(emaSlow, true);
   ArraySetAsSeries(emaTrend, true); ArraySetAsSeries(rsi, true);
   ArraySetAsSeries(atr, true);      ArraySetAsSeries(adx, true);
   ArraySetAsSeries(bbUpper, true);  ArraySetAsSeries(bbLower, true);
   ArraySetAsSeries(bbMid, true);    ArraySetAsSeries(mtfEma, true);
   ArraySetAsSeries(dxyEmaArr, true);

   SendTelegramAlert("QuantumGoldTrader v4.11 Fixed started on " + _Symbol);
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   SendTelegramAlert("QuantumGoldTrader v4.11 Fixed stopped.");
   IndicatorRelease(handleEMAfast);
   IndicatorRelease(handleEMAslow);
   IndicatorRelease(handleEMAtrend);
   IndicatorRelease(handleRSI);
   IndicatorRelease(handleATR);
   IndicatorRelease(handleADX);
   IndicatorRelease(handleBB);
   IndicatorRelease(handleMTF_EMA);
   if(handleDXY_EMA != INVALID_HANDLE) IndicatorRelease(handleDXY_EMA);
}

//+------------------------------------------------------------------+
void OnTick()
{
   if(!IsNewBar()) return;
   if(!IsTradingSessionAllowed()) return;

   if(CopyBuffer(handleEMAfast, 0,0,10,emaFast)  < 10) return;
   if(CopyBuffer(handleEMAslow, 0,0,10,emaSlow)  < 10) return;
   if(CopyBuffer(handleEMAtrend,0,0,10,emaTrend) < 10) return;
   if(CopyBuffer(handleRSI,     0,0,10,rsi)      < 10) return;
   if(CopyBuffer(handleATR,     0,0,10,atr)      < 10) return;
   if(CopyBuffer(handleADX,     0,0,4,adx)       < 4)  return;
   if(CopyBuffer(handleBB,      1,0,4,bbUpper)   < 4)  return;
   if(CopyBuffer(handleBB,      2,0,4,bbLower)   < 4)  return;
   if(CopyBuffer(handleBB,      0,0,4,bbMid)     < 4)  return;
   if(CopyBuffer(handleMTF_EMA, 0,0,4,mtfEma)    < 4)  return;

   double spread = (double)SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpreadPoints) return;

   double closePrice = iClose(_Symbol, Timeframe, 1);
   double atrAvg     = (atr[1] + atr[2] + atr[3]) / 3.0;
   bool   atrOK      = (atr[1] >= atrAvg * MinATR_Multiplier);

   bool aboveTrend  = (closePrice > emaTrend[1]);
   bool belowTrend  = (closePrice < emaTrend[1]);
   bool goldenCross = (emaFast[1] > emaSlow[1] && emaFast[2] <= emaSlow[2]);
   bool deathCross  = (emaFast[1] < emaSlow[1] && emaFast[2] >= emaSlow[2]);

   UpdateVIXState();

   bool breakoutLong = true, breakoutShort = true;
   if(UseBreakoutFilter)
   {
      double highestHigh = iHigh(_Symbol, Timeframe, iHighest(_Symbol, Timeframe, MODE_HIGH, BreakoutLookback, 2));
      double lowestLow   = iLow (_Symbol, Timeframe, iLowest (_Symbol, Timeframe, MODE_LOW,  BreakoutLookback, 2));
      double buf         = atr[1] * BreakoutBuffer_ATR;
      breakoutLong  = (closePrice >= highestHigh - buf);
      breakoutShort = (closePrice <= lowestLow  + buf);
   }

   ENUM_REGIME regime = DetectRegime();

   bool mtfBullish = true, mtfBearish = true;
   if(UseMTFFilter)
   {
      double h4Close = iClose(_Symbol, PERIOD_H4, 1);
      mtfBullish = (h4Close > mtfEma[1]);
      mtfBearish = (h4Close < mtfEma[1]);
   }

   // DXY filter (safe)
   bool dxyBlocking = false;
   if(UseDXYFilter && g_dxyAvailable && handleDXY_EMA != INVALID_HANDLE)
   {
      if(CopyBuffer(handleDXY_EMA, 0, 0, DXY_AboveEMA_Bars+2, dxyEmaArr) >= DXY_AboveEMA_Bars+1)
      {
         bool dxyAboveAll = true;
         for(int b=1; b<=DXY_AboveEMA_Bars; b++)
         {
            double dxyClose = iClose(DXY_Symbol, PERIOD_D1, b);
            if(dxyClose <= 0 || dxyClose <= dxyEmaArr[b]) { dxyAboveAll = false; break; }
         }
         dxyBlocking = dxyAboveAll;
      }
   }

   bool bullishDivergence = false, bearishDivergence = false;
   if(UseDivergenceFilter)
   {
      bullishDivergence = CheckBullishDivergence();
      bearishDivergence = CheckBearishDivergence();
   }

   // Gold/Silver ratio (safe)
   double gsSentimentMult = 1.0;
   bool gsLongBias = false, gsReduceLong = false;
   if(UseGSRatioFilter && g_silverAvailable)
   {
      double silverClose = iClose(Silver_Symbol, PERIOD_D1, 1);
      double goldClose   = iClose(_Symbol, PERIOD_D1, 1);
      if(silverClose > 0 && goldClose > 0)
      {
         double gsRatio = goldClose / silverClose;
         if(gsRatio >= GSRatio_ExtHigh) { gsLongBias = true;  gsSentimentMult = Stagflation_SizeMult; }
         if(gsRatio <= GSRatio_ExtLow)  { gsReduceLong = true; gsSentimentMult = 0.85; }
      }
   }

   if(UseNewsGuard && IsNewsWindow()) return;

   bool longSignal  = false;
   bool shortSignal = false;

   if(regime == REGIME_TREND || regime == REGIME_BREAKOUT)
   {
      longSignal = goldenCross
                   && (!UseTrendFilter || aboveTrend)
                   && mtfBullish
                   && (rsi[1] > 50.0 && rsi[1] < RSI_LongMax)
                   && atrOK
                   && breakoutLong
                   && !dxyBlocking
                   && !gsReduceLong
                   && (!UseDivergenceFilter || !bearishDivergence);

      shortSignal = deathCross
                    && (!UseTrendFilter || belowTrend)
                    && mtfBearish
                    && (rsi[1] < 50.0 && rsi[1] > RSI_ShortMin)
                    && atrOK
                    && breakoutShort
                    && !g_vixRiskOff
                    && (!UseDivergenceFilter || !bullishDivergence);
   }
   else if(regime == REGIME_RANGE)
   {
      bool nearLowerBB = (closePrice <= bbMid[1] - (bbMid[1] - bbLower[1]) * 0.7);
      bool nearUpperBB = (closePrice >= bbMid[1] + (bbUpper[1] - bbMid[1]) * 0.7);

      longSignal  = nearLowerBB
                    && (rsi[1] < 45.0)
                    && (!UseTrendFilter || aboveTrend)
                    && mtfBullish
                    && !dxyBlocking
                    && (!UseDivergenceFilter || bullishDivergence);

      shortSignal = nearUpperBB
                    && (rsi[1] > 55.0)
                    && (!UseTrendFilter || belowTrend)
                    && mtfBearish
                    && !g_vixRiskOff
                    && (!UseDivergenceFilter || bearishDivergence);
   }

   if(longSignal  && CountOpenPositions() < MaxPositions)
      OpenPosition(ORDER_TYPE_BUY,  gsSentimentMult);
   if(shortSignal && CountOpenPositions() < MaxPositions)
      OpenPosition(ORDER_TYPE_SELL, 1.0);

   ManagePositions();
}

//+------------------------------------------------------------------+
ENUM_REGIME DetectRegime()
{
   if(!UseRegimeFilter) return REGIME_TREND;
   if(adx[1] >= ADX_TrendMin) return REGIME_TREND;
   if(adx[1] <= ADX_RangeMax) return REGIME_RANGE;

   double closePrice = iClose(_Symbol, Timeframe, 1);
   if(closePrice > bbUpper[1] || closePrice < bbLower[1]) return REGIME_BREAKOUT;
   return REGIME_RANGE;
}

//+------------------------------------------------------------------+
bool CheckBullishDivergence()
{
   int lookback = Div_Lookback + 1;
   if(lookback >= ArraySize(rsi)) return false;
   double pricePrev = iLow(_Symbol, Timeframe, lookback);
   double priceCur  = iLow(_Symbol, Timeframe, 1);
   return (priceCur < pricePrev && rsi[1] > rsi[lookback]);
}

bool CheckBearishDivergence()
{
   int lookback = Div_Lookback + 1;
   if(lookback >= ArraySize(rsi)) return false;
   double pricePrev = iHigh(_Symbol, Timeframe, lookback);
   double priceCur  = iHigh(_Symbol, Timeframe, 1);
   return (priceCur > pricePrev && rsi[1] < rsi[lookback]);
}

//+------------------------------------------------------------------+
bool IsNewsWindow()
{
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   string parts[];
   int count = StringSplit(NewsHours, ',', parts);
   for(int i=0; i<count; i++)
   {
      int h = (int)StringToInteger(StringTrimLeft(StringTrimRight(parts[i])));
      if(dt.hour == h) return true;
      for(int b=1; b<=NewsGuard_Bars; b++)
         if(dt.hour == (h + b) % 24) return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void UpdateVIXState()
{
   g_vixRiskOff = false;
   if(!UseVIXFilter || !g_vixAvailable) return;

   double vixClose = iClose(VIX_Symbol, PERIOD_D1, 1);
   if(vixClose <= 0) return;

   if(vixClose > VIX_RiskOff) g_vixAboveCount++;
   else g_vixAboveCount = 0;

   g_vixRiskOff = (g_vixAboveCount >= VIX_HoldBars);
}

//+------------------------------------------------------------------+
double CalcLotSize(double slDistancePrice, double scenarioMult=1.0)
{
   if(slDistancePrice <= 0) return 0.0;
   double balance    = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskAmount = balance * BaseRiskPercent / 100.0;
   double lossPerLot = (slDistancePrice / g_tickSize) * g_tickValue;
   if(lossPerLot <= 0) return 0.0;

   double lots = riskAmount / lossPerLot;
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

   double finalMult = scenarioMult;
   if(UseScenarioSizing && g_vixRiskOff)
      finalMult *= RiskOff_SizeMult;

   double lotSize = CalcLotSize(slDistance, finalMult);
   if(UseDynamicRisk && atr[1] > atrAvgSafe()*2.5)
      lotSize = NormalizeDouble(lotSize * 0.55, 2);

   if(lotSize < g_volMin) return;

   double effectiveRR = MathMax(RR_TakeProfit, 2.0);
   double sl=0, tp=0;
   bool ok = false;

   if(type == ORDER_TYPE_BUY)
   {
      sl = NormalizeDouble(bid - slDistance, g_digits);
      tp = NormalizeDouble(bid + slDistance * effectiveRR, g_digits);
      ok = trade.Buy(lotSize, _Symbol, ask, sl, tp, "QGT Long v4.11F");
   }
   else
   {
      sl = NormalizeDouble(ask + slDistance, g_digits);
      tp = NormalizeDouble(ask - slDistance * effectiveRR, g_digits);
      ok = trade.Sell(lotSize, _Symbol, bid, sl, tp, "QGT Short v4.11F");
   }

   if(!ok) Print("Order failed: ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
double atrAvgSafe() { return (atr[1]+atr[2]+atr[3])/3.0; }

bool PartialAlreadyDone(ulong ticket)
{
   for(int i=0; i<ArraySize(g_partialDone); i++)
      if(g_partialDone[i]==ticket) return true;
   return false;
}

void MarkPartialDone(ulong ticket)
{
   int sz = ArraySize(g_partialDone);
   ArrayResize(g_partialDone, sz+1);
   g_partialDone[sz] = ticket;
}

void CleanupPartialTracking()
{
   for(int i=ArraySize(g_partialDone)-1; i>=0; i--)
   {
      if(!PositionSelectByTicket(g_partialDone[i]))
      {
         for(int j=i; j<ArraySize(g_partialDone)-1; j++)
            g_partialDone[j] = g_partialDone[j+1];
         ArrayResize(g_partialDone, ArraySize(g_partialDone)-1);
      }
   }
}

void ManagePositions()
{
   CleanupPartialTracking();
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
      double
