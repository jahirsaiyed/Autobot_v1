#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/EntrySignal.mqh"

void OnStart()
  {
   T_ResetCounters();

   // priorHigh=110, priorLow=90
   T_AssertTrue("long bias + close above prior high => LONG breakout",
                DetectBreakout(111.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_LONG_BREAKOUT);
   T_AssertTrue("long bias + close below prior high => NONE",
                DetectBreakout(109.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_NONE);
   T_AssertTrue("short bias + close below prior low => SHORT breakout",
                DetectBreakout(89.0, 110.0, 90.0, BIAS_SHORT) == SIGNAL_SHORT_BREAKOUT);
   T_AssertTrue("short bias + close above prior low => NONE",
                DetectBreakout(91.0, 110.0, 90.0, BIAS_SHORT) == SIGNAL_NONE);
   T_AssertTrue("no bias => NONE even if price breaks high",
                DetectBreakout(111.0, 110.0, 90.0, BIAS_NONE) == SIGNAL_NONE);
   T_AssertTrue("long bias but price breaks LOW, not high => NONE (wrong direction)",
                DetectBreakout(89.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_NONE);

   T_PrintSummary("Test_EntrySignal");
  }
