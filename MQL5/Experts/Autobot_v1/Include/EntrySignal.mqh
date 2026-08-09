//+------------------------------------------------------------------+
//| EntrySignal.mqh - H1 Donchian(20) breakout detection             |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

#ifndef AUTOBOT_V1_ENTRYSIGNAL_MQH
#define AUTOBOT_V1_ENTRYSIGNAL_MQH

enum ENUM_SIGNAL
  {
   SIGNAL_LONG_BREAKOUT,
   SIGNAL_SHORT_BREAKOUT,
   SIGNAL_NONE
  };

// Pure function. priorHighestHigh/priorLowestLow must be computed from the
// 20 bars BEFORE the just-closed bar (see MarketData.mqh ComputeDonchian,
// Task 14) - not including the bar being evaluated for breakout.
ENUM_SIGNAL DetectBreakout(double currentClose, double priorHighestHigh, double priorLowestLow, ENUM_BIAS bias)
  {
   if(bias == BIAS_LONG && currentClose > priorHighestHigh)
      return SIGNAL_LONG_BREAKOUT;
   if(bias == BIAS_SHORT && currentClose < priorLowestLow)
      return SIGNAL_SHORT_BREAKOUT;
   return SIGNAL_NONE;
  }

#endif // AUTOBOT_V1_ENTRYSIGNAL_MQH
