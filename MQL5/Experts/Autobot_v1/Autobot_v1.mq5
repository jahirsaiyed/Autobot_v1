//+------------------------------------------------------------------+
//|                                                   Autobot_v1.mq5 |
//| Multi-symbol H4-bias / H1-Donchian-breakout trend-following EA.  |
//| See docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md     |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"

#include <Trade\Trade.mqh>
#include "Include/Config.mqh"
#include "Include/SymbolState.mqh"
#include "Include/TrendFilter.mqh"
#include "Include/EntrySignal.mqh"
#include "Include/RiskManager.mqh"
#include "Include/TrailingStop.mqh"
#include "Include/TradeExecution.mqh"
#include "Include/Persistence.mqh"
#include "Include/Logger.mqh"
#include "Include/Notifier.mqh"
#include "Include/MarketData.mqh"

#define TIMER_INTERVAL_SECONDS 5

CTrade       g_trade;
SymbolConfig g_symbolConfigs[];
SymbolState  g_symbolStates[];
int          g_emaHandles[];
int          g_atrH4Handles[];
int          g_atrH1Handles[];

double  g_dailyStartEquity;
long    g_dailyStartDayCode;
bool    g_dailyBreakerTripped;
double  g_equityPeak;
bool    g_maxDrawdownTripped;
bool    g_entriesBlockedPersistenceFailsafe;
datetime g_lastHeartbeat;

// Risk committed to correlated-group (BTC/ETH) symbols earlier in the SAME
// OnTimer pass but not yet visible via PositionsTotal()/PositionGetX (order
// send + position materializing is not instantaneous). Reset at the top of
// every OnTimer() call. See GetOtherCryptoOpenRiskPercent().
double g_pendingCryptoRiskThisPass;

long CurrentDayCode()
  {
   MqlDateTime dt;
   TimeToStruct(TimeTradeServer(), dt);
   return (long)dt.year * 10000 + (long)dt.mon * 100 + dt.day;
  }

bool SelectPositionBySymbolMagic(string symbol, ulong magic)
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) == symbol && (ulong)PositionGetInteger(POSITION_MAGIC) == magic)
         return true;
     }
   return false;
  }

void ReconstructOpenPositionState()
  {
   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
     {
      if(!SelectPositionBySymbolMagic(g_symbolConfigs[i].symbol, g_symbolConfigs[i].magicNumber))
         continue;

      bool   isLong     = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL  = PositionGetDouble(POSITION_SL);

      g_symbolStates[i].entryPrice          = entryPrice;
      g_symbolStates[i].trailPhase          = InferTrailPhase(currentSL, entryPrice, isLong);
      g_symbolStates[i].initialStopDistance = MathAbs(entryPrice - currentSL);
      g_symbolStates[i].riskPercentAtEntry  = InpRiskPercent; // v1 assumption: unchanged since entry
     }
  }

