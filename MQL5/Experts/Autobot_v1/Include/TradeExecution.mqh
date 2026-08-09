//+------------------------------------------------------------------+
//| TradeExecution.mqh - CTrade wrapper: retries, dup-check, SL      |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

// Include guard: MQL5 has no #pragma once and no automatic double-include
// protection. Trade.mqh guards itself, but this header may still be
// included from multiple compile units (EA + test scripts), so guard it
// the same way as our other headers.
#ifndef AUTOBOT_V1_TRADEEXECUTION_MQH
#define AUTOBOT_V1_TRADEEXECUTION_MQH

bool ShouldRetry(uint retcode, int attemptCount, int maxRetries)
  {
   if(attemptCount >= maxRetries)
      return false;

   switch(retcode)
     {
      case TRADE_RETCODE_REQUOTE:
      case TRADE_RETCODE_PRICE_CHANGED:
      case TRADE_RETCODE_PRICE_OFF:
      case TRADE_RETCODE_CONNECTION:
      case TRADE_RETCODE_TIMEOUT:
         return true;
      default:
         return false;
     }
  }

bool HasExistingPositionOrOrder(string symbol, ulong magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
     }

   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket == 0)
         continue;
      if(OrderGetString(ORDER_SYMBOL) == symbol && (ulong)OrderGetInteger(ORDER_MAGIC) == magic)
         return true;
     }

   return false;
  }

// Always attaches SL to the order itself (never a mental/code-only stop).
// Retries up to maxRetries on transient errors per ShouldRetry(), then
// gives up and returns false - callers must log the failure, never swallow it.
bool ExecuteMarketOrder(CTrade &trade, string symbol, ENUM_ORDER_TYPE orderType,
                         double lots, double stopLoss, ulong magic, string comment,
                         int deviationPoints, int maxRetries)
  {
   trade.SetExpertMagicNumber(magic);
   trade.SetDeviationInPoints(deviationPoints);

   for(int attempt = 0; attempt < maxRetries; attempt++)
     {
      bool sent;
      if(orderType == ORDER_TYPE_BUY)
         sent = trade.Buy(lots, symbol, 0.0, stopLoss, 0.0, comment);
      else if(orderType == ORDER_TYPE_SELL)
         sent = trade.Sell(lots, symbol, 0.0, stopLoss, 0.0, comment);
      else
         return false; // only market buy/sell supported in v1

      if(sent)
         return true;

      uint retcode = trade.ResultRetcode();
      if(!ShouldRetry(retcode, attempt, maxRetries))
        {
         PrintFormat("ExecuteMarketOrder: giving up on %s after %d attempt(s), retcode=%u",
                     symbol, attempt + 1, retcode);
         return false;
        }
     }

   return false;
  }

// --- Stop-loss normalization / stops-level & freeze-level clamp --------

// Pure function: clamps a proposed SL to be at least minDistance away from
// currentPrice on the correct side, and returns it pre-rounded to digits.
// (Rounding via NormalizeDouble happens here since NormalizeDouble itself
// is fine to call from a pure function - it's pure math, not an MT5
// API/state call.)
double ClampStopLossToMinDistance(double stopLoss, bool isLong, double currentPrice, double minDistance, int digits)
  {
   double clamped = stopLoss;
   if(isLong)
     {
      double maxAllowed = currentPrice - minDistance;
      if(clamped > maxAllowed)
         clamped = maxAllowed;
     }
   else
     {
      double minAllowed = currentPrice + minDistance;
      if(clamped < minAllowed)
         clamped = minAllowed;
     }
   return NormalizeDouble(clamped, digits);
  }

// Glue: fetches live symbol properties and current price, then clamps.
double NormalizeAndClampStopLoss(string symbol, double stopLoss, bool isLong)
  {
   int    digits           = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point            = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stopsLevelPoints = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double freezeLevelPoints = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance      = MathMax(stopsLevelPoints, freezeLevelPoints) * point;
   double currentPrice     = isLong ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   return ClampStopLossToMinDistance(stopLoss, isLong, currentPrice, minDistance, digits);
  }

#endif // AUTOBOT_V1_TRADEEXECUTION_MQH
