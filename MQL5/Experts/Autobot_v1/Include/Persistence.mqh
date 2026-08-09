//+------------------------------------------------------------------+
//| Persistence.mqh - file-based state survives VPS/terminal restarts|
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_PERSISTENCE_MQH
#define AUTOBOT_V1_PERSISTENCE_MQH

#define PERSIST_MAGIC_HEADER 954218L // bumped from 954217L when the two
                                      // breaker-tripped flags were added to
                                      // the binary format - this correctly
                                      // makes old-format files fail the
                                      // magic check below and get treated as
                                      // corrupt (fail-safe), rather than
                                      // silently misreading their bytes.

// testMode=true is used exclusively by test scripts (Test_Persistence.mq5)
// so they never read/write the production state file.
string PersistenceFileName(bool testMode = false)
  {
   return testMode ? "Autobot_v1_state.TEST.bin" : "Autobot_v1_state.bin";
  }

// Persistence is intentionally skipped ENTIRELY inside the Strategy Tester
// and optimization passes - both functions below early-exit before touching
// any file whenever MQL_TESTER/MQL_OPTIMIZATION is true. This guarantees
// every backtest starts as a genuine first run, seeded from its own actual
// deposit. A plain (non-FILE_COMMON) file still persists across consecutive
// backtests on the same Tester agent, which previously let a poisoned
// equity peak (or a stale breaker-tripped flag) from one run leak into the
// next run on that agent. Once we're past the early-exit we know we are NOT
// in the tester/optimization, so all real file I/O below uses FILE_COMMON
// unconditionally (the machine-wide folder needed for genuine live/demo
// VPS-reboot survival).
bool SavePersistedState(double dailyStartEquity, long dailyStartDayCode, double equityPeak,
                         bool dailyBreakerTripped, bool maxDrawdownTripped, bool testMode = false)
  {
   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
      return true;

   int handle = FileOpen(PersistenceFileName(testMode), FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteLong(handle, PERSIST_MAGIC_HEADER);
   FileWriteDouble(handle, dailyStartEquity);
   FileWriteLong(handle, dailyStartDayCode);
   FileWriteDouble(handle, equityPeak);
   FileWriteLong(handle, dailyBreakerTripped ? 1 : 0);
   FileWriteLong(handle, maxDrawdownTripped ? 1 : 0);
   FileClose(handle);
   return true;
  }

// fileValid=false on any read failure, wrong-magic, or short file. Callers
// MUST treat fileValid=false (when a file was found) as the fail-safe
// trigger described in the spec - block new entries + alert - and never
// silently reseed state. Return value distinguishes "file exists" (true)
// from "no file at all" (false); check fileValid separately.
bool LoadPersistedState(double &dailyStartEquity, long &dailyStartDayCode, double &equityPeak,
                         bool &dailyBreakerTripped, bool &maxDrawdownTripped, bool &fileValid,
                         bool testMode = false)
  {
   dailyStartEquity    = 0.0;
   dailyStartDayCode   = 0;
   equityPeak          = 0.0;
   dailyBreakerTripped = false;
   maxDrawdownTripped  = false;
   fileValid           = false;

   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
      return false; // report "not found" immediately - no tester/optimization state ever exists

   if(!FileIsExist(PersistenceFileName(testMode), FILE_COMMON))
      return false;

   int handle = FileOpen(PersistenceFileName(testMode), FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return true; // file exists but couldn't be opened - fileValid stays false

   ulong minSize = (ulong)(sizeof(long) * 4 + sizeof(double) * 2);
   if(FileSize(handle) < minSize)
     {
      FileClose(handle);
      return true;
     }

   long magic = FileReadLong(handle);
   if(magic != PERSIST_MAGIC_HEADER)
     {
      FileClose(handle);
      return true;
     }

   dailyStartEquity    = FileReadDouble(handle);
   dailyStartDayCode   = FileReadLong(handle);
   equityPeak          = FileReadDouble(handle);
   dailyBreakerTripped = (FileReadLong(handle) != 0);
   maxDrawdownTripped  = (FileReadLong(handle) != 0);
   FileClose(handle);

   fileValid = true;
   return true;
  }

#endif // AUTOBOT_V1_PERSISTENCE_MQH
