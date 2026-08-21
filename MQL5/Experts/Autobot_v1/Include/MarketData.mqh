//+------------------------------------------------------------------+
//| MarketData.mqh - indicator handle lifecycle and data-fetching    |
//| glue. Not unit-tested in isolation - see Task 16 for verification|
//| against real historical data via the Strategy Tester.            |
//+------------------------------------------------------------------+
#property strict
#include "Config.mqh"

#ifndef AUTOBOT_V1_MARKETDATA_MQH
#define AUTOBOT_V1_MARKETDATA_MQH

// Checks the terminal's full symbol list (not just Market Watch) BEFORE
// calling SymbolSelect(). Calling SymbolSelect (or iMA/iATR/SymbolInfoXxx)
// directly with a name the broker doesn't carry at all makes the terminal
// itself log "symbol XXXX does not exist" to the Journal - which MQL5
// Market's automated validator counts as an error even when OnInit handles
// the false return gracefully. Enumerating known names first avoids ever
// passing an unknown name into a resolving call, so that line is never
// emitted for a genuinely-missing symbol like BTCUSD/ETHUSD on a broker
// that doesn't list them.
bool SymbolIsKnownToTerminal(const string symbol)
  {
   int total = SymbolsTotal(false);
   for(int i = 0; i < total; i++)
      if(SymbolName(i, false) == symbol)
         return true;
   return false;
  }

bool CreateIndicatorHandles(const SymbolConfig &configs[], int &emaHandles[], int &atrH4Handles[], int &atrH1Handles[],
                             int emaPeriod, int atrPeriod)
  {
   int n = ArraySize(configs);
   ArrayResize(emaHandles, n);
   ArrayResize(atrH4Handles, n);
   ArrayResize(atrH1Handles, n);

   for(int i = 0; i < n; i++)
     {
      // Disabled symbols (manually via input, or because SymbolSelect
      // couldn't find them on this broker - see OnInit) never reach
      // ComputeH4Bias/ComputeATRH1, so skip handle creation for them
      // entirely rather than letting a missing symbol's indicator-load
      // failure fail OnInit for the whole EA.
      if(!configs[i].enabled)
        {
         emaHandles[i]   = INVALID_HANDLE;
         atrH4Handles[i] = INVALID_HANDLE;
         atrH1Handles[i] = INVALID_HANDLE;
         continue;
        }

      emaHandles[i]   = iMA(configs[i].symbol, PERIOD_H4, emaPeriod, 0, MODE_EMA, PRICE_CLOSE);
      atrH4Handles[i] = iATR(configs[i].symbol, PERIOD_H4, atrPeriod);
      atrH1Handles[i] = iATR(configs[i].symbol, PERIOD_H1, atrPeriod);

      if(emaHandles[i] == INVALID_HANDLE || atrH4Handles[i] == INVALID_HANDLE || atrH1Handles[i] == INVALID_HANDLE)
        {
         PrintFormat("CreateIndicatorHandles: failed for %s", configs[i].symbol);
         return false;
        }
     }
   return true;
  }

void ReleaseIndicatorHandles(int &emaHandles[], int &atrH4Handles[], int &atrH1Handles[])
  {
   for(int i = 0; i < ArraySize(emaHandles); i++)
     {
      IndicatorRelease(emaHandles[i]);
      IndicatorRelease(atrH4Handles[i]);
      IndicatorRelease(atrH1Handles[i]);
     }
  }

// Fetches the last CLOSED H4 bar's close/EMA/ATR (shift=1, not the
// currently-forming bar at shift=0).
bool ComputeH4Bias(string symbol, int emaHandle, int atrH4Handle, double &closeOut, double &emaOut, double &atrOut)
  {
   double closeArr[], emaArr[], atrArr[];

   if(CopyClose(symbol, PERIOD_H4, 1, 1, closeArr) != 1)
      return false;
   if(CopyBuffer(emaHandle, 0, 1, 1, emaArr) != 1)
      return false;
   if(CopyBuffer(atrH4Handle, 0, 1, 1, atrArr) != 1)
      return false;

   closeOut = closeArr[0];
   emaOut   = emaArr[0];
   atrOut   = atrArr[0];
   return true;
  }

// Donchian channel over the `period` bars BEFORE the just-closed bar
// (shift 2..period+1), excluding the just-closed bar itself.
bool ComputeDonchian(string symbol, int period, double &highestHigh, double &lowestLow)
  {
   double highs[], lows[];
   if(CopyHigh(symbol, PERIOD_H1, 2, period, highs) != period)
      return false;
   if(CopyLow(symbol, PERIOD_H1, 2, period, lows) != period)
      return false;

   highestHigh = highs[ArrayMaximum(highs)];
   lowestLow   = lows[ArrayMinimum(lows)];
   return true;
  }

bool ComputeATRH1(int atrH1Handle, double &atrOut)
  {
   double atrArr[];
   if(CopyBuffer(atrH1Handle, 0, 1, 1, atrArr) != 1)
      return false;
   atrOut = atrArr[0];
   return true;
  }

#endif // AUTOBOT_V1_MARKETDATA_MQH
