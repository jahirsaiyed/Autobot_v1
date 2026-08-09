//+------------------------------------------------------------------+
//| TestUtils.mqh - shared assertion helpers for Autobot_v1 test     |
//| scripts. No MT5 unit-test framework exists; these helpers print  |
//| PASS/FAIL lines to the Experts log for manual verification.      |
//+------------------------------------------------------------------+
#property strict

int g_testPassCount = 0;
int g_testFailCount = 0;

void T_ResetCounters()
  {
   g_testPassCount = 0;
   g_testFailCount = 0;
  }

void T_AssertTrue(string testName, bool condition, string detail = "")
  {
   if(condition)
     {
      g_testPassCount++;
      PrintFormat("PASS: %s", testName);
     }
   else
     {
      g_testFailCount++;
      PrintFormat("FAIL: %s %s", testName, detail);
     }
  }

void T_AssertEqualsDouble(string testName, double actual, double expected, double tolerance = 0.00001)
  {
   bool ok = MathAbs(actual - expected) <= tolerance;
   T_AssertTrue(testName, ok, StringFormat("expected=%.5f actual=%.5f", expected, actual));
  }

void T_AssertEqualsInt(string testName, int actual, int expected)
  {
   T_AssertTrue(testName, actual == expected, StringFormat("expected=%d actual=%d", expected, actual));
  }

void T_AssertEqualsString(string testName, string actual, string expected)
  {
   T_AssertTrue(testName, actual == expected, StringFormat("expected=%s actual=%s", expected, actual));
  }

void T_PrintSummary(string suiteName)
  {
   PrintFormat("=== %s: %d passed, %d failed ===", suiteName, g_testPassCount, g_testFailCount);
   if(g_testFailCount == 0)
      PrintFormat("ALL TESTS PASSED: %s", suiteName);
   else
      PrintFormat("TESTS FAILED: %s", suiteName);
  }
