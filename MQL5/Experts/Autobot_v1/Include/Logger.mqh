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

void EnsureLogHeader()
  {
   if(FileIsExist(LogFileName(), FILE_COMMON))
      return;

   int handle = FileOpen(LogFileName(), FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "symbol", "event_type", "price", "lots", "sl", "equity", "reason_tag");
   FileClose(handle);
  }

bool LogEvent(string timestamp, string symbol, string eventType, double price, double lots, double sl, double equity, string reasonTag)
  {
   EnsureLogHeader();

   int handle = FileOpen(LogFileName(), FILE_READ | FILE_WRITE | FILE_CSV | FILE_COMMON, ',');
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
