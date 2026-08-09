#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();
   bool skipped;
   double lots;

   // Case 1: normal sizing. equity=10000, risk=1% => riskAmount=100.
   // tickValue=1, tickSize=1 => valuePerLot = stopDistance = 5.0.
   // rawLots = 100/5 = 20.0, volumeStep=0.01 => steppedLots=20.00.
   lots = CalculateLotSize(10000.0, 1.0, 5.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("normal case not skipped", !skipped);
   T_AssertEqualsDouble("normal case lots = 20.00", lots, 20.00);

   // Case 2: computed size rounds below minimum volume => skipped.
   // equity=100, risk=1% => riskAmount=1.0. stopDistance=1000, tickValue=1,
   // tickSize=1 => valuePerLot=1000. rawLots=0.001 < volumeMin=0.01.
   lots = CalculateLotSize(100.0, 1.0, 1000.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("below-minimum case is skipped", skipped);
   T_AssertEqualsDouble("below-minimum case returns 0", lots, 0.0);

   // Case 3: computed size clamps to maximum volume.
   // equity=1,000,000, risk=1% => riskAmount=10000. stopDistance=1,
   // tickValue=1, tickSize=1 => valuePerLot=1. rawLots=10000, volumeMax=50.
   lots = CalculateLotSize(1000000.0, 1.0, 1.0, 1.0, 1.0, 0.01, 0.01, 50.0, skipped);
   T_AssertTrue("above-maximum case not skipped", !skipped);
   T_AssertEqualsDouble("above-maximum case clamps to 50.00", lots, 50.00);

   // Case 4: invalid stop distance => skipped.
   lots = CalculateLotSize(10000.0, 1.0, 0.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("zero stop distance is skipped", skipped);

   T_PrintSummary("Test_RiskManager_Sizing");
  }