int OnInit()
  {
   // Demo-only guard: v1 is deliberately scoped to demo-account use per the
   // design spec. The Strategy Tester and optimization passes are exempted
   // since they aren't real accounts. This must be the first substantive
   // check in OnInit, before any other setup.
   if(!InpAllowLiveAccount && !MQLInfoInteger(MQL_TESTER) && !MQLInfoInteger(MQL_OPTIMIZATION)
      && AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO)
     {
      Print("Autobot_v1: refusing to run on a non-demo account (v1 is demo-only per design spec). Set InpAllowLiveAccount=true to override.");
      return(INIT_FAILED);
     }

   GetSymbolConfigs(g_symbolConfigs);
   InitSymbolStates(g_symbolStates, g_symbolConfigs);

   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      SymbolSelect(g_symbolConfigs[i].symbol, true);

   if(!CreateIndicatorHandles(g_symbolConfigs, g_emaHandles, g_atrH4Handles, g_atrH1Handles, InpEMAPeriod, InpATRPeriod))
      return(INIT_FAILED);

   double loadedEquity, loadedPeak;
   long   loadedDayCode;
   bool   loadedDailyBreakerTripped, loadedMaxDrawdownTripped;
   bool   fileValid;
   bool   fileFound = LoadPersistedState(loadedEquity, loadedDayCode, loadedPeak,
                                          loadedDailyBreakerTripped, loadedMaxDrawdownTripped, fileValid);

   bool anyPriorDeals = false;
   if(HistorySelect(0, TimeCurrent()))
     {
      for(int i = 0; i < HistoryDealsTotal(); i++)
        {
         ulong dealTicket = HistoryDealGetTicket(i);
         ulong dealMagic  = (ulong)HistoryDealGetInteger(dealTicket, DEAL_MAGIC);
         for(int s = 0; s < ArraySize(g_symbolConfigs); s++)
            if(dealMagic == g_symbolConfigs[s].magicNumber)
               anyPriorDeals = true;
        }
     }

   g_entriesBlockedPersistenceFailsafe = false;
   double nowEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   if(fileFound && !fileValid)
     {
      g_entriesBlockedPersistenceFailsafe = true;
      g_dailyStartEquity    = nowEquity;
      g_dailyStartDayCode   = CurrentDayCode();
      g_equityPeak          = nowEquity;
      // We can't trust anything in this branch - stay maximally
      // conservative on both breaker flags, not just max-drawdown.
      g_dailyBreakerTripped = true;
      g_maxDrawdownTripped  = true;
      SendAlert("Autobot_v1: persistence file corrupt on startup - new entries BLOCKED pending manual review.",
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
     }
   else if(!fileFound && anyPriorDeals)
     {
      g_entriesBlockedPersistenceFailsafe = true;
      g_dailyStartEquity    = nowEquity;
      g_dailyStartDayCode   = CurrentDayCode();
      g_equityPeak          = nowEquity;
      g_dailyBreakerTripped = true;
      g_maxDrawdownTripped  = true;
      SendAlert("Autobot_v1: persistence file missing but trade history exists - new entries BLOCKED pending manual review.",
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
     }
   else if(fileFound && fileValid)
     {
      g_dailyStartEquity  = loadedEquity;
      g_dailyStartDayCode = loadedDayCode;
      g_equityPeak        = loadedPeak;

      if(loadedDayCode != CurrentDayCode())
        {
         // A new day has started since the file was written - mirror
         // OnTimer's day-rollover logic. Yesterday's daily trip must never
         // carry into today.
         g_dailyStartEquity    = nowEquity;
         g_dailyStartDayCode   = CurrentDayCode();
         g_dailyBreakerTripped = false;
        }
      else
         g_dailyBreakerTripped = loadedDailyBreakerTripped;

      // Sticky across restarts unless a human explicitly clears it via
      // InpClearMaxDrawdownBreaker - a restart alone must never clear it.
      g_maxDrawdownTripped = InpClearMaxDrawdownBreaker ? false : loadedMaxDrawdownTripped;

      // Persist immediately whenever this branch changes what's on disk
      // relative to what was loaded: day-rollover reset, the override
      // clearing a trip, OR (found by independent review) a fresh
      // dailyStartDayCode - without that last check, a SECOND restart
      // later the same day would reload the still-stale (yesterday's)
      // file, see loadedDayCode != today AGAIN, and silently re-derive a
      // brand new "start of day" baseline from whatever equity exists at
      // THAT restart - quietly moving the daily-loss breaker's reference
      // point mid-day and potentially masking a real loss that happened
      // between the two restarts.
      if(g_dailyStartDayCode != loadedDayCode
         || g_dailyBreakerTripped != loadedDailyBreakerTripped
         || g_maxDrawdownTripped != loadedMaxDrawdownTripped)
        {
         if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
            Print("Autobot_v1: WARNING - failed to persist state after OnInit restore. A second restart before the next successful save could re-derive a stale daily baseline or re-trip a manually-cleared breaker.");
        }
     }
   else
     {
      g_dailyStartEquity    = nowEquity;
      g_dailyStartDayCode   = CurrentDayCode();
      g_equityPeak          = nowEquity;
      g_dailyBreakerTripped = false;
      g_maxDrawdownTripped  = false;
      if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
         Print("Autobot_v1: WARNING - failed to persist state on genuine first run.");
     }

   ReconstructOpenPositionState();

   g_lastHeartbeat = TimeCurrent();
   g_pendingCryptoRiskThisPass = 0.0;

   if(!EventSetTimer(TIMER_INTERVAL_SECONDS))
     {
      Print("OnInit: EventSetTimer failed");
      return(INIT_FAILED);
     }

   PrintFormat("Autobot_v1 initialized. dailyStartEquity=%.2f equityPeak=%.2f persistenceFailsafe=%s",
               g_dailyStartEquity, g_equityPeak, g_entriesBlockedPersistenceFailsafe ? "true" : "false");
   return(INIT_SUCCEEDED);
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   ReleaseIndicatorHandles(g_emaHandles, g_atrH4Handles, g_atrH1Handles);
  }

void OnTick()
  {
   // Intentionally minimal - OnTick only fires for the chart's own symbol.
   // The multi-symbol loop runs on OnTimer (see spec Architecture section).
  }

// Fires on every deal (fill), including closes. Used only to log the
// "exit" event for our own symbols/magics - entries are already logged in
// ProcessSymbol at the point the order is sent.
void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   ulong dealMagic = (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC);
   bool isOurs = false;
   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      if(dealMagic == g_symbolConfigs[i].magicNumber)
         isOurs = true;
   if(!isOurs)
      return;

   ENUM_DEAL_ENTRY entry = (ENUM_DEAL_ENTRY)HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(entry != DEAL_ENTRY_OUT && entry != DEAL_ENTRY_OUT_BY)
      return; // only closing deals - entries are already logged in ProcessSymbol

   string symbol = HistoryDealGetString(trans.deal, DEAL_SYMBOL);
   double price  = HistoryDealGetDouble(trans.deal, DEAL_PRICE);
   double profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
   double volume = HistoryDealGetDouble(trans.deal, DEAL_VOLUME);

   LogEvent(TimeToString(TimeCurrent()), symbol, "exit", price, volume, 0.0, AccountInfoDouble(ACCOUNT_EQUITY),
            StringFormat("profit=%.2f", profit));
  }

// Returns the larger of: (a) the OTHER correlated-group symbol's live open
// risk (from an already-materialized position), or (b) risk committed to a
// correlated-group symbol earlier in this SAME OnTimer pass whose position
// may not have materialized in PositionsTotal() yet. Without (b), two
// crypto signals firing in the same pass could both read "no other position
// open" and both pass the cap check, exceeding InpCorrelatedCapPercent.
double GetOtherCryptoOpenRiskPercent(int idx)
  {
   double liveRisk = 0.0;
   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
     {
      if(i == idx || !g_symbolConfigs[i].isCorrelatedGroup)
         continue;
      if(SelectPositionBySymbolMagic(g_symbolConfigs[i].symbol, g_symbolConfigs[i].magicNumber))
         liveRisk = g_symbolStates[i].riskPercentAtEntry;
     }
   return MathMax(liveRisk, g_pendingCryptoRiskThisPass);
  }

void ManageOpenPosition(int idx)
  {
   string symbol = g_symbolConfigs[idx].symbol;
   ulong  magic  = g_symbolConfigs[idx].magicNumber;

   if(!SelectPositionBySymbolMagic(symbol, magic))
      return;

   ulong  ticket        = (ulong)PositionGetInteger(POSITION_TICKET);
   bool   isLong        = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double entryPrice    = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL     = PositionGetDouble(POSITION_SL);
   double currentPrice  = isLong ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);

   double unrealizedProfitPrice = isLong ? (currentPrice - entryPrice) : (entryPrice - currentPrice);

   if(g_symbolStates[idx].trailPhase == TRAIL_PHASE_1_BREAKEVEN)
     {
      if(ShouldMoveToBreakeven(unrealizedProfitPrice, g_symbolStates[idx].initialStopDistance))
        {
         double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double buffer = InpBreakevenBufferPoints * point;
         double newSL  = CalculateBreakevenSL(entryPrice, isLong, buffer);
         newSL = NormalizeAndClampStopLoss(symbol, newSL, isLong);

         // Guard added after independent review: on a broker whose
         // stops/freeze level is unusually large relative to this trade's
         // initial risk, the clamp above can pull the intended breakeven
         // SL back past the position's CURRENT (original entry) stop -
         // i.e. it could silently loosen risk instead of locking in
         // breakeven. Only modify if the clamped result still genuinely
         // improves on the current SL; otherwise skip this tick and retry
         // on the next one (mirrors the structure-trail branch below).
         bool improves = isLong ? (newSL > currentSL) : (newSL < currentSL);
         if(improves)
           {
            bool modified = g_trade.PositionModify(ticket, newSL, 0.0);
            if(modified)
              {
               g_symbolStates[idx].trailPhase = TRAIL_PHASE_2_STRUCTURE;
               LogEvent(TimeToString(TimeCurrent()), symbol, "trail-update", currentPrice, 0, newSL, currentEquity, "breakeven-move");
              }
            else
               LogEvent(TimeToString(TimeCurrent()), symbol, "trail-update-failed", currentPrice, 0, newSL, currentEquity,
                        StringFormat("breakeven-move-retcode-%u", g_trade.ResultRetcode()));
           }
        }
      return;
     }

   double priorBarLow  = iLow(symbol, PERIOD_H1, 1);
   double priorBarHigh = iHigh(symbol, PERIOD_H1, 1);
   double newTrailSL   = CalculateStructureTrailSL(priorBarLow, priorBarHigh, isLong);
   newTrailSL = NormalizeAndClampStopLoss(symbol, newTrailSL, isLong);

   bool improves = isLong ? (newTrailSL > currentSL) : (newTrailSL < currentSL);
   if(improves)
     {
      bool modified = g_trade.PositionModify(ticket, newTrailSL, 0.0);
      if(modified)
         LogEvent(TimeToString(TimeCurrent()), symbol, "trail-update", currentPrice, 0, newTrailSL, currentEquity, "structure-trail");
      else
         LogEvent(TimeToString(TimeCurrent()), symbol, "trail-update-failed", currentPrice, 0, newTrailSL, currentEquity,
                  StringFormat("structure-trail-retcode-%u", g_trade.ResultRetcode()));
     }
  }

