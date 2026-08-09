#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Config.mqh"

void OnStart()
  {
   T_ResetCounters();

   SymbolConfig configs[];
   GetSymbolConfigs(configs);

   T_AssertEqualsInt("symbol count is 3", ArraySize(configs), 3);
   T_AssertEqualsString("index 0 is XAUUSD", configs[0].symbol, "XAUUSD");
   T_AssertEqualsString("index 1 is BTCUSD", configs[1].symbol, "BTCUSD");
   T_AssertEqualsString("index 2 is ETHUSD", configs[2].symbol, "ETHUSD");
   T_AssertTrue("XAUUSD not in correlated group", !configs[0].isCorrelatedGroup);
   T_AssertTrue("BTCUSD in correlated group", configs[1].isCorrelatedGroup);
   T_AssertTrue("ETHUSD in correlated group", configs[2].isCorrelatedGroup);
   T_AssertEqualsInt("XAUUSD magic = base+1", (int)configs[0].magicNumber, (int)InpMagicBase + 1);
   T_AssertEqualsInt("BTCUSD magic = base+2", (int)configs[1].magicNumber, (int)InpMagicBase + 2);
   T_AssertEqualsInt("ETHUSD magic = base+3", (int)configs[2].magicNumber, (int)InpMagicBase + 3);
   // BTC-before-ETH tie-break is enforced by this array's index order (1
   // before 2), consumed by the main loop in Task 15 - not re-checked here.

   T_PrintSummary("Test_Config");
  }
