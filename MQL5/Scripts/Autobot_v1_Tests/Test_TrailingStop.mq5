#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TrailingStop.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertTrue("profit >= risk triggers breakeven move", ShouldMoveToBreakeven(10.0, 10.0) == true);
   T_AssertTrue("profit < risk does not trigger breakeven move", ShouldMoveToBreakeven(9.0, 10.0) == false);
   T_AssertTrue("zero initial risk never triggers (guards div-by-zero elsewhere)", ShouldMoveToBreakeven(5.0, 0.0) == false);

   T_AssertEqualsDouble("long breakeven SL = entry + buffer", CalculateBreakevenSL(2000.0, true, 0.5), 2000.5);
   T_AssertEqualsDouble("short breakeven SL = entry - buffer", CalculateBreakevenSL(2000.0, false, 0.5), 1999.5);

   T_AssertEqualsDouble("long structure trail = prior bar low", CalculateStructureTrailSL(1990.0, 2010.0, true), 1990.0);
   T_AssertEqualsDouble("short structure trail = prior bar high", CalculateStructureTrailSL(1990.0, 2010.0, false), 2010.0);

   T_AssertEqualsInt("long, SL past entry => Phase 2", InferTrailPhase(2001.0, 2000.0, true), TRAIL_PHASE_2_STRUCTURE);
   T_AssertEqualsInt("long, SL below entry => Phase 1", InferTrailPhase(1990.0, 2000.0, true), TRAIL_PHASE_1_BREAKEVEN);
   T_AssertEqualsInt("short, SL past entry => Phase 2", InferTrailPhase(1999.0, 2000.0, false), TRAIL_PHASE_2_STRUCTURE);
   T_AssertEqualsInt("short, SL above entry => Phase 1", InferTrailPhase(2010.0, 2000.0, false), TRAIL_PHASE_1_BREAKEVEN);

   T_PrintSummary("Test_TrailingStop");
  }
