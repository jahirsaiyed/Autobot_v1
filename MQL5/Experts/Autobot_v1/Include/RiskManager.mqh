//+------------------------------------------------------------------+
//| RiskManager.mqh - position sizing, circuit breakers, exposure cap|
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_RISKMANAGER_MQH
#define AUTOBOT_V1_RISKMANAGER_MQH

// --- Position sizing ---------------------------------------------------

// Pure function. tickValue MUST be SYMBOL_TRADE_TICK_VALUE_PROFIT (or
// SYMBOL_TRADE_TICK_VALUE_LOSS for a more conservative estimate) - never
// the plain SYMBOL_TRADE_TICK_VALUE, which can be stale on CFDs like
// XAUUSD/BTCUSD/ETHUSD (see spec Risk Management > Position sizing).
double CalculateLotSize(double equity, double riskPercent, double stopDistancePrice,
                         double tickValue, double tickSize, double volumeStep,
                         double volumeMin, double volumeMax, bool &skipped)
  {
   skipped = false;

   if(stopDistancePrice <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || volumeStep <= 0.0)
     {
      skipped = true;
      return 0.0;
     }

   double riskAmount  = equity * (riskPercent / 100.0);
   double valuePerLot = (tickValue / tickSize) * stopDistancePrice;
   double rawLots      = riskAmount / valuePerLot;

   double steppedLots = MathFloor(rawLots / volumeStep) * volumeStep;

   if(steppedLots < volumeMin)
     {
      skipped = true;
      return 0.0;
     }

   if(steppedLots > volumeMax)
      steppedLots = volumeMax;

   return NormalizeDouble(steppedLots, 2);
  }

#endif // AUTOBOT_V1_RISKMANAGER_MQH
