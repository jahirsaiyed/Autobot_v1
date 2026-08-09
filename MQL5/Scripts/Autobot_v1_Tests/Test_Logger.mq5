#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Logger.mqh"

void OnStart()
  {
   T_ResetCounters();

   if(FileIsExist(LogFileName(), FILE_COMMON))
      FileDelete(LogFileName(), FILE_COMMON);

   T_AssertTrue("first log event succeeds",
                LogEvent("2026.08.09 12:00:00", "XAUUSD", "entry", 2000.12345, 0.10, 1990.0, 10000.0, "AutoBotV1|TrendBreak|H1"));
   T_AssertTrue("second log event succeeds",
                LogEvent("2026.08.09 13:00:00", "BTCUSD", "exit", 65000.5, 0.01, 64000.0, 10050.0, "trail-stop"));

   int handle = FileOpen(LogFileName(), FILE_READ | FILE_CSV | FILE_COMMON, ',');
   T_AssertTrue("log file reopens for reading", handle != INVALID_HANDLE);

   string header = FileReadString(handle);
   T_AssertEqualsString("header field 0 is timestamp", header, "timestamp");
   for(int i = 0; i < 7; i++) FileReadString(handle); // skip remaining header fields

   string row1Timestamp = FileReadString(handle);
   T_AssertEqualsString("row 1 timestamp matches", row1Timestamp, "2026.08.09 12:00:00");
   string row1Symbol = FileReadString(handle);
   T_AssertEqualsString("row 1 symbol matches", row1Symbol, "XAUUSD");

   FileClose(handle);
   FileDelete(LogFileName(), FILE_COMMON);

   T_PrintSummary("Test_Logger");
  }
