#property strict
#include "TestUtils.mqh"

void OnStart()
  {
   T_ResetCounters();
   T_AssertTrue("smoke test runs", true);
   T_PrintSummary("SmokeTest_Compile");
  }
