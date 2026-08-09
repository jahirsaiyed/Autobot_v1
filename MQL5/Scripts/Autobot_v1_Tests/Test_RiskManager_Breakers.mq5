#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();

   // Daily breaker: trips exactly at the 5% threshold.
   T_AssertTrue("daily breaker trips at exactly 5% loss",
                UpdateDailyBreakerState(false, 10000.0, 9500.0, 5.0) == true);
   T_AssertTrue("daily breaker does not trip above threshold",
                UpdateDailyBreakerState(false, 10000.0, 9600.0, 5.0) == false);
   T_AssertTrue("daily breaker is sticky - stays tripped even after equity recovers",
                UpdateDailyBreakerState(true, 10000.0, 9999999.0, 5.0) == true);

   // Equity peak never decreases.
   T_AssertEqualsDouble("peak rises with equity", UpdateEquityPeak(10000.0, 10500.0), 10500.0);
   T_AssertEqualsDouble("peak does not fall with equity", UpdateEquityPeak(10500.0, 9000.0), 10500.0);

   // Max drawdown: trips exactly at the 15% threshold.
   T_AssertTrue("max drawdown trips at exactly 15% below peak",
                IsMaxDrawdownTripped(10000.0, 8500.0, 15.0) == true);
   T_AssertTrue("max drawdown does not trip above threshold",
                IsMaxDrawdownTripped(10000.0, 8600.0, 15.0) == false);

   T_PrintSummary("Test_RiskManager_Breakers");
  }
