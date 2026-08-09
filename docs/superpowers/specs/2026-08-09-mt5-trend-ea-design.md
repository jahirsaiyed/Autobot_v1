# Design: Autobot v1 — MQL5 Trend-Following EA (Gold, BTCUSD, ETHUSD)

**Date**: 2026-08-09
**Status**: Approved by user, pending implementation plan

## Purpose

A native MQL5 Expert Advisor that trades XAUUSD, BTCUSD, and ETHUSD on a
single MetaTrader 5 account using a multi-timeframe trend-following breakout
strategy, with risk management as a first-class concern rather than an
afterthought. This is v1 — a deliberately scoped-down system meant to be
backtested and validated before any consideration of live/real-money use.

No claim of guaranteed profitability is made or implied anywhere in this
design. The goal is a system with a defensible, testable trading logic and
strict, mechanical risk controls, so that if the strategy has no edge, that
becomes evident in backtesting/forward-testing rather than in a live account.

## Account & Risk Parameters (user-specified)

- Demo account, starting equity: $10,000
- Risk per trade: 1% of current equity
- Daily loss circuit breaker: 5% (based on equity, includes floating P/L)
- Max drawdown circuit breaker: 15% (based on all-time equity high-water mark)

## Instruments

XAUUSD, BTCUSD, ETHUSD — one EA instance, single chart, manages all three
symbols internally via a symbol loop. Not three separate chart instances.

**Correlation note**: BTCUSD and ETHUSD are treated as a correlated group for
portfolio exposure purposes (see Risk Management). XAUUSD is treated as
uncorrelated with the crypto group.

## Architecture

Single EA (`Autobot_v1.mq5`) attached to one chart. On `OnInit()`, state for
each symbol is rebuilt from live positions/history (no reliance on in-memory
state surviving a restart). On every `OnTick()`, the EA loops over its symbol
array and, per symbol: checks trend bias -> checks for a new breakout signal
-> checks risk gates -> manages any existing position's trailing stop ->
executes/logs as needed.

```
MQL5/Experts/Autobot_v1/
├── Autobot_v1.mq5          # Main EA: OnInit, OnTick, OnDeinit
├── Include/
│   ├── Config.mqh          # All tunable inputs (risk %, ATR mults, symbol list)
│   ├── SymbolState.mqh     # Per-symbol state struct
│   ├── TrendFilter.mqh     # H4 EMA200 bias logic
│   ├── EntrySignal.mqh     # Donchian(20) breakout detection on H1
│   ├── RiskManager.mqh     # Position sizing, circuit breakers, exposure cap
│   ├── TradeExecution.mqh  # CTrade wrapper: send/modify/close, retries, slippage guard
│   ├── TrailingStop.mqh    # Breakeven + structure-based trailing
│   ├── Persistence.mqh     # File-based state persistence (daily-start equity, equity peak)
│   ├── Notifier.mqh        # MT5 push notifications + Telegram bot alerts
│   └── Logger.mqh          # Structured CSV trade/event logging
```

**Magic number scheme**: base + symbol offset, e.g. 100001 = XAUUSD,
100002 = BTCUSD, 100003 = ETHUSD. Used to filter the EA's own positions from
any manually-placed trades on the same account.

## Trading Logic

**Bias filter — H4, evaluated once per new H4 bar per symbol**
- Long bias if `Close[H4] > EMA(200, H4)`, short bias if below.
- Deadband filter (config toggle, default on): require price to be at least
  0.1x ATR away from the EMA to count as a clear bias, to avoid chop right at
  the line.

**Entry — H1, evaluated once per new H1 bar per symbol (signal only on bar
close, never intra-bar)**
- Long entry: H1 close breaks above the highest high of the prior 20 H1 bars
  (Donchian(20)), AND H4 bias is long.
- Short entry: mirror condition (lowest low of prior 20 bars), AND H4 bias is
  short.
- Max one open position per symbol at a time. No pyramiding in v1.

**Initial stop loss**: `Entry ± 2.0 x ATR(14, H1)`, sent with the order at
execution time (never a mental/code-only stop).

**Trailing**:
- Phase 1: once unrealized profit >= 1x initial risk, move SL to breakeven +
  small buffer.
- Phase 2: beyond that, trail SL behind the previous H1 bar's swing low
  (longs) / high (shorts), recalculated on each new H1 bar.
- No fixed take-profit.

**Entry filters**:
- Spread guard: skip entry if current spread exceeds a per-symbol configured
  maximum.
- News/economic-calendar filtering: explicitly out of scope for v1 (see
  Scope Boundaries).

## Risk Management

**Position sizing**
```
risk_amount = AccountEquity() * 1%
stop_distance_price = |EntryPrice - StopLossPrice|
value_per_lot = (SYMBOL_TRADE_TICK_VALUE / SYMBOL_TRADE_TICK_SIZE) * stop_distance_price
lots = risk_amount / value_per_lot
```
Rounded down to the broker's volume step, clamped to
`SYMBOL_VOLUME_MIN`/`MAX`, and checked against free margin via
`OrderCalcMargin()`. If the computed size rounds below the minimum tradeable
volume, the trade is skipped and logged (never forced to a min-lot size that
would risk more than 1%).

