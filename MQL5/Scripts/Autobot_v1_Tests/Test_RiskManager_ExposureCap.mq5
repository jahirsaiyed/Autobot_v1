#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertTrue("no existing crypto risk, 1% fits under 1.5% cap",
                CanOpenCryptoPosition(0.0, 1.0, 1.5) == true);
   T_AssertTrue("1% existing + 1% new exceeds 1.5% cap => blocked",
                CanOpenCryptoPosition(1.0, 1.0, 1.5) == false);
   T_AssertTrue("1% existing + 0.5% new exactly hits 1.5% cap => allowed",
                CanOpenCryptoPosition(1.0, 0.5, 1.5) == true);
   T_AssertTrue("single trade using the whole 1.5% budget => allowed",
                CanOpenCryptoPosition(0.0, 1.5, 1.5) == true);
   T_AssertTrue("single trade exceeding the whole budget => blocked",
                CanOpenCryptoPosition(0.0, 1.6, 1.5) == false);

   T_PrintSummary("Test_RiskManager_ExposureCap");
  }
