#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Persistence.mqh"

void OnStart()
  {
   T_ResetCounters();

   // Clean slate. testMode=true throughout - never touches the production
   // Autobot_v1_state.bin file.
   if(FileIsExist(PersistenceFileName(true), FILE_COMMON))
      FileDelete(PersistenceFileName(true), FILE_COMMON);

   double eq, peak;
   long dayCode;
   bool dailyTripped, maxDDTripped;
   bool valid;

   // Missing file (genuine first run).
   bool found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("missing file: found=false", found == false);
   T_AssertTrue("missing file: valid=false", valid == false);

   // Round-trip, including the two breaker-tripped flags added alongside
   // the bumped magic header.
   T_AssertTrue("save succeeds", SavePersistedState(9800.0, 20260809, 10500.0, true, false, true));
   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("round-trip: found=true", found == true);
   T_AssertTrue("round-trip: valid=true", valid == true);
   T_AssertEqualsDouble("round-trip: dailyStartEquity matches", eq, 9800.0);
   T_AssertEqualsInt("round-trip: dailyStartDayCode matches", (int)dayCode, 20260809);
   T_AssertEqualsDouble("round-trip: equityPeak matches", peak, 10500.0);
   T_AssertTrue("round-trip: dailyBreakerTripped matches (true)", dailyTripped == true);
   T_AssertTrue("round-trip: maxDrawdownTripped matches (false)", maxDDTripped == false);

   // Round-trip again with the flags flipped, to make sure both booleans
   // are read back independently rather than one masking the other.
   T_AssertTrue("second save succeeds", SavePersistedState(9700.0, 20260810, 10600.0, false, true, true));
   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("second round-trip: valid=true", valid == true);
   T_AssertTrue("second round-trip: dailyBreakerTripped matches (false)", dailyTripped == false);
   T_AssertTrue("second round-trip: maxDrawdownTripped matches (true)", maxDDTripped == true);

   // Corruption: overwrite with a full-size record carrying the wrong magic
   // header, so the failure exercises the magic check (not the short-file
   // check) even with the bumped header size (4 longs + 2 doubles).
   int handle = FileOpen(PersistenceFileName(true), FILE_WRITE | FILE_BIN | FILE_COMMON);
   FileWriteLong(handle, 1111111L); // wrong magic
   FileWriteDouble(handle, 1.0);
   FileWriteLong(handle, 1L);
   FileWriteDouble(handle, 1.0);
   FileWriteLong(handle, 0L);
   FileWriteLong(handle, 0L);
   FileClose(handle);

   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("corrupt file: found=true (file exists)", found == true);
   T_AssertTrue("corrupt file: valid=false (fail-safe triggers)", valid == false);

   // Cleanup.
   FileDelete(PersistenceFileName(true), FILE_COMMON);

   T_PrintSummary("Test_Persistence");
  }
