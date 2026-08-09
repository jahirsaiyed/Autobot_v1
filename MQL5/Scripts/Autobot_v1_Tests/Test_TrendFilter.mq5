#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TrendFilter.mqh"

void OnStart()
  {
   T_ResetCounters();

   // ATR=10, deadband multiplier=0.1 => deadband=1.0
   T_AssertTrue("price well above EMA => LONG", DetermineBias(2020.0, 2000.0, 10.0, 0.1) == BIAS_LONG);
   T_AssertTrue("price well below EMA => SHORT", DetermineBias(1980.0, 2000.0, 10.0, 0.1) == BIAS_SHORT);
   T_AssertTrue("price within deadband above => NONE", DetermineBias(2000.5, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price within deadband below => NONE", DetermineBias(1999.5, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price exactly at EMA => NONE", DetermineBias(2000.0, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price just past deadband edge => LONG", DetermineBias(2001.01, 2000.0, 10.0, 0.1) == BIAS_LONG);
   T_AssertTrue("zero ATR collapses deadband => any positive diff triggers LONG", DetermineBias(2000.01, 2000.0, 0.0, 0.1) == BIAS_LONG);

   T_PrintSummary("Test_TrendFilter");
  }