void ProcessSymbol(int idx, bool newEntriesAllowed, double currentEquity)
  {
   string symbol = g_symbolConfigs[idx].symbol;
   ulong  magic  = g_symbolConfigs[idx].magicNumber;

   ManageOpenPosition(idx);

   if(!newEntriesAllowed)
      return;
   if(HasExistingPositionOrOrder(symbol, magic))
      return;

   datetime latestH1Bar = iTime(symbol, PERIOD_H1, 0);
   if(latestH1Bar == g_symbolStates[idx].lastH1BarTime)
      return; // already evaluated this bar
   g_symbolStates[idx].lastH1BarTime = latestH1Bar;

   double spread = (double)SymbolInfoInteger(symbol, SYMBOL_SPREAD);
   if(spread > g_symbolConfigs[idx].maxSpreadPoints)
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "entry-skipped-spread", 0, 0, 0, currentEquity, "spread-guard");
      return;
     }

   double h4Close, h4Ema, h4Atr;
   if(!ComputeH4Bias(symbol, g_emaHandles[idx], g_atrH4Handles[idx], h4Close, h4Ema, h4Atr))
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "signal-skipped-data-unavailable", 0, 0, 0, currentEquity, "compute-h4-bias-failed");
      return;
     }

   ENUM_BIAS bias = DetermineBias(h4Close, h4Ema, h4Atr, InpDeadbandATRMultiplier);
   g_symbolStates[idx].bias = bias;
   if(bias == BIAS_NONE)
      return;

   double h1Close = iClose(symbol, PERIOD_H1, 1);
   double priorHigh, priorLow;
   if(!ComputeDonchian(symbol, InpDonchianPeriod, priorHigh, priorLow))
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "signal-skipped-data-unavailable", 0, 0, 0, currentEquity, "compute-donchian-failed");
      return;
     }

   ENUM_SIGNAL signal = DetectBreakout(h1Close, priorHigh, priorLow, bias);
   if(signal == SIGNAL_NONE)
      return;

   double atrH1;
   if(!ComputeATRH1(g_atrH1Handles[idx], atrH1))
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "signal-skipped-data-unavailable", 0, 0, 0, currentEquity, "compute-atr-failed");
      return;
     }

   bool   isLong      = (signal == SIGNAL_LONG_BREAKOUT);
   double entryPrice  = isLong ? SymbolInfoDouble(symbol, SYMBOL_ASK) : SymbolInfoDouble(symbol, SYMBOL_BID);
   double stopDistance = InpATRStopMultiplier * atrH1;
   double stopLoss     = isLong ? (entryPrice - stopDistance) : (entryPrice + stopDistance);

   if(g_symbolConfigs[idx].isCorrelatedGroup)
     {
      double otherRisk = GetOtherCryptoOpenRiskPercent(idx);
      if(!CanOpenCryptoPosition(otherRisk, InpRiskPercent, InpCorrelatedCapPercent))
        {
         LogEvent(TimeToString(TimeCurrent()), symbol, "entry-skipped-exposure-cap", entryPrice, 0, stopLoss, currentEquity, "correlated-cap");
         return;
        }
     }

   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE_PROFIT);
   double tickSize  = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   double volStep   = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double volMin    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double volMax    = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);

   bool   skipped;
   double lots = CalculateLotSize(currentEquity, InpRiskPercent, stopDistance, tickValue, tickSize, volStep, volMin, volMax, skipped);
   if(skipped)
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "entry-skipped-min-lot", entryPrice, 0, stopLoss, currentEquity, "sizing-below-minimum");
      return;
     }

   double marginRequired;
   if(!OrderCalcMargin(isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL, symbol, lots, entryPrice, marginRequired))
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "entry-skipped-margin-calc-failed", entryPrice, lots, stopLoss, currentEquity, "order-calc-margin-failed");
      return;
     }
   if(marginRequired > AccountInfoDouble(ACCOUNT_MARGIN_FREE))
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "entry-skipped-margin", entryPrice, lots, stopLoss, currentEquity, "insufficient-margin");
      return;
     }

   stopLoss = NormalizeAndClampStopLoss(symbol, stopLoss, isLong);

   string comment = "AutoBotV1|TrendBreak|H1";
   bool sent = ExecuteMarketOrder(g_trade, symbol, isLong ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,
                                   lots, stopLoss, magic, comment,
                                   g_symbolConfigs[idx].slippagePoints, InpMaxRetries);

   if(sent)
     {
      g_symbolStates[idx].trailPhase          = TRAIL_PHASE_1_BREAKEVEN;
      g_symbolStates[idx].initialStopDistance = stopDistance;
      g_symbolStates[idx].entryPrice          = entryPrice;
      g_symbolStates[idx].riskPercentAtEntry  = InpRiskPercent;
      if(g_symbolConfigs[idx].isCorrelatedGroup)
         g_pendingCryptoRiskThisPass += InpRiskPercent;
      LogEvent(TimeToString(TimeCurrent()), symbol, "entry", entryPrice, lots, stopLoss, currentEquity, comment);
     }
   else
     {
      LogEvent(TimeToString(TimeCurrent()), symbol, "order-error", entryPrice, lots, stopLoss, currentEquity, "execute-failed");
      SendAlert(StringFormat("Autobot_v1: order execution failed on %s", symbol), InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
     }
  }

