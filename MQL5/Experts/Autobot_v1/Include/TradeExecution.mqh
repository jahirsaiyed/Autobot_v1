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

#endif // AUTOBOT_V1_TRADEEXECUTION_MQH
