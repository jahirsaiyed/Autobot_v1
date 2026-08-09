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
state surviving a restart). **Correction from initial draft**: `OnTick()`
only fires for the chart's own symbol, not for the EA's other tracked
symbols — so a chart attached to XAUUSD would never reliably process
BTCUSD/ETHUSD ticks via `OnTick()`. The EA instead uses `OnTimer()` (e.g.
every 2-5 seconds via `EventSetTimer()`) as its main loop, iterating over the
symbol array on each timer fire and, per symbol: checks trend bias -> checks
for a new breakout signal -> checks risk gates -> manages any existing
position's trailing stop -> executes/logs as needed. `OnTick()` is still
implemented (required by the platform) but only used for lightweight
chart-symbol-specific bookkeeping, not the core multi-symbol loop.

```
MQL5/Experts/Autobot_v1/
├── Autobot_v1.mq5          # Main EA: OnInit, OnTimer (main loop), OnTick, OnDeinit
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

**Expected behavior, stated explicitly so it isn't mistaken for a bug**:
Donchian-breakout systems with an H4 trend filter are well known to whipsaw
in ranging regimes — the H4 bias can stay "long" for weeks while price
ranges below/around it, producing repeated false H1 breakouts that each take
a ~2xATR stop-out. The 0.1x ATR EMA deadband (above) only filters chop right
at the bias line; it does nothing once bias is established and price ranges
away from it. This strategy family typically runs a ~35-45% win rate, with
profitability (if any) coming from occasional large trend-following winners,
not from a high hit rate. Backtesting will show whether chop-driven
whipsaw is severe enough on these three symbols to warrant an added regime
filter (e.g. an ADX threshold) in v1.1 — deliberately not built into v1 to
avoid adding an untested parameter before there's data showing it's needed.

**Initial stop loss**: `Entry ± 2.0 x ATR(14, H1)`, sent with the order at
execution time (never a mental/code-only stop). Note: ATR(14) is a lagging
average and will under-react during sudden volatility spikes (flash moves,
liquidity gaps) and over-react during a volatility collapse — worst on
BTC/ETH given their cluster-volatility behavior. Accepted as a known
limitation for v1; not adding a secondary realized-vol clamp until
backtesting shows it's actually costly.

**Trailing**:
- Phase 1: once unrealized profit >= 1x initial risk, move SL to breakeven +
  small buffer.
- Phase 2: beyond that, trail SL behind the previous H1 bar's swing low
  (longs) / high (shorts), recalculated on each new H1 bar.
- No fixed take-profit.

**Entry filters**:
- Spread guard: skip entry if current spread exceeds a per-symbol configured
  maximum. Note this only guards entries — spread widening near session
  opens (well documented for Gold specifically, and common on crypto during
  thin-liquidity hours) is not separately guarded on exits/trailing-stop
  placement; a resting stop can still be touched by a spread spike with no
  real price movement. Accepted as a known limitation for v1 (see Failure
  Modes section).
- News/economic-calendar filtering: explicitly out of scope for v1 (see
  Scope Boundaries).

**Weekend gap risk (XAUUSD)**: Gold CFDs close for the weekend while
BTCUSD/ETHUSD trade continuously. A Gold position held into Friday close can
gap through its resting stop at Sunday/Monday open, filling at whatever
price is available rather than the SL price — the realized loss on that
event can exceed the intended ~1% risk by an unbounded amount. **Decision:
v1 accepts this risk and documents it rather than force-flattening or
tightening stops before weekend close** — treating it as a rare-tail-event
cost of letting the trend-following system hold multi-day trends, consistent
with the "no take-profit, let winners run" philosophy. This must be visible
in backtest results (large single-loss outliers around weekend boundaries
should be expected, not treated as a bug) and re-examined if live/demo
results show it happening more often or more severely than tolerable.

## Risk Management

**Position sizing**
```
risk_amount = AccountEquity() * 1%
stop_distance_price = |EntryPrice - StopLossPrice|
value_per_lot = (SYMBOL_TRADE_TICK_VALUE_PROFIT_or_LOSS / SYMBOL_TRADE_TICK_SIZE) * stop_distance_price
lots = risk_amount / value_per_lot
```
Uses `SYMBOL_TRADE_TICK_VALUE_PROFIT`/`SYMBOL_TRADE_TICK_VALUE_LOSS` (the
bid/ask-side-aware tick values), not the plain `SYMBOL_TRADE_TICK_VALUE`,
which can be stale/approximate on CFD instruments like these three. Where
feasible, cross-check with `OrderCalcProfit()` for the actual computed lot
size before sending the order, since it accounts for the real contract
specification rather than a derived approximation.

Rounded down to the broker's volume step, clamped to
`SYMBOL_VOLUME_MIN`/`MAX`, and checked against free margin via
`OrderCalcMargin()`. If the computed size rounds below the minimum tradeable
volume, the trade is skipped and logged (never forced to a min-lot size that
would risk more than 1%). The *rounded* lot size (not the pre-rounding
theoretical value) is what gets checked against the correlated-group cap
below, since that's the risk actually taken.

**Daily loss circuit breaker (5%)**: equity is recorded at the first tick of
each new trading day, using **broker server time** as the day boundary
(`TimeTradeServer()`), not local/GMT time. If current equity <= that value x
0.95, all *new* entries are blocked for the rest of the day — **sticky once
tripped**: even if equity recovers intraday back above the threshold, new
entries stay blocked until the next day's reset. This is a deliberate choice
(a bounce doesn't undo the signal that something is going wrong that day),
not an accidental side effect.

**Scope: account-wide, not per-symbol.** A loss on any one symbol (most
likely BTC/ETH given their volatility) blocks new entries on *all three*
symbols for the rest of the day, including a perfectly good Gold setup. This
is intentional — the 5% figure is a daily risk budget for the account as a
whole, not per-instrument, and treating it as account-wide is simpler and
more conservative than tracking three independent daily budgets.

Existing open positions continue to be managed (trailing stops keep
running) regardless of breaker state. The daily-start equity value is
persisted to a file (see Persistence) so it survives a VPS/terminal restart
mid-day, and crypto's continuous trading over the weekend means the Sunday
session's daily reset happens normally even though Gold has no ticks that
day.

**Assumption**: this account is used exclusively by this EA — no manual
trades placed alongside it. Both circuit breakers and position sizing use
account-wide `AccountEquity()`, so a manual trade's P/L would silently
contaminate both the 1% sizing calculation and the breaker thresholds. If
this assumption doesn't hold in practice, the breakers need to be
recalculated against EA-attributable equity only, which is a materially
different (and more complex) implementation.

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
and always sizes independently at 1%.

**Tie-break rule (both crypto symbols signal in the same evaluation pass,
only one fits under the cap)**: fixed priority order, **BTCUSD before
ETHUSD**. This is a deliberate, documented choice — not an accident of
symbol-array iteration order — made for simplicity in v1. It does mean
ETHUSD entries will be structurally disadvantaged whenever both signal
simultaneously; if backtesting shows this materially hurts results, a
signal-strength-based tie-break is a reasonable v1.1 revisit.

**Cap basis: risk-at-entry, fixed for the life of the trade.** Once a crypto
position is open, it counts against the 1.5% group budget at its *original*
risk amount, even after trailing has moved its stop to breakeven or beyond.
This is simpler and more conservative than recalculating against current
(post-trail) risk — it means a second crypto entry may stay blocked longer
than strictly necessary once the first trade is de-risked, which is an
accepted trade-off for avoiding real-time recalculation complexity and its
bug surface.

**Expected exposure under normal conditions**: 1% (Gold) + 1.5% (BTC+ETH
group) = 2.5% of equity across at most 3 concurrent positions. This is a
best-case bound under frictionless assumptions — it does not hold during a
weekend gap (see above) or during tail events where Gold and crypto become
correlated despite normally being independent (e.g. broad risk-off
liquidity events, as seen historically in March 2020). Actual worst-case
loss in a single adverse event can exceed 2.5%.

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
reboot, not only an EA/terminal restart. Stored via `FILE_COMMON` scope
(shared common folder, not the per-installation hashed terminal data folder)
specifically so a broker-terminal reinstall or VPS recovery doesn't silently
orphan the file at a stale path.

**Fail-safe on missing/corrupt persistence file**: on `OnInit()`, if the
persistence file cannot be read or fails validation (e.g. corrupt, zeroed,
malformed), and this is not verifiably the very first run (no prior trade
history exists for this EA's magic numbers either), the EA **blocks all new
entries and sends an alert** rather than silently reseeding the equity peak
to current equity. Silently reseeding would erase the 15% max-drawdown
protection at exactly the moment it's most likely needed (a bad stretch that
also happened to coincide with a restart). Only a genuinely-first-ever run
(no file, no history) initializes fresh with no alert.

**Trailing-phase reconstruction on restart**: when rebuilding state for an
existing open position on `OnInit()`, the EA infers which trailing phase it
was in by comparing the position's current SL to its entry price (e.g. for a
long: if current SL >= entry price, treat as already past the Phase 1
breakeven move and resume Phase 2 structure-trailing; otherwise resume
Phase 1 logic). This is an inference, not a persisted fact — acceptable
because the inference is unambiguous given the two-phase design, but it
should be unit-tested explicitly since it's the one part of "stateless
restart" that isn't a direct file/position lookup.

**Alerting**: both channels enabled —
- MT5 built-in push notifications (to MetaTrader mobile app).
- Telegram bot notifications (bot token supplied via EA input parameter,
  never hardcoded; requires `WebRequest` allow-listing for the Telegram API
  domain in terminal options — a manual one-time setup step).

Alerts fire on: circuit breaker trips (daily loss / max drawdown), order
execution errors, and EA disabled events.

**Heartbeat / watchdog alert**: in addition to event-driven alerts above, the
EA sends a periodic "still alive" heartbeat notification (e.g. once daily)
via `OnTimer()`. Rationale: an EA that crashes, gets removed from the chart,
or has AutoTrading silently toggled off produces *no* alert under a
purely event-driven design — there's no "disabled" event if it just stops
running. A missing heartbeat is the signal that something is wrong even when
no explicit failure event fired.

**Notification safety in the Strategy Tester**: `WebRequest` does not
execute inside the Strategy Tester at all, and calls are synchronous/
blocking. `Notifier.mqh` gates all Telegram calls behind
`MQLInfoInteger(MQL_TESTER)`/`MQL_OPTIMIZATION` checks (no-op during
backtests/optimization), and treats notification failures as best-effort —
a failed or slow notification call must never delay or block trade-management
logic (e.g. trailing-stop updates) for other symbols in the same tick pass.

## Testing & Validation Plan (for the upcoming backtesting phase)

Not implemented in v1 build, but the bar this system is being built toward:

- MT5 Strategy Tester with real tick data, target 2-3 years per symbol where
  broker history allows (crypto CFD history will likely be shorter — this
  limitation will be surfaced explicitly, not glossed over).
- Walk-forward validation: in-sample parameter optimization windows,
  out-of-sample unmodified test windows. **Correction from initial draft**:
  MT5's built-in Strategy Tester optimization "Forward" setting only
  provides a single fixed-ratio in-sample/out-of-sample split, not a
  flexible rolling multi-window walk-forward engine. Genuine rolling
  walk-forward (fixed window + step size, re-anchored repeatedly) requires
  manually re-running optimizations over shifted date ranges, or external
  tooling — this will be scoped concretely when the backtesting phase
  starts, not assumed to be a built-in checkbox. A strategy that only
  performs well in-sample is overfit and will be called out as such
  regardless of which method produces that finding.
- Metrics tracked beyond net profit: max drawdown, Sharpe/Sortino, win rate
  vs average R-multiple, longest losing streak, result stability across
  differing sub-periods (trending vs choppy years), and **trailing give-back**
  — MAE/MFE (maximum adverse/favorable excursion) and "% of peak open profit
  given back before exit," which directly measures whether the Phase 2
  structure-trail (previous H1 bar's swing low/high) is too loose.
- Realistic spread/commission/swap modeling using the actual broker's
  typical figures for these three symbols, not optimistic Strategy Tester
  defaults.

## Failure Modes & Operational Assumptions

Centralizing the accepted risks and assumptions scattered through the
sections above, per independent design review:

- **Weekend gap risk (XAUUSD)** is accepted, not mitigated — a held Gold
  position can lose more than its intended ~1% risk on a Sunday/Monday gap.
- **Correlated-cap bound (2.5% expected exposure) is a best-case figure**,
  not a hard worst-case guarantee — it assumes no gap-through-stop and no
  tail-correlation between Gold and crypto, both of which can fail during
  genuine market stress.
- **This account is assumed EA-exclusive** — no manual trades placed
  alongside the EA. If violated, both circuit breakers and position sizing
  (which use account-wide equity) become contaminated by manual P/L.
- **Broker disconnect / VPS crash while a position is open**: the
  server-side stop loss (always attached to the order, never mental-only)
  is the actual safety net here. Trailing-stop updates freeze at their last
  level while the EA/terminal is down — the position is protected at
  whatever level the SL was last set to, not actively managed, until the EA
  resumes.
- **A dead EA (crashed, removed from chart, AutoTrading disabled) produces
  no explicit failure event** — this is why the heartbeat alert (above)
  exists as the detection mechanism, rather than relying solely on
  event-driven alerts.
- **Spread widening at session opens can trigger a resting stop without real
  price movement** — only entries are spread-guarded in v1; exit/trailing
  placement near session opens is not separately protected.
- These are v1 trade-offs, not oversights — each was evaluated and
  deliberately not engineered around, to keep the initial build scoped and
  testable. Revisit any of them if backtesting or demo trading shows the
  actual cost is higher than assumed here.

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
