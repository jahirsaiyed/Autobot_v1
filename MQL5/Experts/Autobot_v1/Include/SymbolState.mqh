//+------------------------------------------------------------------+
//| SymbolState.mqh - per-symbol runtime state and shared enums      |
//+------------------------------------------------------------------+
#property strict
#include "Config.mqh"

#ifndef AUTOBOT_V1_SYMBOLSTATE_MQH
#define AUTOBOT_V1_SYMBOLSTATE_MQH

enum ENUM_BIAS
  {
   BIAS_LONG,
   BIAS_SHORT,
   BIAS_NONE
  };

#define TRAIL_PHASE_1_BREAKEVEN 1
#define TRAIL_PHASE_2_STRUCTURE 2

struct SymbolState
  {
   string    symbol;
   ENUM_BIAS bias;
   datetime  lastH1BarTime;
   int       trailPhase;
   double    entryPrice;
   double    initialStopDistance;
   double    riskPercentAtEntry;
  };

void InitSymbolStates(SymbolState &states[], const SymbolConfig &configs[])
  {
   int n = ArraySize(configs);
   ArrayResize(states, n);
   for(int i = 0; i < n; i++)
     {
      states[i].symbol              = configs[i].symbol;
      states[i].bias                = BIAS_NONE;
      states[i].lastH1BarTime       = 0;
      states[i].trailPhase          = TRAIL_PHASE_1_BREAKEVEN;
      states[i].entryPrice          = 0.0;
      states[i].initialStopDistance = 0.0;
      states[i].riskPercentAtEntry  = 0.0;
     }
  }

int FindSymbolIndex(const SymbolState &states[], string symbol)
  {
   for(int i = 0; i < ArraySize(states); i++)
      if(states[i].symbol == symbol)
         return i;
   return -1;
  }

#endif // AUTOBOT_V1_SYMBOLSTATE_MQH
