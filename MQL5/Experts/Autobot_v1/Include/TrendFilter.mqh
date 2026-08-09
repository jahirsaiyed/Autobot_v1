//+------------------------------------------------------------------+
//| TrendFilter.mqh - H4 EMA200 trend bias with ATR deadband         |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

#ifndef AUTOBOT_V1_TRENDFILTER_MQH
#define AUTOBOT_V1_TRENDFILTER_MQH

// Pure function: given an already-computed H4 close, EMA, and ATR value,
// determine directional bias. No indicator handles or live data access -
// callers fetch closePrice/emaValue/atrValue via CopyClose/CopyBuffer
// (see MarketData.mqh, Task 14).
ENUM_BIAS DetermineBias(double closePrice, double emaValue, double atrValue, double deadbandMultiplier)
  {
   double diff = closePrice - emaValue;
   double deadband = deadbandMultiplier * atrValue;

   if(diff > deadband)
      return BIAS_LONG;
   if(diff < -deadband)
      return BIAS_SHORT;
   return BIAS_NONE;
  }

#endif // AUTOBOT_V1_TRENDFILTER_MQH
