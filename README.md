# Autobot_v1

A native MQL5 Expert Advisor for MetaTrader 5 that trades **XAUUSD, BTCUSD, and ETHUSD** from a single chart using a multi-timeframe trend-following breakout strategy: H4 EMA(200) bias + H1 Donchian(20) breakout entries, ATR-based stops, breakeven → structure trailing, and mechanical circuit breakers.

**This is v1** — deliberately scoped down and meant to be backtested/demo-forward-tested before any live use. It **refuses to trade on a non-demo account by default** (`InpAllowLiveAccount=false`); see [docs/guides/01-running-the-ea.md](docs/guides/01-running-the-ea.md#demo-only-guard).

Full strategy rationale, edge cases, and accepted limitations (chop/whipsaw expectations, weekend gap risk, spread-spike exits) live in [docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md](docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md). This README is the entry point; the [docs/guides/](docs/guides/README.md) folder has full step-by-step depth for each topic below.

## Repo layout

```
MQL5/
├── Experts/Autobot_v1/
│   ├── Autobot_v1.mq5        # Main EA: OnInit, OnTimer (main loop), OnTick, OnTradeTransaction
│   └── Include/
│       ├── Config.mqh        # All tunable inputs + per-symbol config table
│       ├── SymbolState.mqh   # Per-symbol runtime state struct
│       ├── MarketData.mqh    # Indicator handles, H4 bias / Donchian / ATR computation
│       ├── TrendFilter.mqh   # H4 EMA200 bias decision (deadband logic)
│       ├── EntrySignal.mqh   # Donchian(20) breakout detection
│       ├── RiskManager.mqh   # Position sizing, circuit breakers, correlated-exposure cap
│       ├── TradeExecution.mqh# CTrade wrapper: send/retry, stop clamping, position lookup
│       ├── TrailingStop.mqh  # Breakeven + structure-based trailing math
│       ├── Persistence.mqh   # File-based equity/breaker state (survives restarts)
│       ├── Notifier.mqh      # MT5 push + Telegram alerts
│       └── Logger.mqh        # Structured CSV trade/event logging
└── Scripts/Autobot_v1_Tests/ # One .mq5 test script per module + shared assert helpers
docs/
├── guides/                   # Setup, Telegram, VPS deployment, MQL5 Market publishing/subscribing
└── superpowers/
    ├── specs/                # Design spec (the "why")
    └── plans/                # Original implementation plan (the "how it was built")
```

## Quick start

1. Install: copy `MQL5/Experts/Autobot_v1/` (including `Include/`) into your terminal's `MQL5/Experts/` data folder.
2. Compile `Autobot_v1.mq5` in MetaEditor (F7), confirm zero errors.
3. Enable **Algo Trading** in MT5, attach the EA to a chart for each symbol you want traded (one instance per symbol — the EA loops over all three symbols internally regardless of which chart it's on).
4. Use a **demo account**, or explicitly set `InpAllowLiveAccount=true` if you've decided to override the guard.

Full walkthrough, the complete input reference table, where state files live, and manual-trading/netting-account caveats: **[docs/guides/01-running-the-ea.md](docs/guides/01-running-the-ea.md)**.

## How the EA works

Everything runs off a **5-second timer** (`OnTimer`, set via `EventSetTimer`), not `OnTick` — `OnTick` only fires for the chart's own symbol, which can't drive multi-symbol logic. `OnTick` is left intentionally empty.

Per `OnTimer` pass, for each configured symbol (`Config.mqh` → `GetSymbolConfigs`):

1. **Manage any open position** (`ManageOpenPosition`) — breakeven move once unrealized profit ≥ 1× initial risk, then structure trailing behind the prior H1 bar's swing high/low.
2. **Skip new-entry evaluation** if the symbol is disabled, entries are globally blocked (breaker tripped / persistence failsafe), a position/order already exists, or this H1 bar was already evaluated.
3. **Signal check**: H4 bias (`ComputeH4Bias` + `DetermineBias`, EMA200 with an ATR-based deadband) must agree with an H1 Donchian(20) breakout (`ComputeDonchian` + `DetectBreakout`).
4. **Risk gates**: spread guard, correlated BTC+ETH exposure cap (`CanOpenCryptoPosition`), position sizing off `InpRiskPercent` and the clamped ATR stop distance (`CalculateLotSize`), margin check.
5. **Execute** (`ExecuteMarketOrder`) with retries, log the event (`Logger.mqh`), queue an alert.

Account-wide circuit breakers (daily loss %, max drawdown % from equity peak) are evaluated once per pass, before the symbol loop, and block *all* new entries when tripped — existing positions are still trailed. `OnInit` rebuilds all state (equity baselines, breaker flags, per-symbol trail phase) from the persisted state file plus live positions/history, so a terminal/VPS restart never loses risk state. `OnTradeTransaction` fires on every closing deal to log the exit and alert.

Alerts raised mid-pass are queued (`QueueAlert`) and flushed once at the end of the pass, so a slow/failed Telegram `WebRequest` never delays trade management for other symbols.

## Making changes

- **Inputs**: add/change tunables in `Config.mqh` only (grouped by `input group`); `GetSymbolConfigs` is the single place per-symbol values (magic offset, spread cap, slippage) are derived.
- **Strategy logic**: bias lives in `TrendFilter.mqh`, breakout detection in `EntrySignal.mqh`, indicator plumbing in `MarketData.mqh` — keep these pure/testable (inputs in, decision out) rather than touching global state directly, matching the existing style.
- **Risk/sizing/breakers**: `RiskManager.mqh`. Trailing math: `TrailingStop.mqh`. Both are pure functions called from `Autobot_v1.mq5`'s `ManageOpenPosition`/`ProcessSymbol` — extend the module, then wire the call site.
- **Compile after every change**: open `Autobot_v1.mq5` in MetaEditor, F7, confirm zero errors/warnings before testing.
- **No `#pragma once` in MQL5** — every new `.mqh` needs its own `#ifndef`/`#define` include guard (see the top of any existing `Include/*.mqh` for the pattern), since headers get included both directly and transitively.

## Testing changes

There's no MT5 unit-test framework, so `MQL5/Scripts/Autobot_v1_Tests/` uses plain `.mq5` scripts: one per module (`Test_TrendFilter.mq5`, `Test_EntrySignal.mq5`, `Test_RiskManager_Sizing.mq5`, `Test_RiskManager_Breakers.mq5`, `Test_RiskManager_ExposureCap.mq5`, `Test_TradeExecution.mq5`, `Test_TradeExecution_Stops.mq5`, `Test_TrailingStop.mq5`, `Test_SymbolState.mq5`, `Test_Persistence.mq5`, `Test_Logger.mq5`, `Test_Notifier.mq5`), plus `SmokeTest_Compile.mq5` which just confirms every module still links together.

To run them:

1. Copy `MQL5/Scripts/Autobot_v1_Tests/` into your terminal's `MQL5/Scripts/` folder.
2. Compile each `Test_*.mq5` in MetaEditor (F7).
3. Drag the compiled script onto any chart from the Navigator (scripts run once via `OnStart` and detach).
4. Read the **Experts log** tab — each assertion prints `PASS: <name>` or `FAIL: <name> <expected/actual>`, with a `=== <suite>: N passed, N failed ===` summary line.

When you change a module's logic, update or add cases in its matching `Test_*.mq5` first, then re-run it. `Test_Persistence.mq5` writes to `Autobot_v1_state.TEST.bin` (via `testMode=true`), never the production per-account state file — safe to run anytime without touching real state.

## Backtesting

The EA's main loop is timer-driven, which the MT5 Strategy Tester supports natively (timers fire on the tester's simulated clock) — no special setup beyond a normal multi-symbol-aware backtest:

1. **Strategy Tester** → select `Autobot_v1`, any one of XAUUSD/BTCUSD/ETHUSD as the tested symbol (the EA manages all three internally regardless of which one the chart/tester is on — make sure your broker/tester environment actually carries all three, or the others get disabled for that session per the `OnInit` symbol-availability check).
2. **Modeling mode**: "Every tick based on real ticks" or "Every tick" for realistic fills; "1-minute OHLC" or "Open prices only" is fine for a fast first pass since entries only evaluate on H1 bar close anyway.
3. **Timeframe**: doesn't affect the logic (H4/H1 are pulled explicitly via indicator handles), but H1 is the natural chart to watch visually.
4. The demo-only guard is automatically bypassed under `MQL_TESTER`/`MQL_OPTIMIZATION` — no need to set `InpAllowLiveAccount` for backtests.
5. **State isolation**: `Persistence.mqh` skips all file I/O entirely inside the tester/optimizer — every single backtest pass starts as a genuine first run seeded from that pass's actual starting deposit. Nothing is read from or written to the live per-account state file, and nothing carries over between passes.
6. Use a multi-year range covering at least one full trend + range cycle per symbol; expect a ~35–45% win rate by design (trend-following with no take-profit) — see the spec's "Expected behavior" note before mistaking that for a broken signal.
7. For optimization, prefer Open Prices for a wide scan, then validate promising parameter sets with Every Tick. General MQL5 backtesting/optimization mechanics (walk-forward, `OnTester()`, avoiding overfitting): `.agents/skills/mql-developer/references/backtesting.md`.

## Deeper guides

| Guide | Covers |
|---|---|
| [01-running-the-ea.md](docs/guides/01-running-the-ea.md) | Install, compile, attach, full input reference, demo-only guard, manual-trading/netting-account interaction |
| [02-telegram-alerts.md](docs/guides/02-telegram-alerts.md) | Bot setup, chat ID, WebRequest allow-listing |
| [03-vps-deployment.md](docs/guides/03-vps-deployment.md) | MetaQuotes VPS vs third-party Windows VPS, 24/5 unattended running |
| [04-publishing-to-mql5-market.md](docs/guides/04-publishing-to-mql5-market.md) | Seller side: submission, source protection |
| [05-subscribing-and-running.md](docs/guides/05-subscribing-and-running.md) | Buyer side: purchasing, activation, running a Market copy |
