#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TradeExecution.mqh"

// Tests ONLY the pure function ClampStopLossToMinDistance - no live
// account/demo guard needed since it takes hardcoded numbers and never
// touches the MT5 API.

void OnStart()
  {
   T_ResetCounters();

   // currentPrice=2000.0, minDistance=1.0, digits=2
   //   long:  maxAllowed = currentPrice - minDistance = 1999.0
   //   short: minAllowed = currentPrice + minDistance = 2001.0

   double sl = ClampStopLossToMinDistance(1999.8, true, 2000.0, 1.0, 2);
   T_AssertEqualsDouble("long SL too close gets pushed away to maxAllowed", sl, 1999.0);

   sl = ClampStopLossToMinDistance(1990.0, true, 2000.0, 1.0, 2);
   T_AssertEqualsDouble("long SL already far enough is untouched", sl, 1990.0);

   sl = ClampStopLossToMinDistance(2000.2, false, 2000.0, 1.0, 2);
   T_AssertEqualsDouble("short SL too close gets pushed away to minAllowed", sl, 2001.0);

   sl = ClampStopLossToMinDistance(2010.0, false, 2000.0, 1.0, 2);
   T_AssertEqualsDouble("short SL already far enough is untouched", sl, 2010.0);

   T_PrintSummary("Test_TradeExecution_Stops");
  }
