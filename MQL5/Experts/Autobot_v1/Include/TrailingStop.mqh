//+------------------------------------------------------------------+
//| TrailingStop.mqh - breakeven + structure-based trailing           |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

#ifndef AUTOBOT_V1_TRAILINGSTOP_MQH
#define AUTOBOT_V1_TRAILINGSTOP_MQH

// unrealizedProfitPrice and initialRiskPrice are both in price units
// (not points), same sign convention (positive = favorable).
bool ShouldMoveToBreakeven(double unrealizedProfitPrice, double initialRiskPrice)
  {
   if(initialRiskPrice <= 0.0)
      return false;
   return (unrealizedProfitPrice >= initialRiskPrice);
  }

double CalculateBreakevenSL(double entryPrice, bool isLong, double bufferPrice)
  {
   return isLong ? (entryPrice + bufferPrice) : (entryPrice - bufferPrice);
  }

double CalculateStructureTrailSL(double priorBarLow, double priorBarHigh, bool isLong)
  {
   return isLong ? priorBarLow : priorBarHigh;
  }

// Infers which trailing phase a resumed position is in, per the spec's
// restart-reconstruction rule: SL at/past entry (favorable side) => Phase 2.
int InferTrailPhase(double currentSL, double entryPrice, bool isLong)
  {
   if(isLong)
      return (currentSL >= entryPrice) ? TRAIL_PHASE_2_STRUCTURE : TRAIL_PHASE_1_BREAKEVEN;
   else
      return (currentSL <= entryPrice) ? TRAIL_PHASE_2_STRUCTURE : TRAIL_PHASE_1_BREAKEVEN;
  }

#endif // AUTOBOT_V1_TRAILINGSTOP_MQH
