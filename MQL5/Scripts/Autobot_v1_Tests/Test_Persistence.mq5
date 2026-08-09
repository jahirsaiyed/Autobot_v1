#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Persistence.mqh"

void OnStart()
  {
   T_ResetCounters();

   // Clean slate.
   if(FileIsExist(PersistenceFileName(), FILE_COMMON))
      FileDelete(PersistenceFileName(), FILE_COMMON);

   double eq, peak;
   long dayCode;
   bool valid;

   // Missing file (genuine first run).
   bool found = LoadPersistedState(eq, dayCode, peak, valid);
   T_AssertTrue("missing file: found=false", found == false);
   T_AssertTrue("missing file: valid=false", valid == false);

   // Round-trip.
   T_AssertTrue("save succeeds", SavePersistedState(9800.0, 20260809, 10500.0));
   found = LoadPersistedState(eq, dayCode, peak, valid);
   T_AssertTrue("round-trip: found=true", found == true);
   T_AssertTrue("round-trip: valid=true", valid == true);
   T_AssertEqualsDouble("round-trip: dailyStartEquity matches", eq, 9800.0);
   T_AssertEqualsInt("round-trip: dailyStartDayCode matches", (int)dayCode, 20260809);
   T_AssertEqualsDouble("round-trip: equityPeak matches", peak, 10500.0);

   // Corruption: overwrite with garbage bytes not matching the magic header.
   int handle = FileOpen(PersistenceFileName(), FILE_WRITE | FILE_BIN | FILE_COMMON);
   FileWriteLong(handle, 1111111L); // wrong magic
   FileWriteDouble(handle, 1.0);
   FileWriteLong(handle, 1L);
   FileWriteDouble(handle, 1.0);
   FileClose(handle);

   found = LoadPersistedState(eq, dayCode, peak, valid);
   T_AssertTrue("corrupt file: found=true (file exists)", found == true);
   T_AssertTrue("corrupt file: valid=false (fail-safe triggers)", valid == false);

   // Cleanup.
   FileDelete(PersistenceFileName(), FILE_COMMON);

   T_PrintSummary("Test_Persistence");
  }
