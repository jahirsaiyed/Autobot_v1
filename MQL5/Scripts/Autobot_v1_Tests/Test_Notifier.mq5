#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Notifier.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertEqualsString("escapes quotes", EscapeJsonString("say \"hi\""), "say \\\"hi\\\"");
   T_AssertEqualsString("escapes backslashes", EscapeJsonString("a\\b"), "a\\\\b");

   string payload = FormatTelegramPayload("12345", "hello");
   T_AssertEqualsString("telegram payload format", payload, "{\"chat_id\":\"12345\",\"text\":\"hello\"}");

   // Running as a normal script (not inside Strategy Tester/optimization),
   // suppression must be false. The true-branch (inside Strategy Tester) is
   // exercised by the Task 16 Strategy Tester smoke test, not here.
   T_AssertTrue("notifications not suppressed in a normal script run", IsNotificationSuppressed() == false);

   T_PrintSummary("Test_Notifier");
  }
