#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/SymbolState.mqh"

void OnStart()
  {
   T_ResetCounters();

   SymbolConfig configs[];
   GetSymbolConfigs(configs);

   SymbolState states[];
   InitSymbolStates(states, configs);

   T_AssertEqualsInt("state count is 3", ArraySize(states), 3);
   T_AssertTrue("default bias is BIAS_NONE", states[0].bias == BIAS_NONE);
   T_AssertEqualsInt("default trail phase is PHASE_1", states[0].trailPhase, TRAIL_PHASE_1_BREAKEVEN);
   T_AssertEqualsInt("FindSymbolIndex(BTCUSD) == 1", FindSymbolIndex(states, "BTCUSD"), 1);
   T_AssertEqualsInt("FindSymbolIndex(ETHUSD) == 2", FindSymbolIndex(states, "ETHUSD"), 2);
   T_AssertEqualsInt("FindSymbolIndex(unknown) == -1", FindSymbolIndex(states, "DOGEUSD"), -1);

   T_PrintSummary("Test_SymbolState");
  }
