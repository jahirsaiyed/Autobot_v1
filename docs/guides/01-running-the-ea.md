# Running Autobot_v1

Autobot_v1 is a multi-symbol H4-bias / H1-Donchian-breakout trend-following EA for XAUUSD, BTCUSD, and ETHUSD. See `docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md` for the full design spec.

## Prerequisites

- MetaTrader 5 desktop terminal
- A **demo account** — the EA refuses to trade on a live account by default (see [Demo-only guard](#demo-only-guard) below)
- Broker/symbols available: XAUUSD, BTCUSD, ETHUSD (or your broker's equivalent symbol names)

## 1. Install the files

Copy the EA folder into your terminal's data folder, preserving the `Include/` subfolder:

```
<Terminal Data Folder>/MQL5/Experts/Autobot_v1/Autobot_v1.mq5
<Terminal Data Folder>/MQL5/Experts/Autobot_v1/Include/*.mqh
```

Find your terminal's data folder from MT5: **File > Open Data Folder**.

## 2. Compile

1. Open `Autobot_v1.mq5` in MetaEditor (F4 from MT5, or double-click the file).
2. Press **Compile** (F7). Confirm zero errors.
3. Optional sanity check: the repo includes standalone test scripts under `MQL5/Scripts/Autobot_v1_Tests/`. Copy that folder into `MQL5/Scripts/` too, compile `SmokeTest_Compile.mq5`, and run it from the Navigator to confirm all modules link correctly before attaching the live EA.

## 3. Enable algo trading

In the MT5 toolbar, make sure **Algo Trading** is toggled on (green). The EA will not place orders otherwise.

## 4. Attach to charts

Attach **one instance per symbol** you want traded — open a chart for XAUUSD, BTCUSD, and/or ETHUSD and drag `Autobot_v1` onto each from the Navigator. The EA is single-symbol-per-chart; multi-symbol handling inside one instance is not how it's wired.

In the EA's **Common** tab, confirm **Allow WebRequest for listed URL** is available if you plan to use Telegram alerts (configured in the **Dependencies** tab — see [02-telegram-alerts.md](02-telegram-alerts.md)).

## Demo-only guard

By design, `OnInit()` refuses to run on a non-demo account:

> "Autobot_v1: refusing to run on a non-demo account (v1 is demo-only per design spec). Set InpAllowLiveAccount=true to override."

This was added and verified deliberately during development (see `.superpowers/sdd/progress.md`), not an oversight. `InpAllowLiveAccount` is a real input you *can* set to `true` to override it — but do that only as your own informed decision after you've validated the strategy yourself; this guide does not recommend flipping it.

## Input reference

Inputs are grouped in `MQL5/Experts/Autobot_v1/Include/Config.mqh`. Values shown are the shipped defaults.

### Risk Management

| Input | Default | Meaning |
|---|---|---|
| `InpRiskPercent` | 1.0 | Risk per trade, % of equity |
| `InpDailyLossPercent` | 5.0 | Daily loss circuit breaker, % |
| `InpMaxDrawdownPercent` | 15.0 | Max drawdown circuit breaker, % |
| `InpCorrelatedCapPercent` | 1.5 | Combined BTC+ETH open-risk cap, % |
| `InpClearMaxDrawdownBreaker` | false | Explicit human re-enable after a max-drawdown trip |

### Trading Logic

| Input | Default | Meaning |
|---|---|---|
| `InpEMAPeriod` | 200 | H4 EMA period for trend bias |
| `InpDeadbandATRMultiplier` | 0.1 | Bias deadband, × H4 ATR |
| `InpDonchianPeriod` | 20 | H1 Donchian channel period |
| `InpATRPeriod` | 14 | ATR period (used on both H1 and H4) |
| `InpATRStopMultiplier` | 2.0 | Initial stop = entry ± N × ATR(H1) |
| `InpBreakevenBufferPoints` | 20 | Buffer added to breakeven SL, in points |

### Execution

| Input | Default | Meaning |
|---|---|---|
| `InpMagicBase` | 100000 | Base magic number (per-symbol offset added) |
| `InpMaxRetries` | 3 | Max order-send retries on transient errors |
| `InpSlippagePointsGold` | 50 | Max deviation, XAUUSD |
| `InpSlippagePointsCrypto` | 200 | Max deviation, BTCUSD/ETHUSD |
| `InpMaxSpreadPointsGold` | 50 | Spread guard, XAUUSD |
| `InpMaxSpreadPointsBTC` | 3500 | Spread guard, BTCUSD |
| `InpMaxSpreadPointsETH` | 300 | Spread guard, ETHUSD |
| `InpAllowLiveAccount` | false | Explicitly permit non-demo trading (see [Demo-only guard](#demo-only-guard)) |

### Alerting

| Input | Default | Meaning |
|---|---|---|
| `InpEnableTelegram` | false | Enable Telegram alerts |
| `InpTelegramBotToken` | "" | Telegram bot token (set per-deployment, never commit to source) |
| `InpTelegramChatID` | "" | Telegram chat ID |
| `InpHeartbeatHours` | 24 | Heartbeat notification interval, hours |

Full setup for this section: [02-telegram-alerts.md](02-telegram-alerts.md).

### Symbol Selection

| Input | Default | Meaning |
|---|---|---|
| `InpTradeXAUUSD` | true | Allow new entries on XAUUSD |
| `InpTradeBTCUSD` | true | Allow new entries on BTCUSD |
| `InpTradeETHUSD` | true | Allow new entries on ETHUSD |

## Where the EA writes its state

Both files live in the terminal's shared **Common** files folder (`FILE_COMMON`), not the per-terminal data folder — relevant if you ever run more than one terminal instance on the same machine (see [03-vps-deployment.md](03-vps-deployment.md)):

- `Autobot_v1_state.bin` — persisted equity baselines, circuit-breaker state, trail phase (survives terminal/VPS restarts)
- `Autobot_v1_log.csv` — trade/event log

Strategy Tester runs use separate `.TEST.*` filenames so backtests never read or corrupt live state.

## Running alongside manual trading

The EA identifies its own positions strictly by **symbol + magic number** (`InpMagicBase` plus a per-symbol offset). It never queries, modifies, or closes a position or pending order that doesn't match both — so on an account where you also manage trades by hand, the EA will not touch anything it didn't open itself, with one important caveat below.

### Netting vs. Hedging accounts

Check your account's margin mode before mixing manual and EA trades on **the same symbols the EA trades** (XAUUSD, BTCUSD, ETHUSD):

- **Hedging accounts** (most offshore/retail MT5 brokers): manual and EA positions on the same symbol stay as separate tickets. Magic-number isolation works as described above.
- **Netting accounts** (common at EU/regulated brokers): MT5 allows only one position per symbol. A manual trade on XAUUSD/BTCUSD/ETHUSD while the EA holds one **merges into a single blended position** — the EA will then trail/manage volume that includes your manual trade, and your manual actions (partial close, opposite-direction trade) alter the position the EA thinks it fully owns.
- **If you're on a Netting account, avoid manually trading XAUUSD/BTCUSD/ETHUSD while the EA is running those symbols.** Any other symbol is unaffected.

### Shared account resources

Even on a Hedging account with no symbol overlap, the EA's risk logic is account-wide, not EA-scoped:

| Situation | What happens |
|---|---|
| Manual trades have floating profit/loss | `InpRiskPercent` sizing uses whole-account equity (`ACCOUNT_EQUITY`), so EA lot sizes shrink or grow with your manual P&L |
| Manual trades lose money | Can trip `InpDailyLossPercent` / `InpMaxDrawdownPercent` and halt new EA entries, even though the loss wasn't the EA's |
| Manual trades are profitable | Can mask a real EA-driven drawdown and delay a breaker trip that should have happened |
| Manual trades use margin | Reduces `ACCOUNT_MARGIN_FREE`; the EA silently skips entries with `"insufficient-margin"` rather than over-leveraging — safe, but fewer EA fills |
| You hold BTC or ETH manually | Not counted toward `InpCorrelatedCapPercent` — real combined crypto exposure can run hotter than the EA's 1.5% default cap suggests |
| You edit the SL/TP on an EA position (Hedging accounts only) | The EA never loosens a stop you've tightened, never removes a TP you add, and cleanly stops managing a position once you close it |
| You deposit or withdraw funds | Indistinguishable from trading P&L to the breaker logic — a withdrawal can look like a loss, a deposit can reset the drawdown high-water mark upward |

**Recommendation:** if you want the EA's performance numbers to be clean and independently attributable, either confirm your account is Hedging-mode and avoid manual trades on XAUUSD/BTCUSD/ETHUSD, or run the EA on a separate account/sub-account with its own dedicated capital.

## Next steps

- [02-telegram-alerts.md](02-telegram-alerts.md) — get notified of trades and heartbeats
- [03-vps-deployment.md](03-vps-deployment.md) — keep the EA running 24/5 without your own PC
