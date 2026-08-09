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

   // Round to the broker's actual volume-step precision, not a hardcoded 2
   // decimals - a 0.001 volumeStep (common on some crypto CFDs) would
   // otherwise have its third decimal silently truncated away here.
   int volDigits = (int)MathMax(0, MathCeil(-MathLog10(volumeStep) - 0.0000001));
   return NormalizeDouble(steppedLots, volDigits);
  }

// --- Circuit breakers ---------------------------------------------------

// Sticky daily-loss breaker: once tripped, stays tripped regardless of
// equity recovery. Caller resets currentlyTripped to false at the next
// day boundary (see Autobot_v1.mq5, Task 15).
bool UpdateDailyBreakerState(bool currentlyTripped, double dailyStartEquity, double currentEquity, double dailyLossPercent)
  {
   if(currentlyTripped)
      return true;

   double threshold = dailyStartEquity * (1.0 - dailyLossPercent / 100.0);
   return (currentEquity <= threshold);
  }

// High-water mark - never decreases.
double UpdateEquityPeak(double currentPeak, double currentEquity)
  {
   return MathMax(currentPeak, currentEquity);
  }

// Not sticky in this function alone - the caller (Autobot_v1.mq5) ORs this
// into a persistent g_maxDrawdownTripped flag that requires manual
// re-enable, per spec (a 15% drawdown needs human review, not auto-resume).
bool IsMaxDrawdownTripped(double equityPeak, double currentEquity, double maxDrawdownPercent)
  {
   double threshold = equityPeak * (1.0 - maxDrawdownPercent / 100.0);
   return (currentEquity <= threshold);
  }

// --- Correlated exposure cap (BTCUSD + ETHUSD) --------------------------

// existingOtherSymbolRiskPercent is the OTHER crypto symbol's open risk
// (0 if none open), fixed at its risk-at-entry value per the spec's
// cap-basis decision (not recalculated as that trade trails).
// newRiskPercent is the risk the incoming trade would take if opened.
// The BTC-before-ETH tie-break is enforced structurally by main-loop
// array order (Config.mqh, Task 2) - this function only checks the cap.
bool CanOpenCryptoPosition(double existingOtherSymbolRiskPercent, double newRiskPercent, double capPercent)
  {
   double combined = existingOtherSymbolRiskPercent + newRiskPercent;
   return (combined <= capPercent + 0.0000001); // epsilon guards float rounding at the exact boundary
  }

#endif // AUTOBOT_V1_RISKMANAGER_MQH