**Daily loss circuit breaker (5%)**: equity is recorded at the first tick of
each new trading day. If current equity <= that value x 0.95, all *new*
entries are blocked for the rest of the day. Existing open positions continue
to be managed (trailing stops keep running). Resets automatically the next
day. The daily-start equity value is persisted to a file (see Persistence)
so it survives a VPS/terminal restart mid-day.

**Max drawdown circuit breaker (15%)**: an all-time equity high-water mark is
tracked and persisted to a file. If current equity <= peak x 0.85, the EA
disables all new entries entirely. This requires manual re-enable (a config
flag/restart) — it does not auto-resume, since a 15% drawdown is a signal
that something needs human review.

**Portfolio exposure cap**: BTCUSD + ETHUSD are treated as a correlated
group. Combined open risk across that group is capped at 1.5% of equity
(rather than the 2% two independent 1% trades would imply). If a new signal
on one crypto symbol would push the group's combined open risk above 1.5%
given the other symbol's existing open position, the new entry is skipped
and logged — no partial-sizing logic in v1. XAUUSD is not part of this cap
and always sizes independently at 1%. Worst-case simultaneous exposure:
1% (Gold) + 1.5% (BTC+ETH group) = 2.5% of equity across at most 3 concurrent
positions.

## Trade Execution & Order Management

- All order operations go through a `CTrade`-based wrapper
  (`TradeExecution.mqh`), not called directly from signal logic.
- Slippage/deviation guard configured per symbol (wider tolerance for
  BTC/ETH than Gold).
- Retry on transient errors (requote, price-changed, connection hiccups), up
  to a small fixed retry count, then log failure — never an unbounded retry
  loop, never a silently swallowed failure.
- Before sending a new entry, check for an existing open position *or*
  pending order on that symbol+magic number to prevent duplicate entries
  (e.g. after an EA restart mid-bar).
- Every order tagged with a comment encoding the signal reason (e.g.
  `AutoBotV1|TrendBreak|H1`) for post-hoc trade history analysis.
- Stop loss is always attached to the order itself, never managed only in
  EA memory.

## Logging, Alerting, and Persistence

**Logging**: structured CSV in the terminal's `Files/` directory (works in
both live and Strategy Tester runs). Columns: timestamp, symbol, event type
(signal-detected / entry / trail-update / exit / circuit-breaker-tripped /
order-error), price, lots, SL, equity-at-event, signal-reason tag. This
schema is designed to directly support the later backtesting/analysis phase.

**Persistence**: daily-start equity and all-time equity peak are written to
a file (not just `GlobalVariable`), so both values survive a full VPS/machine
reboot, not only an EA/terminal restart.

**Alerting**: both channels enabled —
- MT5 built-in push notifications (to MetaTrader mobile app).
- Telegram bot notifications (bot token supplied via EA input parameter,
  never hardcoded; requires `WebRequest` allow-listing for the Telegram API
  domain in terminal options — a manual one-time setup step).

Alerts fire on: circuit breaker trips (daily loss / max drawdown), order
execution errors, and EA disabled events.

## Testing & Validation Plan (for the upcoming backtesting phase)

Not implemented in v1 build, but the bar this system is being built toward:

- MT5 Strategy Tester with real tick data, target 2-3 years per symbol where
  broker history allows (crypto CFD history will likely be shorter — this
  limitation will be surfaced explicitly, not glossed over).
- Walk-forward validation: in-sample parameter optimization windows,
  out-of-sample unmodified test windows, rolled forward multiple times. A
  strategy that only performs well in-sample is overfit and will be called
  out as such.
- Metrics tracked beyond net profit: max drawdown, Sharpe/Sortino, win rate
  vs average R-multiple, longest losing streak, and result stability across
  differing sub-periods (trending vs choppy years).
- Realistic spread/commission/swap modeling using the actual broker's
  typical figures for these three symbols, not optimistic Strategy Tester
  defaults.

## V1 Scope Boundaries (explicitly excluded)

- News/economic calendar filtering
- Pyramiding / multiple simultaneous positions per symbol
- Self-adaptive/ML-driven parameter tuning ("self-evolution" style
  automation) — a deliberate, human-supervised periodic re-optimization is a
  legitimate v2+ idea; an autonomous black-box version is not being built
  here
- Symbols beyond XAUUSD, BTCUSD, ETHUSD
- On-chart GUI dashboard panel

## Note on Installed Skills

Two Claude Code skills were installed prior to this design: `mql-developer`
(MQL4/MQL5 development reference — used as implementation guidance for the
build phase) and `mt5-trading` (a Python-based strategy skill named "V6.6
Predator" with claims like "Infinite RR" and "0-loss trades"). The second
skill's strategy content is explicitly **not** used as a basis for this
design — its claims are unsubstantiated and its architecture (Python-driven)
doesn't match the native-MQL5 direction chosen here. It remains installed
but is not a dependency of this system.
