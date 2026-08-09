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
   GetSymbolConfigs(g_symbolConfigs);
   InitSymbolStates(g_symbolStates, g_symbolConfigs);

   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      SymbolSelect(g_symbolConfigs[i].symbol, true);

   if(!CreateIndicatorHandles(g_symbolConfigs, g_emaHandles, g_atrH4Handles, g_atrH1Handles, InpEMAPeriod, InpATRPeriod))
      return(INIT_FAILED);

   double loadedEquity, loadedPeak;
   long   loadedDayCode;
   bool   fileValid;
   bool   fileFound = LoadPersistedState(loadedEquity, loadedDayCode, loadedPeak, fileValid);

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
      g_dailyStartEquity  = nowEquity;
      g_dailyStartDayCode = CurrentDayCode();
      g_equityPeak        = nowEquity;
      SendAlert("Autobot_v1: persistence file corrupt on startup - new entries BLOCKED pending manual review.",
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
     }
   else if(!fileFound && anyPriorDeals)
     {
      g_entriesBlockedPersistenceFailsafe = true;
      g_dailyStartEquity  = nowEquity;
      g_dailyStartDayCode = CurrentDayCode();
      g_equityPeak        = nowEquity;
      SendAlert("Autobot_v1: persistence file missing but trade history exists - new entries BLOCKED pending manual review.",
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
     }
   else if(fileFound && fileValid)
     {
      g_dailyStartEquity  = loadedEquity;
      g_dailyStartDayCode = loadedDayCode;
      g_equityPeak        = loadedPeak;
     }
   else
     {
      g_dailyStartEquity  = nowEquity;
      g_dailyStartDayCode = CurrentDayCode();
      g_equityPeak        = nowEquity;
      SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak);
     }

   g_dailyBreakerTripped = false;
   if(g_entriesBlockedPersistenceFailsafe)
      // The in-memory equityPeak above was seeded from current equity, not
      // the true historical peak (which is unknown - the file was corrupt
      // or missing). Computing IsMaxDrawdownTripped against a fabricated
      // peak would always report "not tripped". Stay conservative until a
      // human clears the fail-safe.
      g_maxDrawdownTripped = true;
   else
      g_maxDrawdownTripped = IsMaxDrawdownTripped(g_equityPeak, nowEquity, InpMaxDrawdownPercent);

   ReconstructOpenPositionState();

   g_lastHeartbeat = TimeCurrent();

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

double GetOtherCryptoOpenRiskPercent(int idx)
  {
   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
     {
      if(i == idx || !g_symbolConfigs[i].isCorrelatedGroup)
         continue;
      if(SelectPositionBySymbolMagic(g_symbolConfigs[i].symbol, g_symbolConfigs[i].magicNumber))
         return g_symbolStates[i].riskPercentAtEntry;
     }
   return 0.0;
  }

void ManageOpenPosition(int idx)
  {
   string symbol = g_symbolConfigs[idx].symbol;
   ulong  magic  = g_symbolConfigs[idx].magicNumber;

   if(!SelectPositionBySymbolMagic(symbol, magic))
      return;

   ulong  ticket       = (ulong)PositionGetInteger(POSITION_TICKET);
   bool   isLong       = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY);
   double entryPrice   = PositionGetDouble(POSITION_PRICE_OPEN);
   double currentSL    = PositionGetDouble(POSITION_SL);
   double currentPrice = isLong ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);

   double unrealizedProfitPrice = isLong ? (currentPrice - entryPrice) : (entryPrice - currentPrice);

   if(g_symbolStates[idx].trailPhase == TRAIL_PHASE_1_BREAKEVEN)
     {
      if(ShouldMoveToBreakeven(unrealizedProfitPrice, g_symbolStates[idx].initialStopDistance))
        {
         double point  = SymbolInfoDouble(symbol, SYMBOL_POINT);
         double buffer = InpBreakevenBufferPoints * point;
         double newSL  = CalculateBreakevenSL(entryPrice, isLong, buffer);
         if(g_trade.PositionModify(ticket, newSL, 0.0))
            g_symbolStates[idx].trailPhase = TRAIL_PHASE_2_STRUCTURE;
        }
      return;
     }

   double priorBarLow  = iLow(symbol, PERIOD_H1, 1);
   double priorBarHigh = iHigh(symbol, PERIOD_H1, 1);
   double newTrailSL   = CalculateStructureTrailSL(priorBarLow, priorBarHigh, isLong);

   bool improves = isLong ? (newTrailSL > currentSL) : (newTrailSL < currentSL);
   if(improves)
      g_trade.PositionModify(ticket, newTrailSL, 0.0);
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
      return;

   ENUM_BIAS bias = DetermineBias(h4Close, h4Ema, h4Atr, InpDeadbandATRMultiplier);
   g_symbolStates[idx].bias = bias;
   if(bias == BIAS_NONE)
      return;

   double h1Close = iClose(symbol, PERIOD_H1, 1);
   double priorHigh, priorLow;
   if(!ComputeDonchian(symbol, InpDonchianPeriod, priorHigh, priorLow))
      return;

   ENUM_SIGNAL signal = DetectBreakout(h1Close, priorHigh, priorLow, bias);
   if(signal == SIGNAL_NONE)
      return;

   double atrH1;
   if(!ComputeATRH1(g_atrH1Handles[idx], atrH1))
      return;

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
         SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak);
     }

   g_dailyBreakerTripped = UpdateDailyBreakerState(g_dailyBreakerTripped, g_dailyStartEquity, currentEquity, InpDailyLossPercent);

   double previousPeak = g_equityPeak;
   g_equityPeak = UpdateEquityPeak(g_equityPeak, currentEquity);
   if(g_equityPeak != previousPeak && !g_entriesBlockedPersistenceFailsafe)
      SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak);

   bool wasMaxDDTripped = g_maxDrawdownTripped;
   g_maxDrawdownTripped = g_maxDrawdownTripped || IsMaxDrawdownTripped(g_equityPeak, currentEquity, InpMaxDrawdownPercent);
   if(g_maxDrawdownTripped && !wasMaxDDTripped)
      SendAlert(StringFormat("Autobot_v1: MAX DRAWDOWN circuit breaker tripped. Peak=%.2f Current=%.2f. New entries disabled - manual re-enable required.",
                             g_equityPeak, currentEquity),
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);

   bool newEntriesAllowed = !g_dailyBreakerTripped && !g_maxDrawdownTripped && !g_entriesBlockedPersistenceFailsafe;

   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      ProcessSymbol(i, newEntriesAllowed, currentEquity);

   MaybeSendHeartbeat();
  }
