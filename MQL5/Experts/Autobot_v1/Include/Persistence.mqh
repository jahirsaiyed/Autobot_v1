//+------------------------------------------------------------------+
//| Persistence.mqh - file-based state survives VPS/terminal restarts|
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_PERSISTENCE_MQH
#define AUTOBOT_V1_PERSISTENCE_MQH

#define PERSIST_MAGIC_HEADER 954217L // arbitrary constant used to detect a
                                      // corrupt/foreign file on load

string PersistenceFileName()
  {
   return "Autobot_v1_state.bin";
  }

// FILE_COMMON is a machine-wide folder shared by every MT5 terminal
// install AND the Strategy Tester on this machine - it is NOT isolated
// per live-account deployment. Using it unconditionally would let a
// backtest silently load (or overwrite) a live/demo account's persisted
// equity baseline, and vice versa - discovered via Task 16's Strategy
// Tester run loading a stale live-session equity value instead of the
// tester's actual starting deposit. Only use FILE_COMMON for genuine
// live/demo runs (where VPS-reboot survival matters); inside the Strategy
// Tester or an optimization pass, use a plain (non-common) file, which
// MT5 sandboxes per Tester agent and never shares with the live terminal.
int PersistenceFileFlag()
  {
   bool inTesterOrOptimization = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   return inTesterOrOptimization ? 0 : FILE_COMMON;
  }

bool SavePersistedState(double dailyStartEquity, long dailyStartDayCode, double equityPeak)
  {
   int handle = FileOpen(PersistenceFileName(), FILE_WRITE | FILE_BIN | PersistenceFileFlag());
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteLong(handle, PERSIST_MAGIC_HEADER);
   FileWriteDouble(handle, dailyStartEquity);
   FileWriteLong(handle, dailyStartDayCode);
   FileWriteDouble(handle, equityPeak);
   FileClose(handle);
   return true;
  }

// fileValid=false on any read failure, wrong-magic, or short file. Callers
// MUST treat fileValid=false (when a file was found) as the fail-safe
// trigger described in the spec - block new entries + alert - and never
// silently reseed state. Return value distinguishes "file exists" (true)
// from "no file at all" (false); check fileValid separately.
bool LoadPersistedState(double &dailyStartEquity, long &dailyStartDayCode, double &equityPeak, bool &fileValid)
  {
   dailyStartEquity = 0.0;
   dailyStartDayCode = 0;
   equityPeak = 0.0;
   fileValid = false;

   if(!FileIsExist(PersistenceFileName(), PersistenceFileFlag()))
      return false;

   int handle = FileOpen(PersistenceFileName(), FILE_READ | FILE_BIN | PersistenceFileFlag());
   if(handle == INVALID_HANDLE)
      return true; // file exists but couldn't be opened - fileValid stays false

   ulong minSize = (ulong)(sizeof(long) * 2 + sizeof(double) * 2);
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

   dailyStartEquity  = FileReadDouble(handle);
   dailyStartDayCode = FileReadLong(handle);
   equityPeak        = FileReadDouble(handle);
   FileClose(handle);

   fileValid = true;
   return true;
  }

#endif // AUTOBOT_V1_PERSISTENCE_MQH
