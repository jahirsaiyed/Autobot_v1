#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TradeExecution.mqh"

#define TEST_MAGIC 999999
#define TEST_SYMBOL "BTCUSD"
// BTCUSD chosen over a forex pair (e.g. EURUSD) because forex markets are
// closed on weekends - a pending-order test would fail with "market closed"
// whenever run on a Saturday/Sunday. BTCUSD/ETHUSD trade continuously (see
// spec's weekend-gap discussion), and it's also one of this EA's own three
// traded symbols, so it's guaranteed to be selected in Market Watch already.

void OnStart()
  {
   T_ResetCounters();

   // --- Pure logic: ShouldRetry ---
   T_AssertTrue("transient error retries when attempts remain",
                ShouldRetry(TRADE_RETCODE_REQUOTE, 0, 3) == true);
   T_AssertTrue("transient error stops retrying once exhausted",
                ShouldRetry(TRADE_RETCODE_REQUOTE, 3, 3) == false);
   T_AssertTrue("non-transient error never retries",
                ShouldRetry(TRADE_RETCODE_INVALID_VOLUME, 0, 3) == false);

   // --- Live-state: HasExistingPositionOrOrder ---
   // SAFETY GUARD: never run this against a live account.
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
     {
      T_AssertTrue("ABORTED: connected account is not a demo account", false,
                   "refusing to place a test order on a non-demo account");
      T_PrintSummary("Test_TradeExecution");
      return;
     }

   T_AssertTrue("no test order exists initially", HasExistingPositionOrOrder(TEST_SYMBOL, TEST_MAGIC) == false);

   if(!SymbolSelect(TEST_SYMBOL, true))
     {
      T_AssertTrue(StringFormat("%s could not be selected in Market Watch", TEST_SYMBOL), false);
      T_PrintSummary("Test_TradeExecution");
      return;
     }

   double bid = SymbolInfoDouble(TEST_SYMBOL, SYMBOL_BID);
   // Percentage-based offset, not point-based: a fixed point count means
   // very different real distances across instruments/price scales (e.g.
   // 1000 points is negligible on a $60,000+ BTC price but huge on a $2,000
   // Gold price). 5% below current bid is comfortably far from market for
   // any of this EA's instruments without relying on point-size assumptions.
   double farBelowPrice = NormalizeDouble(bid * 0.95, (int)SymbolInfoInteger(TEST_SYMBOL, SYMBOL_DIGITS));

   CTrade trade;
   trade.SetExpertMagicNumber(TEST_MAGIC);
   bool placed = trade.BuyLimit(SymbolInfoDouble(TEST_SYMBOL, SYMBOL_VOLUME_MIN), farBelowPrice, TEST_SYMBOL,
                                 0.0, 0.0, ORDER_TIME_GTC, 0, "Autobot_v1 test order");
   T_AssertTrue("test pending order placed", placed);

   T_AssertTrue("HasExistingPositionOrOrder now true", HasExistingPositionOrOrder(TEST_SYMBOL, TEST_MAGIC) == true);

   // Cleanup: find and delete the pending order we just placed.
   for(int i = OrdersTotal() - 1; i >= 0; i--)
     {
      ulong ticket = OrderGetTicket(i);
      if(ticket != 0 && OrderGetString(ORDER_SYMBOL) == TEST_SYMBOL && (ulong)OrderGetInteger(ORDER_MAGIC) == TEST_MAGIC)
         trade.OrderDelete(ticket);
     }

   T_AssertTrue("HasExistingPositionOrOrder false again after cleanup", HasExistingPositionOrOrder(TEST_SYMBOL, TEST_MAGIC) == false);

   T_PrintSummary("Test_TradeExecution");
  }
