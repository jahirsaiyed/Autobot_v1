//+------------------------------------------------------------------+
//| Logger.mqh - structured CSV event logging                        |
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_LOGGER_MQH
#define AUTOBOT_V1_LOGGER_MQH

string LogFileName()
  {
   return "Autobot_v1_log.csv";
  }

// FILE_COMMON is shared machine-wide across every terminal install AND the
// Strategy Tester - never isolated per live-account deployment. Using it
// unconditionally would mix backtest log rows into the live/demo trade
// journal (and vice versa). Only use FILE_COMMON for genuine live/demo
// runs; inside the Strategy Tester or an optimization pass, use a plain
// (non-common) file, which MT5 sandboxes per Tester agent.
int LogFileFlag()
  {
   bool inTesterOrOptimization = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   return inTesterOrOptimization ? 0 : FILE_COMMON;
  }

void EnsureLogHeader()
  {
   if(FileIsExist(LogFileName(), LogFileFlag()))
      return;

   int handle = FileOpen(LogFileName(), FILE_WRITE | FILE_CSV | LogFileFlag(), ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "symbol", "event_type", "price", "lots", "sl", "equity", "reason_tag");
   FileClose(handle);
  }

bool LogEvent(string timestamp, string symbol, string eventType, double price, double lots, double sl, double equity, string reasonTag)
  {
   EnsureLogHeader();

   int handle = FileOpen(LogFileName(), FILE_READ | FILE_WRITE | FILE_CSV | LogFileFlag(), ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, timestamp, symbol, eventType, DoubleToString(price, 5),
             DoubleToString(lots, 2), DoubleToString(sl, 5),
             DoubleToString(equity, 2), reasonTag);
   FileClose(handle);
   return true;
  }

#endif // AUTOBOT_V1_LOGGER_MQH