void MaybeSendHeartbeat()
  {
   if(TimeCurrent() - g_lastHeartbeat < InpHeartbeatHours * 3600)
      return;
   g_lastHeartbeat = TimeCurrent();
   SendAlert("Autobot_v1: heartbeat - EA is running.", InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
  }

void OnTimer()
  {
   double currentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_pendingCryptoRiskThisPass = 0.0;

   long today = CurrentDayCode();
   if(today != g_dailyStartDayCode)
     {
      g_dailyStartDayCode   = today;
      g_dailyStartEquity    = currentEquity;
      g_dailyBreakerTripped = false;
      // Freeze persistence while the fail-safe is active: the in-memory
      // baseline was fabricated from current equity (true peak unknown),
      // and writing it to disk would permanently cement a wrong baseline -
      // even after a human "fixes" the file and restarts. Leave the file
      // exactly as found until a human clears the fail-safe.
      if(!g_entriesBlockedPersistenceFailsafe)
        {
         if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
            Print("Autobot_v1: WARNING - failed to persist state on day rollover.");
        }
     }

   bool wasDailyBreakerTripped = g_dailyBreakerTripped;
   g_dailyBreakerTripped = UpdateDailyBreakerState(g_dailyBreakerTripped, g_dailyStartEquity, currentEquity, InpDailyLossPercent);
   if(g_dailyBreakerTripped && !wasDailyBreakerTripped)
     {
      LogEvent(TimeToString(TimeCurrent()), "ACCOUNT", "circuit-breaker-tripped", 0, 0, 0, currentEquity, "daily-loss");
      SendAlert(StringFormat("Autobot_v1: DAILY LOSS circuit breaker tripped. Start=%.2f Current=%.2f. New entries disabled for the rest of the day.",
                             g_dailyStartEquity, currentEquity),
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
      // Make the trip durable immediately rather than waiting for the next
      // scheduled save point (day-rollover or peak-update).
      if(!g_entriesBlockedPersistenceFailsafe)
        {
         if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
           {
            Print("Autobot_v1: WARNING - failed to persist DAILY LOSS breaker trip. Trip is active in memory but not yet durable on disk.");
            SendAlert("Autobot_v1: WARNING - failed to persist the daily-loss circuit breaker trip to disk.",
                      InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
           }
        }
     }

   double previousPeak = g_equityPeak;
   g_equityPeak = UpdateEquityPeak(g_equityPeak, currentEquity);
   if(g_equityPeak != previousPeak && !g_entriesBlockedPersistenceFailsafe)
     {
      if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
         Print("Autobot_v1: WARNING - failed to persist updated equity peak.");
     }

   bool wasMaxDDTripped = g_maxDrawdownTripped;
   g_maxDrawdownTripped = g_maxDrawdownTripped || IsMaxDrawdownTripped(g_equityPeak, currentEquity, InpMaxDrawdownPercent);
   if(g_maxDrawdownTripped && !wasMaxDDTripped)
     {
      LogEvent(TimeToString(TimeCurrent()), "ACCOUNT", "circuit-breaker-tripped", 0, 0, 0, currentEquity, "max-drawdown");
      SendAlert(StringFormat("Autobot_v1: MAX DRAWDOWN circuit breaker tripped. Peak=%.2f Current=%.2f. New entries disabled - manual re-enable required.",
                             g_equityPeak, currentEquity),
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
      // Make the trip durable immediately rather than waiting for the next
      // scheduled save point.
      if(!g_entriesBlockedPersistenceFailsafe)
        {
         if(!SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped))
           {
            Print("Autobot_v1: WARNING - failed to persist MAX DRAWDOWN breaker trip. Trip is active in memory but not yet durable on disk.");
            SendAlert("Autobot_v1: WARNING - failed to persist the max-drawdown circuit breaker trip to disk.",
                      InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
           }
        }
     }

   bool newEntriesAllowed = !g_dailyBreakerTripped && !g_maxDrawdownTripped && !g_entriesBlockedPersistenceFailsafe;

   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      ProcessSymbol(i, newEntriesAllowed, currentEquity);

   MaybeSendHeartbeat();
  }
