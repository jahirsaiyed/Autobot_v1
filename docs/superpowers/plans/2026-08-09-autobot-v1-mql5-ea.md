# Autobot v1 MQL5 EA Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the native MQL5 Expert Advisor described in `docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md` — a single EA trading XAUUSD/BTCUSD/ETHUSD with an H4-bias/H1-Donchian-breakout trend-following strategy, ATR-based risk management, two circuit breakers, and a correlated-exposure cap.

**Architecture:** Trading/risk *decision* logic is written as pure functions (no MT5 API calls inside them) so it can be unit-tested with hardcoded inputs via hand-written test scripts. Thin "glue" functions handle all live MT5 API access (indicator handles, `CopyBuffer`, `PositionGetX`, order execution) and are verified by compiling cleanly plus a final Strategy Tester run, not isolated unit tests. The EA's main loop runs on `OnTimer()`, not `OnTick()` (see spec correction — `OnTick()` only fires for the chart's own symbol).

**Tech Stack:** MQL5 (MetaTrader 5), `CTrade` standard library, native file I/O (no external dependencies).

## Global Constraints

- Canonical source lives at `D:\TradeBots\Autobot_v1\MQL5\...` (this project's git repo). It is made visible to the live MT5 terminal via NTFS junctions (Task 1) — do not create or edit files directly inside the terminal's AppData folder; always edit the project-repo copy.
- Active MT5 terminal data folder (confirmed via today's log file and `origin.txt`): `C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\`. Corresponding MetaEditor CLI binary: `C:\Program Files\MetaTrader 5\MetaEditor64.exe`. This machine has other MT5/MT4 installs (e.g. "FBS MetaTrader 5") — do not use their MetaEditor binaries.
- **No automated MQL5 test runner exists in this environment.** Every task's verification has two tiers, both required before the task is done:
  1. **Automated compile-check**: run MetaEditor CLI (`/compile`) via Bash/PowerShell. Must report 0 errors. This is fully automatable and must be run by whoever executes this task.
  2. **Logic verification**: a hand-written test script (using the shared `TestUtils.mqh` assertion helpers from Task 1) run manually inside the already-open, already-logged-in MT5 terminal (Navigator > Scripts > right-click > Execute, or drag onto any chart). The Experts-tab log output must show `ALL TESTS PASSED` with zero `FAIL` lines. Since no GUI automation tool is available in this environment, running the script and confirming its output is a manual step — the plan is written so this is the *only* manual part of otherwise-automatable tasks.
- **Financial safety guard**: Task 13's test script places a real (demo-account) pending order to validate duplicate-order detection. That script MUST check `AccountInfoInteger(ACCOUNT_TRADE_MODE) == ACCOUNT_TRADE_MODE_DEMO` first and abort immediately with a clear failure message if the connected account is not a demo account. Never skip this guard.
- Money/percentage constants must match the approved spec exactly: 1% risk/trade, 5% daily loss breaker, 15% max drawdown breaker, 1.5% BTC+ETH correlated cap, BTCUSD-before-ETHUSD tie-break (enforced by array order, index 1 before index 2), H4 EMA(200) bias with 0.1×ATR(H4) deadband, H1 Donchian(20) entry, ATR(14, H1) × 2.0 initial stop, breakeven-then-structure trailing, no fixed take-profit.
- Never hardcode the Telegram bot token or chat ID — always EA `input` parameters.
- **Every `.mqh` file must have a manual include guard** (`#ifndef AUTOBOT_V1_<NAME>_MQH` / `#define` / `#endif`, following `Config.mqh`'s pattern from Task 2). MQL5 has no `#pragma once` and no automatic double-include protection — modules in this plan are included both directly by `Autobot_v1.mq5` and transitively through other modules (e.g. `SymbolState.mqh` is included by `TrendFilter.mqh`, `EntrySignal.mqh`, and `TrailingStop.mqh`, all of which `Autobot_v1.mq5` also includes directly), so an unguarded header causes "already defined" compile errors once enough modules stack up in one compilation unit. This was discovered and retrofitted onto `Config.mqh` after Task 2; apply it from the start in every task from here on.
- No silent failures: every skipped trade, failed order, or circuit-breaker trip is logged via `Logger.mqh` and/or alerted via `Notifier.mqh`.
- Keep files focused per the design's module list — do not merge unrelated responsibilities into one file.

---

## File Structure

```
D:\TradeBots\Autobot_v1\
├── MQL5\
│   ├── Experts\Autobot_v1\
│   │   ├── Autobot_v1.mq5              (Task 15)
│   │   └── Include\
│   │       ├── Config.mqh              (Task 2)
│   │       ├── SymbolState.mqh         (Task 3)
│   │       ├── TrendFilter.mqh         (Task 4)
│   │       ├── EntrySignal.mqh         (Task 5)
│   │       ├── RiskManager.mqh         (Tasks 6-8)
│   │       ├── TrailingStop.mqh        (Task 9)
│   │       ├── Persistence.mqh         (Task 10)
│   │       ├── Logger.mqh              (Task 11)
│   │       ├── Notifier.mqh            (Task 12)
│   │       ├── TradeExecution.mqh      (Task 13)
│   │       └── MarketData.mqh          (Task 14)
│   └── Scripts\Autobot_v1_Tests\
│       ├── TestUtils.mqh               (Task 1)
│       ├── Test_Config.mq5             (Task 2)
│       ├── Test_SymbolState.mq5        (Task 3)
│       ├── Test_TrendFilter.mq5        (Task 4)
│       ├── Test_EntrySignal.mq5        (Task 5)
│       ├── Test_RiskManager_Sizing.mq5       (Task 6)
│       ├── Test_RiskManager_Breakers.mq5     (Task 7)
│       ├── Test_RiskManager_ExposureCap.mq5  (Task 8)
│       ├── Test_TrailingStop.mq5       (Task 9)
│       ├── Test_Persistence.mq5        (Task 10)
│       ├── Test_Logger.mq5             (Task 11)
│       ├── Test_Notifier.mq5           (Task 12)
│       ├── Test_TradeExecution.mq5     (Task 13)
│       ├── Test_TradeExecution_Stops.mq5    (Task 17 / Fix 4)
│       └── SmokeTest_Compile.mq5       (Task 1)
```

Two NTFS junctions (created in Task 1, not symlinks — junctions need no admin rights) make these two folders also appear at:
- `...\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Autobot_v1`
- `...\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\Autobot_v1_Tests`

---

### Task 1: Project Scaffolding, Junctions, and Shared Test Utilities

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\.gitkeep` (placeholder, removed once Task 2 adds real files — actually skip this, see step 1)
- Create: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\TestUtils.mqh`
- Create: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\SmokeTest_Compile.mq5`

**Interfaces:**
- Produces: `T_ResetCounters()`, `T_AssertTrue(string,bool,string="")`, `T_AssertEqualsDouble(string,double,double,double=0.00001)`, `T_AssertEqualsInt(string,int,int)`, `T_AssertEqualsString(string,string,string)`, `T_PrintSummary(string)` — used by every subsequent test script.

- [ ] **Step 1: Create the project folder structure**

```bash
mkdir -p "D:/TradeBots/Autobot_v1/MQL5/Experts/Autobot_v1/Include"
mkdir -p "D:/TradeBots/Autobot_v1/MQL5/Scripts/Autobot_v1_Tests"
```

- [ ] **Step 2: Create the NTFS junctions into the live MT5 terminal**

Run in PowerShell (junctions don't require admin rights):

```powershell
$termData = "C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075"
New-Item -ItemType Junction -Path "$termData\MQL5\Experts\Autobot_v1" -Target "D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1"
New-Item -ItemType Junction -Path "$termData\MQL5\Scripts\Autobot_v1_Tests" -Target "D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests"
Get-Item "$termData\MQL5\Experts\Autobot_v1" | Select-Object LinkType,Target
Get-Item "$termData\MQL5\Scripts\Autobot_v1_Tests" | Select-Object LinkType,Target
```

Expected: both `Get-Item` calls print `LinkType: Junction` and a `Target` pointing back to `D:\TradeBots\Autobot_v1\MQL5\...`.

- [ ] **Step 3: Write the shared test assertion helper**

`D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\TestUtils.mqh`:

```mql
//+------------------------------------------------------------------+
//| TestUtils.mqh - shared assertion helpers for Autobot_v1 test     |
//| scripts. No MT5 unit-test framework exists; these helpers print  |
//| PASS/FAIL lines to the Experts log for manual verification.      |
//+------------------------------------------------------------------+
#property strict

int g_testPassCount = 0;
int g_testFailCount = 0;

void T_ResetCounters()
  {
   g_testPassCount = 0;
   g_testFailCount = 0;
  }

void T_AssertTrue(string testName, bool condition, string detail = "")
  {
   if(condition)
     {
      g_testPassCount++;
      PrintFormat("PASS: %s", testName);
     }
   else
     {
      g_testFailCount++;
      PrintFormat("FAIL: %s %s", testName, detail);
     }
  }

void T_AssertEqualsDouble(string testName, double actual, double expected, double tolerance = 0.00001)
  {
   bool ok = MathAbs(actual - expected) <= tolerance;
   T_AssertTrue(testName, ok, StringFormat("expected=%.5f actual=%.5f", expected, actual));
  }

void T_AssertEqualsInt(string testName, int actual, int expected)
  {
   T_AssertTrue(testName, actual == expected, StringFormat("expected=%d actual=%d", expected, actual));
  }

void T_AssertEqualsString(string testName, string actual, string expected)
  {
   T_AssertTrue(testName, actual == expected, StringFormat("expected=%s actual=%s", expected, actual));
  }

void T_PrintSummary(string suiteName)
  {
   PrintFormat("=== %s: %d passed, %d failed ===", suiteName, g_testPassCount, g_testFailCount);
   if(g_testFailCount == 0)
      PrintFormat("ALL TESTS PASSED: %s", suiteName);
   else
      PrintFormat("TESTS FAILED: %s", suiteName);
  }
```

- [ ] **Step 4: Write a trivial smoke-test script to prove the junction + compile pipeline works**

`D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\SmokeTest_Compile.mq5`:

```mql
#property strict
#include "TestUtils.mqh"

void OnStart()
  {
   T_ResetCounters();
   T_AssertTrue("smoke test runs", true);
   T_PrintSummary("SmokeTest_Compile");
  }
```

- [ ] **Step 5: Compile-check via MetaEditor CLI**

```bash
"/c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\Autobot_v1_Tests\SmokeTest_Compile.mq5" /log:"D:\TradeBots\Autobot_v1\compile.log"
cat "D:/TradeBots/Autobot_v1/compile.log"
```

Expected: log shows `0 errors, 0 warnings` (or only informational lines) and `SmokeTest_Compile.ex5` appears next to the `.mq5` file (check via `ls`).

- [ ] **Step 6: Manual run to confirm the terminal sees it**

Ask the user to open the already-running MT5 terminal, find `Autobot_v1_Tests\SmokeTest_Compile` under Navigator > Scripts, double-click to run it on any chart, and paste back the Experts-tab log output.

Expected output contains:
```
PASS: smoke test runs
=== SmokeTest_Compile: 1 passed, 0 failed ===
ALL TESTS PASSED: SmokeTest_Compile
```

- [ ] **Step 7: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Scripts/Autobot_v1_Tests/TestUtils.mqh MQL5/Scripts/Autobot_v1_Tests/SmokeTest_Compile.mq5
git commit -m "feat: scaffold MQL5 project structure, terminal junctions, and shared test utilities"
```

(Note: the junctions themselves are OS-level filesystem objects, not files to commit — only the real files under `D:\TradeBots\Autobot_v1\MQL5\...` are tracked by git.)

---

### Task 2: Config.mqh — Symbol Configuration and Tunable Inputs

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\Config.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_Config.mq5`

**Interfaces:**
- Produces: `struct SymbolConfig { string symbol; ulong magicNumber; bool isCorrelatedGroup; double maxSpreadPoints; int slippagePoints; }`, `void GetSymbolConfigs(SymbolConfig &configs[])`, and all `Inp*` input parameters listed below.

- [ ] **Step 1: Write Config.mqh**

```mql
//+------------------------------------------------------------------+
//| Config.mqh - Autobot_v1 tunable inputs and symbol configuration  |
//+------------------------------------------------------------------+
#property strict

input group "Risk Management"
input double InpRiskPercent            = 1.0;   // Risk per trade (% of equity)
input double InpDailyLossPercent       = 5.0;   // Daily loss circuit breaker (%)
input double InpMaxDrawdownPercent     = 15.0;  // Max drawdown circuit breaker (%)
input double InpCorrelatedCapPercent   = 1.5;   // BTC+ETH combined risk cap (%)
input bool   InpClearMaxDrawdownBreaker = false; // Explicit human re-enable after a max-drawdown trip
// [Task 17 / Fix 2] InpClearMaxDrawdownBreaker is the ONLY sanctioned way to
// clear a max-drawdown trip across a restart - a restart alone must never
// clear it (see Task 15's OnInit restore logic below).

input group "Trading Logic"
input int    InpEMAPeriod              = 200;   // H4 EMA period for trend bias
input double InpDeadbandATRMultiplier  = 0.1;   // Bias deadband, x H4 ATR
input int    InpDonchianPeriod         = 20;    // H1 Donchian channel period
input int    InpATRPeriod              = 14;    // ATR period (used on both H1 and H4)
input double InpATRStopMultiplier      = 2.0;   // Initial stop = entry +/- N x ATR(H1)
input double InpBreakevenBufferPoints  = 20;    // Buffer added to breakeven SL, in points

input group "Execution"
input int    InpMagicBase              = 100000; // Base magic number (symbol offset added)
input int    InpMaxRetries             = 3;      // Max order-send retries on transient errors
input int    InpSlippagePointsGold     = 50;     // Max deviation, XAUUSD
input int    InpSlippagePointsCrypto   = 200;    // Max deviation, BTCUSD/ETHUSD
input double InpMaxSpreadPointsGold    = 50;     // Spread guard, XAUUSD
input double InpMaxSpreadPointsCrypto  = 300;    // Spread guard, BTCUSD/ETHUSD
input bool   InpAllowLiveAccount       = false;  // Explicitly permit non-demo trading (v1 is demo-only by design)
// [Task 17 / Fix 10] Checked first thing in OnInit() - the EA refuses to
// run on a non-demo account unless this is explicitly set true. The
// Strategy Tester and optimization passes are exempted (not real accounts).

input group "Alerting"
input bool   InpEnableTelegram         = false;  // Enable Telegram alerts
input string InpTelegramBotToken       = "";     // Telegram bot token (never hardcode)
input string InpTelegramChatID         = "";     // Telegram chat ID
input int    InpHeartbeatHours         = 24;     // Heartbeat notification interval, hours

// Symbol configuration: one entry per traded symbol. Array order matters -
// BTCUSD (index 1) is always evaluated before ETHUSD (index 2) in the main
// loop, which is how the spec's fixed BTC-before-ETH tie-break is enforced.
struct SymbolConfig
  {
   string            symbol;
   ulong             magicNumber;
   bool              isCorrelatedGroup; // true for BTCUSD/ETHUSD
   double            maxSpreadPoints;
   int               slippagePoints;
  };

#define AUTOBOT_SYMBOL_COUNT 3

void GetSymbolConfigs(SymbolConfig &configs[])
  {
   ArrayResize(configs, AUTOBOT_SYMBOL_COUNT);

   configs[0].symbol            = "XAUUSD";
   configs[0].magicNumber       = (ulong)InpMagicBase + 1;
   configs[0].isCorrelatedGroup = false;
   configs[0].maxSpreadPoints   = InpMaxSpreadPointsGold;
   configs[0].slippagePoints    = InpSlippagePointsGold;

   configs[1].symbol            = "BTCUSD";
   configs[1].magicNumber       = (ulong)InpMagicBase + 2;
   configs[1].isCorrelatedGroup = true;
   configs[1].maxSpreadPoints   = InpMaxSpreadPointsCrypto;
   configs[1].slippagePoints    = InpSlippagePointsCrypto;

   configs[2].symbol            = "ETHUSD";
   configs[2].magicNumber       = (ulong)InpMagicBase + 3;
   configs[2].isCorrelatedGroup = true;
   configs[2].maxSpreadPoints   = InpMaxSpreadPointsCrypto;
   configs[2].slippagePoints    = InpSlippagePointsCrypto;
  }
```

- [ ] **Step 2: Write the test script**

`Test_Config.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Config.mqh"

void OnStart()
  {
   T_ResetCounters();

   SymbolConfig configs[];
   GetSymbolConfigs(configs);

   T_AssertEqualsInt("symbol count is 3", ArraySize(configs), 3);
   T_AssertEqualsString("index 0 is XAUUSD", configs[0].symbol, "XAUUSD");
   T_AssertEqualsString("index 1 is BTCUSD", configs[1].symbol, "BTCUSD");
   T_AssertEqualsString("index 2 is ETHUSD", configs[2].symbol, "ETHUSD");
   T_AssertTrue("XAUUSD not in correlated group", !configs[0].isCorrelatedGroup);
   T_AssertTrue("BTCUSD in correlated group", configs[1].isCorrelatedGroup);
   T_AssertTrue("ETHUSD in correlated group", configs[2].isCorrelatedGroup);
   T_AssertEqualsInt("XAUUSD magic = base+1", (int)configs[0].magicNumber, (int)InpMagicBase + 1);
   T_AssertEqualsInt("BTCUSD magic = base+2", (int)configs[1].magicNumber, (int)InpMagicBase + 2);
   T_AssertEqualsInt("ETHUSD magic = base+3", (int)configs[2].magicNumber, (int)InpMagicBase + 3);
   // BTC-before-ETH tie-break is enforced by this array's index order (1
   // before 2), consumed by the main loop in Task 15 - not re-checked here.

   T_PrintSummary("Test_Config");
  }
```

- [ ] **Step 3: Compile-check**

```bash
"/c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\Autobot_v1_Tests\Test_Config.mq5" /log:"D:\TradeBots\Autobot_v1\compile.log"
cat "D:/TradeBots/Autobot_v1/compile.log"
```

Expected: `0 errors`.

- [ ] **Step 4: Manual run**

Run `Test_Config` in the terminal (Scripts panel). Expected Experts-tab output: 9 `PASS:` lines, `0 failed`, `ALL TESTS PASSED: Test_Config`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/Config.mqh MQL5/Scripts/Autobot_v1_Tests/Test_Config.mq5
git commit -m "feat: add EA configuration (inputs, symbol list, magic numbers)"
```

---

### Task 3: SymbolState.mqh — Per-Symbol Runtime State

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\SymbolState.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_SymbolState.mq5`

**Interfaces:**
- Consumes: `SymbolConfig` (Task 2), `ENUM_BIAS` (Task 4 — see note below), `TRAIL_PHASE_1_BREAKEVEN` (Task 9 — see note below)
- Produces: `struct SymbolState {...}`, `void InitSymbolStates(SymbolState &states[], const SymbolConfig &configs[])`, `int FindSymbolIndex(const SymbolState &states[], string symbol)`

Note: this task's `SymbolState.mqh` references `ENUM_BIAS` (Task 4) and `TRAIL_PHASE_1_BREAKEVEN` (Task 9), which don't exist yet. To keep this task self-contained and compilable now, define `ENUM_BIAS` and the trail-phase constants directly in this task, then in Tasks 4 and 9 `#include "SymbolState.mqh"` instead of redefining them (SymbolState.mqh becomes the shared home for these small shared types, and is included by TrendFilter.mqh/TrailingStop.mqh instead of the other way around).

- [ ] **Step 1: Write SymbolState.mqh**

```mql
//+------------------------------------------------------------------+
//| SymbolState.mqh - per-symbol runtime state and shared enums      |
//+------------------------------------------------------------------+
#property strict
#include "Config.mqh"

enum ENUM_BIAS
  {
   BIAS_LONG,
   BIAS_SHORT,
   BIAS_NONE
  };

#define TRAIL_PHASE_1_BREAKEVEN 1
#define TRAIL_PHASE_2_STRUCTURE 2

struct SymbolState
  {
   string    symbol;
   ENUM_BIAS bias;
   datetime  lastH1BarTime;
   int       trailPhase;
   double    entryPrice;
   double    initialStopDistance;
   double    riskPercentAtEntry;
  };

void InitSymbolStates(SymbolState &states[], const SymbolConfig &configs[])
  {
   int n = ArraySize(configs);
   ArrayResize(states, n);
   for(int i = 0; i < n; i++)
     {
      states[i].symbol              = configs[i].symbol;
      states[i].bias                = BIAS_NONE;
      states[i].lastH1BarTime       = 0;
      states[i].trailPhase          = TRAIL_PHASE_1_BREAKEVEN;
      states[i].entryPrice          = 0.0;
      states[i].initialStopDistance = 0.0;
      states[i].riskPercentAtEntry  = 0.0;
     }
  }

int FindSymbolIndex(const SymbolState &states[], string symbol)
  {
   for(int i = 0; i < ArraySize(states); i++)
      if(states[i].symbol == symbol)
         return i;
   return -1;
  }
```

- [ ] **Step 2: Write the test script**

`Test_SymbolState.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/SymbolState.mqh"

void OnStart()
  {
   T_ResetCounters();

   SymbolConfig configs[];
   GetSymbolConfigs(configs);

   SymbolState states[];
   InitSymbolStates(states, configs);

   T_AssertEqualsInt("state count is 3", ArraySize(states), 3);
   T_AssertTrue("default bias is BIAS_NONE", states[0].bias == BIAS_NONE);
   T_AssertEqualsInt("default trail phase is PHASE_1", states[0].trailPhase, TRAIL_PHASE_1_BREAKEVEN);
   T_AssertEqualsInt("FindSymbolIndex(BTCUSD) == 1", FindSymbolIndex(states, "BTCUSD"), 1);
   T_AssertEqualsInt("FindSymbolIndex(ETHUSD) == 2", FindSymbolIndex(states, "ETHUSD"), 2);
   T_AssertEqualsInt("FindSymbolIndex(unknown) == -1", FindSymbolIndex(states, "DOGEUSD"), -1);

   T_PrintSummary("Test_SymbolState");
  }
```

- [ ] **Step 3: Compile-check** (same pattern as Task 1 Step 5, target `Test_SymbolState.mq5`). Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 5 `PASS:` lines, `ALL TESTS PASSED: Test_SymbolState`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/SymbolState.mqh MQL5/Scripts/Autobot_v1_Tests/Test_SymbolState.mq5
git commit -m "feat: add per-symbol runtime state and shared bias/trail-phase enums"
```

---

### Task 4: TrendFilter.mqh — H4 EMA Bias with ATR Deadband

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\TrendFilter.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_TrendFilter.mq5`

**Interfaces:**
- Consumes: `ENUM_BIAS` (Task 3, `SymbolState.mqh`)
- Produces: `ENUM_BIAS DetermineBias(double closePrice, double emaValue, double atrValue, double deadbandMultiplier)`

- [ ] **Step 1: Write TrendFilter.mqh**

```mql
//+------------------------------------------------------------------+
//| TrendFilter.mqh - H4 EMA200 trend bias with ATR deadband         |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

// Pure function: given an already-computed H4 close, EMA, and ATR value,
// determine directional bias. No indicator handles or live data access -
// callers fetch closePrice/emaValue/atrValue via CopyClose/CopyBuffer
// (see MarketData.mqh, Task 14).
ENUM_BIAS DetermineBias(double closePrice, double emaValue, double atrValue, double deadbandMultiplier)
  {
   double diff = closePrice - emaValue;
   double deadband = deadbandMultiplier * atrValue;

   if(diff > deadband)
      return BIAS_LONG;
   if(diff < -deadband)
      return BIAS_SHORT;
   return BIAS_NONE;
  }
```

- [ ] **Step 2: Write the test script**

`Test_TrendFilter.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TrendFilter.mqh"

void OnStart()
  {
   T_ResetCounters();

   // ATR=10, deadband multiplier=0.1 => deadband=1.0
   T_AssertTrue("price well above EMA => LONG", DetermineBias(2020.0, 2000.0, 10.0, 0.1) == BIAS_LONG);
   T_AssertTrue("price well below EMA => SHORT", DetermineBias(1980.0, 2000.0, 10.0, 0.1) == BIAS_SHORT);
   T_AssertTrue("price within deadband above => NONE", DetermineBias(2000.5, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price within deadband below => NONE", DetermineBias(1999.5, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price exactly at EMA => NONE", DetermineBias(2000.0, 2000.0, 10.0, 0.1) == BIAS_NONE);
   T_AssertTrue("price just past deadband edge => LONG", DetermineBias(2001.01, 2000.0, 10.0, 0.1) == BIAS_LONG);
   T_AssertTrue("zero ATR collapses deadband => any positive diff triggers LONG", DetermineBias(2000.01, 2000.0, 0.0, 0.1) == BIAS_LONG);

   T_PrintSummary("Test_TrendFilter");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 7 `PASS:` lines, `ALL TESTS PASSED: Test_TrendFilter`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/TrendFilter.mqh MQL5/Scripts/Autobot_v1_Tests/Test_TrendFilter.mq5
git commit -m "feat: add H4 EMA trend bias logic with ATR deadband"
```

---

### Task 5: EntrySignal.mqh — H1 Donchian(20) Breakout Detection

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\EntrySignal.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_EntrySignal.mq5`

**Interfaces:**
- Consumes: `ENUM_BIAS` (Task 3)
- Produces: `enum ENUM_SIGNAL {SIGNAL_LONG_BREAKOUT, SIGNAL_SHORT_BREAKOUT, SIGNAL_NONE}`, `ENUM_SIGNAL DetectBreakout(double currentClose, double priorHighestHigh, double priorLowestLow, ENUM_BIAS bias)`

- [ ] **Step 1: Write EntrySignal.mqh**

```mql
//+------------------------------------------------------------------+
//| EntrySignal.mqh - H1 Donchian(20) breakout detection             |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

enum ENUM_SIGNAL
  {
   SIGNAL_LONG_BREAKOUT,
   SIGNAL_SHORT_BREAKOUT,
   SIGNAL_NONE
  };

// Pure function. priorHighestHigh/priorLowestLow must be computed from the
// 20 bars BEFORE the just-closed bar (see MarketData.mqh ComputeDonchian,
// Task 14) - not including the bar being evaluated for breakout.
ENUM_SIGNAL DetectBreakout(double currentClose, double priorHighestHigh, double priorLowestLow, ENUM_BIAS bias)
  {
   if(bias == BIAS_LONG && currentClose > priorHighestHigh)
      return SIGNAL_LONG_BREAKOUT;
   if(bias == BIAS_SHORT && currentClose < priorLowestLow)
      return SIGNAL_SHORT_BREAKOUT;
   return SIGNAL_NONE;
  }
```

- [ ] **Step 2: Write the test script**

`Test_EntrySignal.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/EntrySignal.mqh"

void OnStart()
  {
   T_ResetCounters();

   // priorHigh=110, priorLow=90
   T_AssertTrue("long bias + close above prior high => LONG breakout",
                DetectBreakout(111.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_LONG_BREAKOUT);
   T_AssertTrue("long bias + close below prior high => NONE",
                DetectBreakout(109.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_NONE);
   T_AssertTrue("short bias + close below prior low => SHORT breakout",
                DetectBreakout(89.0, 110.0, 90.0, BIAS_SHORT) == SIGNAL_SHORT_BREAKOUT);
   T_AssertTrue("short bias + close above prior low => NONE",
                DetectBreakout(91.0, 110.0, 90.0, BIAS_SHORT) == SIGNAL_NONE);
   T_AssertTrue("no bias => NONE even if price breaks high",
                DetectBreakout(111.0, 110.0, 90.0, BIAS_NONE) == SIGNAL_NONE);
   T_AssertTrue("long bias but price breaks LOW, not high => NONE (wrong direction)",
                DetectBreakout(89.0, 110.0, 90.0, BIAS_LONG) == SIGNAL_NONE);

   T_PrintSummary("Test_EntrySignal");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 6 `PASS:` lines, `ALL TESTS PASSED: Test_EntrySignal`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/EntrySignal.mqh MQL5/Scripts/Autobot_v1_Tests/Test_EntrySignal.mq5
git commit -m "feat: add H1 Donchian(20) breakout signal detection"
```

---

### Task 6: RiskManager.mqh — Position Sizing

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\RiskManager.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_RiskManager_Sizing.mq5`

**Interfaces:**
- Produces: `double CalculateLotSize(double equity, double riskPercent, double stopDistancePrice, double tickValue, double tickSize, double volumeStep, double volumeMin, double volumeMax, bool &skipped)`

- [ ] **Step 1: Write RiskManager.mqh (sizing section — breakers and cap are appended in Tasks 7-8)**

```mql
//+------------------------------------------------------------------+
//| RiskManager.mqh - position sizing, circuit breakers, exposure cap|
//+------------------------------------------------------------------+
#property strict

// --- Position sizing ---------------------------------------------------

// Pure function. tickValue MUST be SYMBOL_TRADE_TICK_VALUE_PROFIT (or
// SYMBOL_TRADE_TICK_VALUE_LOSS for a more conservative estimate) - never
// the plain SYMBOL_TRADE_TICK_VALUE, which can be stale on CFDs like
// XAUUSD/BTCUSD/ETHUSD (see spec Risk Management > Position sizing).
double CalculateLotSize(double equity, double riskPercent, double stopDistancePrice,
                         double tickValue, double tickSize, double volumeStep,
                         double volumeMin, double volumeMax, bool &skipped)
  {
   skipped = false;

   if(stopDistancePrice <= 0.0 || tickSize <= 0.0 || tickValue <= 0.0 || volumeStep <= 0.0)
     {
      skipped = true;
      return 0.0;
     }

   double riskAmount  = equity * (riskPercent / 100.0);
   double valuePerLot = (tickValue / tickSize) * stopDistancePrice;
   double rawLots      = riskAmount / valuePerLot;

   double steppedLots = MathFloor(rawLots / volumeStep) * volumeStep;

   if(steppedLots < volumeMin)
     {
      skipped = true;
      return 0.0;
     }

   if(steppedLots > volumeMax)
      steppedLots = volumeMax;

   // Round to the broker's actual volume-step precision, not a hardcoded 2
   // decimals - a 0.001 volumeStep (common on some crypto CFDs) would
   // otherwise have its third decimal silently truncated away here.
   // [Task 17 / Fix 6]
   int volDigits = (int)MathMax(0, MathCeil(-MathLog10(volumeStep) - 0.0000001));
   return NormalizeDouble(steppedLots, volDigits);
  }
```

- [ ] **Step 2: Write the test script**

`Test_RiskManager_Sizing.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();
   bool skipped;
   double lots;

   // Case 1: normal sizing. equity=10000, risk=1% => riskAmount=100.
   // tickValue=1, tickSize=1 => valuePerLot = stopDistance = 5.0.
   // rawLots = 100/5 = 20.0, volumeStep=0.01 => steppedLots=20.00.
   lots = CalculateLotSize(10000.0, 1.0, 5.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("normal case not skipped", !skipped);
   T_AssertEqualsDouble("normal case lots = 20.00", lots, 20.00);

   // Case 2: computed size rounds below minimum volume => skipped.
   // equity=100, risk=1% => riskAmount=1.0. stopDistance=1000, tickValue=1,
   // tickSize=1 => valuePerLot=1000. rawLots=0.001 < volumeMin=0.01.
   lots = CalculateLotSize(100.0, 1.0, 1000.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("below-minimum case is skipped", skipped);
   T_AssertEqualsDouble("below-minimum case returns 0", lots, 0.0);

   // Case 3: computed size clamps to maximum volume.
   // equity=1,000,000, risk=1% => riskAmount=10000. stopDistance=1,
   // tickValue=1, tickSize=1 => valuePerLot=1. rawLots=10000, volumeMax=50.
   lots = CalculateLotSize(1000000.0, 1.0, 1.0, 1.0, 1.0, 0.01, 0.01, 50.0, skipped);
   T_AssertTrue("above-maximum case not skipped", !skipped);
   T_AssertEqualsDouble("above-maximum case clamps to 50.00", lots, 50.00);

   // Case 4: invalid stop distance => skipped.
   lots = CalculateLotSize(10000.0, 1.0, 0.0, 1.0, 1.0, 0.01, 0.01, 100.0, skipped);
   T_AssertTrue("zero stop distance is skipped", skipped);

   // Case 5 [Task 17 / Fix 6]: fine volumeStep (0.001, common on some crypto
   // CFDs) must preserve 3-decimal precision, not truncate to a hardcoded 2
   // decimals. equity=10000, risk=1% => riskAmount=100. tickValue=1,
   // tickSize=1 => valuePerLot=stopDistance=808. rawLots=100/808=0.123762...
   // steps down to 0.123 at volumeStep=0.001 (NOT 0.12).
   lots = CalculateLotSize(10000.0, 1.0, 808.0, 1.0, 1.0, 0.001, 0.001, 100.0, skipped);
   T_AssertTrue("fine volumeStep case not skipped", !skipped);
   T_AssertEqualsDouble("fine volumeStep case preserves 3-decimal precision (0.123, not 0.12)", lots, 0.123);

   T_PrintSummary("Test_RiskManager_Sizing");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 9 `PASS:` lines, `ALL TESTS PASSED: Test_RiskManager_Sizing`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/RiskManager.mqh MQL5/Scripts/Autobot_v1_Tests/Test_RiskManager_Sizing.mq5
git commit -m "feat: add ATR-based position sizing with min/max volume handling"
```

---

### Task 7: RiskManager.mqh — Circuit Breakers

**Files:**
- Modify: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\RiskManager.mqh` (append)
- Create: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_RiskManager_Breakers.mq5`

**Interfaces:**
- Produces: `bool UpdateDailyBreakerState(bool currentlyTripped, double dailyStartEquity, double currentEquity, double dailyLossPercent)`, `double UpdateEquityPeak(double currentPeak, double currentEquity)`, `bool IsMaxDrawdownTripped(double equityPeak, double currentEquity, double maxDrawdownPercent)`

- [ ] **Step 1: Append circuit-breaker functions to RiskManager.mqh**

Add this block at the end of `RiskManager.mqh` (after the position-sizing section from Task 6):

```mql

// --- Circuit breakers ---------------------------------------------------

// Sticky daily-loss breaker: once tripped, stays tripped regardless of
// equity recovery. Caller resets currentlyTripped to false at the next
// day boundary (see Autobot_v1.mq5, Task 15).
bool UpdateDailyBreakerState(bool currentlyTripped, double dailyStartEquity, double currentEquity, double dailyLossPercent)
  {
   if(currentlyTripped)
      return true;

   double threshold = dailyStartEquity * (1.0 - dailyLossPercent / 100.0);
   return (currentEquity <= threshold);
  }

// High-water mark - never decreases.
double UpdateEquityPeak(double currentPeak, double currentEquity)
  {
   return MathMax(currentPeak, currentEquity);
  }

// Not sticky in this function alone - the caller (Autobot_v1.mq5) ORs this
// into a persistent g_maxDrawdownTripped flag that requires manual
// re-enable, per spec (a 15% drawdown needs human review, not auto-resume).
bool IsMaxDrawdownTripped(double equityPeak, double currentEquity, double maxDrawdownPercent)
  {
   double threshold = equityPeak * (1.0 - maxDrawdownPercent / 100.0);
   return (currentEquity <= threshold);
  }
```

- [ ] **Step 2: Write the test script**

`Test_RiskManager_Breakers.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();

   // Daily breaker: trips exactly at the 5% threshold.
   T_AssertTrue("daily breaker trips at exactly 5% loss",
                UpdateDailyBreakerState(false, 10000.0, 9500.0, 5.0) == true);
   T_AssertTrue("daily breaker does not trip above threshold",
                UpdateDailyBreakerState(false, 10000.0, 9600.0, 5.0) == false);
   T_AssertTrue("daily breaker is sticky - stays tripped even after equity recovers",
                UpdateDailyBreakerState(true, 10000.0, 9999999.0, 5.0) == true);

   // Equity peak never decreases.
   T_AssertEqualsDouble("peak rises with equity", UpdateEquityPeak(10000.0, 10500.0), 10500.0);
   T_AssertEqualsDouble("peak does not fall with equity", UpdateEquityPeak(10500.0, 9000.0), 10500.0);

   // Max drawdown: trips exactly at the 15% threshold.
   T_AssertTrue("max drawdown trips at exactly 15% below peak",
                IsMaxDrawdownTripped(10000.0, 8500.0, 15.0) == true);
   T_AssertTrue("max drawdown does not trip above threshold",
                IsMaxDrawdownTripped(10000.0, 8600.0, 15.0) == false);

   T_PrintSummary("Test_RiskManager_Breakers");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 6 `PASS:` lines, `ALL TESTS PASSED: Test_RiskManager_Breakers`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/RiskManager.mqh MQL5/Scripts/Autobot_v1_Tests/Test_RiskManager_Breakers.mq5
git commit -m "feat: add sticky daily-loss and max-drawdown circuit breakers"
```

---

### Task 8: RiskManager.mqh — Correlated Exposure Cap

**Files:**
- Modify: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\RiskManager.mqh` (append)
- Create: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_RiskManager_ExposureCap.mq5`

**Interfaces:**
- Produces: `bool CanOpenCryptoPosition(double existingOtherSymbolRiskPercent, double newRiskPercent, double capPercent)`

- [ ] **Step 1: Append the exposure-cap function to RiskManager.mqh**

```mql

// --- Correlated exposure cap (BTCUSD + ETHUSD) --------------------------

// existingOtherSymbolRiskPercent is the OTHER crypto symbol's open risk
// (0 if none open), fixed at its risk-at-entry value per the spec's
// cap-basis decision (not recalculated as that trade trails).
// newRiskPercent is the risk the incoming trade would take if opened.
// The BTC-before-ETH tie-break is enforced structurally by main-loop
// array order (Config.mqh, Task 2) - this function only checks the cap.
bool CanOpenCryptoPosition(double existingOtherSymbolRiskPercent, double newRiskPercent, double capPercent)
  {
   double combined = existingOtherSymbolRiskPercent + newRiskPercent;
   return (combined <= capPercent + 0.0000001); // epsilon guards float rounding at the exact boundary
  }
```

- [ ] **Step 2: Write the test script**

`Test_RiskManager_ExposureCap.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/RiskManager.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertTrue("no existing crypto risk, 1% fits under 1.5% cap",
                CanOpenCryptoPosition(0.0, 1.0, 1.5) == true);
   T_AssertTrue("1% existing + 1% new exceeds 1.5% cap => blocked",
                CanOpenCryptoPosition(1.0, 1.0, 1.5) == false);
   T_AssertTrue("1% existing + 0.5% new exactly hits 1.5% cap => allowed",
                CanOpenCryptoPosition(1.0, 0.5, 1.5) == true);
   T_AssertTrue("single trade using the whole 1.5% budget => allowed",
                CanOpenCryptoPosition(0.0, 1.5, 1.5) == true);
   T_AssertTrue("single trade exceeding the whole budget => blocked",
                CanOpenCryptoPosition(0.0, 1.6, 1.5) == false);

   T_PrintSummary("Test_RiskManager_ExposureCap");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 5 `PASS:` lines, `ALL TESTS PASSED: Test_RiskManager_ExposureCap`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/RiskManager.mqh MQL5/Scripts/Autobot_v1_Tests/Test_RiskManager_ExposureCap.mq5
git commit -m "feat: add BTC/ETH correlated exposure cap check"
```

---

### Task 9: TrailingStop.mqh — Breakeven and Structure Trailing

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\TrailingStop.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_TrailingStop.mq5`

**Interfaces:**
- Consumes: `TRAIL_PHASE_1_BREAKEVEN`, `TRAIL_PHASE_2_STRUCTURE` (Task 3, `SymbolState.mqh`)
- Produces: `bool ShouldMoveToBreakeven(double unrealizedProfitPrice, double initialRiskPrice)`, `double CalculateBreakevenSL(double entryPrice, bool isLong, double bufferPrice)`, `double CalculateStructureTrailSL(double priorBarLow, double priorBarHigh, bool isLong)`, `int InferTrailPhase(double currentSL, double entryPrice, bool isLong)`

- [ ] **Step 1: Write TrailingStop.mqh**

```mql
//+------------------------------------------------------------------+
//| TrailingStop.mqh - breakeven + structure-based trailing           |
//+------------------------------------------------------------------+
#property strict
#include "SymbolState.mqh"

// unrealizedProfitPrice and initialRiskPrice are both in price units
// (not points), same sign convention (positive = favorable).
bool ShouldMoveToBreakeven(double unrealizedProfitPrice, double initialRiskPrice)
  {
   if(initialRiskPrice <= 0.0)
      return false;
   return (unrealizedProfitPrice >= initialRiskPrice);
  }

double CalculateBreakevenSL(double entryPrice, bool isLong, double bufferPrice)
  {
   return isLong ? (entryPrice + bufferPrice) : (entryPrice - bufferPrice);
  }

double CalculateStructureTrailSL(double priorBarLow, double priorBarHigh, bool isLong)
  {
   return isLong ? priorBarLow : priorBarHigh;
  }

// Infers which trailing phase a resumed position is in, per the spec's
// restart-reconstruction rule: SL at/past entry (favorable side) => Phase 2.
int InferTrailPhase(double currentSL, double entryPrice, bool isLong)
  {
   if(isLong)
      return (currentSL >= entryPrice) ? TRAIL_PHASE_2_STRUCTURE : TRAIL_PHASE_1_BREAKEVEN;
   else
      return (currentSL <= entryPrice) ? TRAIL_PHASE_2_STRUCTURE : TRAIL_PHASE_1_BREAKEVEN;
  }
```

- [ ] **Step 2: Write the test script**

`Test_TrailingStop.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/TrailingStop.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertTrue("profit >= risk triggers breakeven move", ShouldMoveToBreakeven(10.0, 10.0) == true);
   T_AssertTrue("profit < risk does not trigger breakeven move", ShouldMoveToBreakeven(9.0, 10.0) == false);
   T_AssertTrue("zero initial risk never triggers (guards div-by-zero elsewhere)", ShouldMoveToBreakeven(5.0, 0.0) == false);

   T_AssertEqualsDouble("long breakeven SL = entry + buffer", CalculateBreakevenSL(2000.0, true, 0.5), 2000.5);
   T_AssertEqualsDouble("short breakeven SL = entry - buffer", CalculateBreakevenSL(2000.0, false, 0.5), 1999.5);

   T_AssertEqualsDouble("long structure trail = prior bar low", CalculateStructureTrailSL(1990.0, 2010.0, true), 1990.0);
   T_AssertEqualsDouble("short structure trail = prior bar high", CalculateStructureTrailSL(1990.0, 2010.0, false), 2010.0);

   T_AssertEqualsInt("long, SL past entry => Phase 2", InferTrailPhase(2001.0, 2000.0, true), TRAIL_PHASE_2_STRUCTURE);
   T_AssertEqualsInt("long, SL below entry => Phase 1", InferTrailPhase(1990.0, 2000.0, true), TRAIL_PHASE_1_BREAKEVEN);
   T_AssertEqualsInt("short, SL past entry => Phase 2", InferTrailPhase(1999.0, 2000.0, false), TRAIL_PHASE_2_STRUCTURE);
   T_AssertEqualsInt("short, SL above entry => Phase 1", InferTrailPhase(2010.0, 2000.0, false), TRAIL_PHASE_1_BREAKEVEN);

   T_PrintSummary("Test_TrailingStop");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 11 `PASS:` lines, `ALL TESTS PASSED: Test_TrailingStop`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/TrailingStop.mqh MQL5/Scripts/Autobot_v1_Tests/Test_TrailingStop.mq5
git commit -m "feat: add breakeven and structure trailing-stop logic"
```

---

### Task 10: Persistence.mqh — File-Based State Survival

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\Persistence.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_Persistence.mq5`

**Interfaces:**
- Produces (as of Task 17 / Fixes 1, 2, 9 - see addendum at end of document): `bool SavePersistedState(double dailyStartEquity, long dailyStartDayCode, double equityPeak, bool dailyBreakerTripped, bool maxDrawdownTripped, bool testMode = false)`, `bool LoadPersistedState(double &dailyStartEquity, long &dailyStartDayCode, double &equityPeak, bool &dailyBreakerTripped, bool &maxDrawdownTripped, bool &fileValid, bool testMode = false)`

- [ ] **Step 1: Write Persistence.mqh**

```mql
//+------------------------------------------------------------------+
//| Persistence.mqh - file-based state survives VPS/terminal restarts|
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_PERSISTENCE_MQH
#define AUTOBOT_V1_PERSISTENCE_MQH

#define PERSIST_MAGIC_HEADER 954218L // bumped from 954217L when the two
                                      // breaker-tripped flags were added to
                                      // the binary format - this correctly
                                      // makes old-format files fail the
                                      // magic check below and get treated as
                                      // corrupt (fail-safe), rather than
                                      // silently misreading their bytes.

// testMode=true is used exclusively by test scripts (Test_Persistence.mq5)
// so they never read/write the production state file.
string PersistenceFileName(bool testMode = false)
  {
   return testMode ? "Autobot_v1_state.TEST.bin" : "Autobot_v1_state.bin";
  }

// Persistence is intentionally skipped ENTIRELY inside the Strategy Tester
// and optimization passes - both functions below early-exit before touching
// any file whenever MQL_TESTER/MQL_OPTIMIZATION is true. This guarantees
// every backtest starts as a genuine first run, seeded from its own actual
// deposit. A plain (non-FILE_COMMON) file still persists across consecutive
// backtests on the same Tester agent, which previously let a poisoned
// equity peak (or a stale breaker-tripped flag) from one run leak into the
// next run on that agent. Once we're past the early-exit we know we are NOT
// in the tester/optimization, so all real file I/O below uses FILE_COMMON
// unconditionally (the machine-wide folder needed for genuine live/demo
// VPS-reboot survival).
bool SavePersistedState(double dailyStartEquity, long dailyStartDayCode, double equityPeak,
                         bool dailyBreakerTripped, bool maxDrawdownTripped, bool testMode = false)
  {
   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
      return true;

   int handle = FileOpen(PersistenceFileName(testMode), FILE_WRITE | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return false;

   FileWriteLong(handle, PERSIST_MAGIC_HEADER);
   FileWriteDouble(handle, dailyStartEquity);
   FileWriteLong(handle, dailyStartDayCode);
   FileWriteDouble(handle, equityPeak);
   FileWriteLong(handle, dailyBreakerTripped ? 1 : 0);
   FileWriteLong(handle, maxDrawdownTripped ? 1 : 0);
   FileClose(handle);
   return true;
  }

// fileValid=false on any read failure, wrong-magic, or short file. Callers
// MUST treat fileValid=false (when a file was found) as the fail-safe
// trigger described in the spec - block new entries + alert - and never
// silently reseed state. Return value distinguishes "file exists" (true)
// from "no file at all" (false); check fileValid separately.
bool LoadPersistedState(double &dailyStartEquity, long &dailyStartDayCode, double &equityPeak,
                         bool &dailyBreakerTripped, bool &maxDrawdownTripped, bool &fileValid,
                         bool testMode = false)
  {
   dailyStartEquity    = 0.0;
   dailyStartDayCode   = 0;
   equityPeak          = 0.0;
   dailyBreakerTripped = false;
   maxDrawdownTripped  = false;
   fileValid           = false;

   if((bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION))
      return false; // report "not found" immediately - no tester/optimization state ever exists

   if(!FileIsExist(PersistenceFileName(testMode), FILE_COMMON))
      return false;

   int handle = FileOpen(PersistenceFileName(testMode), FILE_READ | FILE_BIN | FILE_COMMON);
   if(handle == INVALID_HANDLE)
      return true; // file exists but couldn't be opened - fileValid stays false

   ulong minSize = (ulong)(sizeof(long) * 4 + sizeof(double) * 2);
   if(FileSize(handle) < minSize)
     {
      FileClose(handle);
      return true;
     }

   long magic = FileReadLong(handle);
   if(magic != PERSIST_MAGIC_HEADER)
     {
      FileClose(handle);
      return true;
     }

   dailyStartEquity    = FileReadDouble(handle);
   dailyStartDayCode   = FileReadLong(handle);
   equityPeak          = FileReadDouble(handle);
   dailyBreakerTripped = (FileReadLong(handle) != 0);
   maxDrawdownTripped  = (FileReadLong(handle) != 0);
   FileClose(handle);

   fileValid = true;
   return true;
  }

#endif // AUTOBOT_V1_PERSISTENCE_MQH
```

- [ ] **Step 2: Write the test script**

`Test_Persistence.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Persistence.mqh"

void OnStart()
  {
   T_ResetCounters();

   // Clean slate. testMode=true throughout - never touches the production
   // Autobot_v1_state.bin file.
   if(FileIsExist(PersistenceFileName(true), FILE_COMMON))
      FileDelete(PersistenceFileName(true), FILE_COMMON);

   double eq, peak;
   long dayCode;
   bool dailyTripped, maxDDTripped;
   bool valid;

   // Missing file (genuine first run).
   bool found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("missing file: found=false", found == false);
   T_AssertTrue("missing file: valid=false", valid == false);

   // Round-trip, including the two breaker-tripped flags added alongside
   // the bumped magic header.
   T_AssertTrue("save succeeds", SavePersistedState(9800.0, 20260809, 10500.0, true, false, true));
   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("round-trip: found=true", found == true);
   T_AssertTrue("round-trip: valid=true", valid == true);
   T_AssertEqualsDouble("round-trip: dailyStartEquity matches", eq, 9800.0);
   T_AssertEqualsInt("round-trip: dailyStartDayCode matches", (int)dayCode, 20260809);
   T_AssertEqualsDouble("round-trip: equityPeak matches", peak, 10500.0);
   T_AssertTrue("round-trip: dailyBreakerTripped matches (true)", dailyTripped == true);
   T_AssertTrue("round-trip: maxDrawdownTripped matches (false)", maxDDTripped == false);

   // Round-trip again with the flags flipped, to make sure both booleans
   // are read back independently rather than one masking the other.
   T_AssertTrue("second save succeeds", SavePersistedState(9700.0, 20260810, 10600.0, false, true, true));
   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("second round-trip: valid=true", valid == true);
   T_AssertTrue("second round-trip: dailyBreakerTripped matches (false)", dailyTripped == false);
   T_AssertTrue("second round-trip: maxDrawdownTripped matches (true)", maxDDTripped == true);

   // Corruption: overwrite with a full-size record carrying the wrong magic
   // header, so the failure exercises the magic check (not the short-file
   // check) even with the bumped header size (4 longs + 2 doubles).
   int handle = FileOpen(PersistenceFileName(true), FILE_WRITE | FILE_BIN | FILE_COMMON);
   FileWriteLong(handle, 1111111L); // wrong magic
   FileWriteDouble(handle, 1.0);
   FileWriteLong(handle, 1L);
   FileWriteDouble(handle, 1.0);
   FileWriteLong(handle, 0L);
   FileWriteLong(handle, 0L);
   FileClose(handle);

   found = LoadPersistedState(eq, dayCode, peak, dailyTripped, maxDDTripped, valid, true);
   T_AssertTrue("corrupt file: found=true (file exists)", found == true);
   T_AssertTrue("corrupt file: valid=false (fail-safe triggers)", valid == false);

   // Cleanup.
   FileDelete(PersistenceFileName(true), FILE_COMMON);

   T_PrintSummary("Test_Persistence");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 16 `PASS:` lines, `ALL TESTS PASSED: Test_Persistence`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/Persistence.mqh MQL5/Scripts/Autobot_v1_Tests/Test_Persistence.mq5
git commit -m "feat: add file-based persistence with corruption fail-safe"
```

---

### Task 11: Logger.mqh — Structured CSV Event Logging

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\Logger.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_Logger.mq5`

**Interfaces:**
- Produces (as of Task 17 / Fix 9): `bool LogEvent(string timestamp, string symbol, string eventType, double price, double lots, double sl, double equity, string reasonTag, bool testMode = false)`

- [ ] **Step 1: Write Logger.mqh**

```mql
//+------------------------------------------------------------------+
//| Logger.mqh - structured CSV event logging                        |
//+------------------------------------------------------------------+
#property strict

#ifndef AUTOBOT_V1_LOGGER_MQH
#define AUTOBOT_V1_LOGGER_MQH

// testMode=true is used exclusively by test scripts (Test_Logger.mq5) so
// they never read/write the production log file.
string LogFileName(bool testMode = false)
  {
   return testMode ? "Autobot_v1_log.TEST.csv" : "Autobot_v1_log.csv";
  }

// FILE_COMMON is shared machine-wide across every terminal install AND the
// Strategy Tester - never isolated per live-account deployment. Using it
// unconditionally would mix backtest log rows into the live/demo trade
// journal (and vice versa). Only use FILE_COMMON for genuine live/demo
// runs; inside the Strategy Tester or an optimization pass, use a plain
// (non-common) file, which MT5 sandboxes per Tester agent.
int LogFileFlag()
  {
   bool inTesterOrOptimization = (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
   return inTesterOrOptimization ? 0 : FILE_COMMON;
  }

void EnsureLogHeader(bool testMode = false)
  {
   if(FileIsExist(LogFileName(testMode), LogFileFlag()))
      return;

   int handle = FileOpen(LogFileName(testMode), FILE_WRITE | FILE_CSV | LogFileFlag(), ',');
   if(handle == INVALID_HANDLE)
      return;
   FileWrite(handle, "timestamp", "symbol", "event_type", "price", "lots", "sl", "equity", "reason_tag");
   FileClose(handle);
  }

bool LogEvent(string timestamp, string symbol, string eventType, double price, double lots, double sl, double equity, string reasonTag, bool testMode = false)
  {
   EnsureLogHeader(testMode);

   int handle = FileOpen(LogFileName(testMode), FILE_READ | FILE_WRITE | FILE_CSV | LogFileFlag(), ',');
   if(handle == INVALID_HANDLE)
      return false;

   FileSeek(handle, 0, SEEK_END);
   FileWrite(handle, timestamp, symbol, eventType, DoubleToString(price, 5),
             DoubleToString(lots, 2), DoubleToString(sl, 5),
             DoubleToString(equity, 2), reasonTag);
   FileClose(handle);
   return true;
  }

#endif // AUTOBOT_V1_LOGGER_MQH
```

- [ ] **Step 2: Write the test script**

`Test_Logger.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Logger.mqh"

void OnStart()
  {
   T_ResetCounters();

   // testMode=true throughout - never touches the production
   // Autobot_v1_log.csv file.
   if(FileIsExist(LogFileName(true), FILE_COMMON))
      FileDelete(LogFileName(true), FILE_COMMON);

   T_AssertTrue("first log event succeeds",
                LogEvent("2026.08.09 12:00:00", "XAUUSD", "entry", 2000.12345, 0.10, 1990.0, 10000.0, "AutoBotV1|TrendBreak|H1", true));
   T_AssertTrue("second log event succeeds",
                LogEvent("2026.08.09 13:00:00", "BTCUSD", "exit", 65000.5, 0.01, 64000.0, 10050.0, "trail-stop", true));

   int handle = FileOpen(LogFileName(true), FILE_READ | FILE_CSV | FILE_COMMON, ',');
   T_AssertTrue("log file reopens for reading", handle != INVALID_HANDLE);

   string header = FileReadString(handle);
   T_AssertEqualsString("header field 0 is timestamp", header, "timestamp");
   for(int i = 0; i < 7; i++) FileReadString(handle); // skip remaining header fields

   string row1Timestamp = FileReadString(handle);
   T_AssertEqualsString("row 1 timestamp matches", row1Timestamp, "2026.08.09 12:00:00");
   string row1Symbol = FileReadString(handle);
   T_AssertEqualsString("row 1 symbol matches", row1Symbol, "XAUUSD");

   FileClose(handle);
   FileDelete(LogFileName(true), FILE_COMMON);

   T_PrintSummary("Test_Logger");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 5 `PASS:` lines, `ALL TESTS PASSED: Test_Logger`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/Logger.mqh MQL5/Scripts/Autobot_v1_Tests/Test_Logger.mq5
git commit -m "feat: add structured CSV event logging"
```

---

### Task 12: Notifier.mqh — Push and Telegram Alerts

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\Notifier.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_Notifier.mq5`

**Interfaces:**
- Produces: `bool IsNotificationSuppressed()`, `string EscapeJsonString(string text)`, `string FormatTelegramPayload(string chatId, string message)`, `void SendPushAlert(string message)`, `void SendTelegramAlert(string botToken, string chatId, string message)`, `void SendAlert(string message, bool telegramEnabled, string botToken, string chatId)`

- [ ] **Step 1: Write Notifier.mqh**

```mql
//+------------------------------------------------------------------+
//| Notifier.mqh - push + Telegram alerts, tester-safe, best-effort  |
//+------------------------------------------------------------------+
#property strict

// WebRequest does not execute inside the Strategy Tester at all, and MT5
// push notifications are meaningless during a backtest. Gate everything
// behind this check so Strategy Tester runs (Task 16) don't error out.
bool IsNotificationSuppressed()
  {
   return (bool)MQLInfoInteger(MQL_TESTER) || (bool)MQLInfoInteger(MQL_OPTIMIZATION);
  }

// Minimal JSON string escaping - only handles characters realistically
// present in our own alert messages (quotes, backslashes, newlines).
string EscapeJsonString(string text)
  {
   string result = text;
   StringReplace(result, "\\", "\\\\");
   StringReplace(result, "\"", "\\\"");
   StringReplace(result, "\n", "\\n");
   return result;
  }

string FormatTelegramPayload(string chatId, string message)
  {
   return StringFormat("{\"chat_id\":\"%s\",\"text\":\"%s\"}", chatId, EscapeJsonString(message));
  }

void SendPushAlert(string message)
  {
   if(IsNotificationSuppressed())
      return;
   SendNotification(message);
  }

// Best-effort: a failed/slow Telegram call must never block trading logic.
// WebRequest is synchronous, so only call this from OnTimer, never from a
// latency-sensitive path.
void SendTelegramAlert(string botToken, string chatId, string message)
  {
   if(IsNotificationSuppressed())
      return;
   if(botToken == "" || chatId == "")
      return;

   string url = "https://api.telegram.org/bot" + botToken + "/sendMessage";
   string payload = FormatTelegramPayload(chatId, message);
   uchar postData[];
   StringToCharArray(payload, postData, 0, StringLen(payload));
   uchar result[];
   string resultHeaders;
   int timeoutMs = 5000;

   ResetLastError();
   int status = WebRequest("POST", url, "Content-Type: application/json\r\n", timeoutMs, postData, result, resultHeaders);
   if(status == -1)
      PrintFormat("Notifier: Telegram WebRequest failed, error %d (is the URL allow-listed in Tools>Options>Expert Advisors?)", GetLastError());
  }

void SendAlert(string message, bool telegramEnabled, string botToken, string chatId)
  {
   SendPushAlert(message);
   if(telegramEnabled)
      SendTelegramAlert(botToken, chatId, message);
  }
```

- [ ] **Step 2: Write the test script**

`Test_Notifier.mq5`:

```mql
#property strict
#include "TestUtils.mqh"
#include "../../Experts/Autobot_v1/Include/Notifier.mqh"

void OnStart()
  {
   T_ResetCounters();

   T_AssertEqualsString("escapes quotes", EscapeJsonString("say \"hi\""), "say \\\"hi\\\"");
   T_AssertEqualsString("escapes backslashes", EscapeJsonString("a\\b"), "a\\\\b");

   string payload = FormatTelegramPayload("12345", "hello");
   T_AssertEqualsString("telegram payload format", payload, "{\"chat_id\":\"12345\",\"text\":\"hello\"}");

   // Running as a normal script (not inside Strategy Tester/optimization),
   // suppression must be false. The true-branch (inside Strategy Tester) is
   // exercised by the Task 16 Strategy Tester smoke test, not here.
   T_AssertTrue("notifications not suppressed in a normal script run", IsNotificationSuppressed() == false);

   T_PrintSummary("Test_Notifier");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Expected: 4 `PASS:` lines, `ALL TESTS PASSED: Test_Notifier`.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/Notifier.mqh MQL5/Scripts/Autobot_v1_Tests/Test_Notifier.mq5
git commit -m "feat: add push and Telegram alerting, gated out of Strategy Tester"
```

---

### Task 13: TradeExecution.mqh — Order Execution, Retries, Duplicate Prevention

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\TradeExecution.mqh`
- Test: `D:\TradeBots\Autobot_v1\MQL5\Scripts\Autobot_v1_Tests\Test_TradeExecution.mq5`

**Interfaces:**
- Produces: `bool ShouldRetry(uint retcode, int attemptCount, int maxRetries)`, `bool HasExistingPositionOrOrder(string symbol, ulong magic)`, `bool ExecuteMarketOrder(CTrade &trade, string symbol, ENUM_ORDER_TYPE orderType, double lots, double stopLoss, ulong magic, string comment, int deviationPoints, int maxRetries)`
- Produces (added in Task 17 / Fix 4): `double ClampStopLossToMinDistance(double stopLoss, bool isLong, double currentPrice, double minDistance, int digits)` (pure), `double NormalizeAndClampStopLoss(string symbol, double stopLoss, bool isLong)` (glue) - see addendum at end of document. Also gains an `#ifndef AUTOBOT_V1_TRADEEXECUTION_MQH` include guard (added alongside Fix 4, following this codebase's standard guard pattern).

**Safety note**: this task's test script places a real pending order on the connected account. It MUST verify the account is a demo account before doing so (see Global Constraints).

- [ ] **Step 1: Write TradeExecution.mqh**

```mql
//+------------------------------------------------------------------+
//| TradeExecution.mqh - CTrade wrapper: retries, dup-check, SL      |
//+------------------------------------------------------------------+
#property strict
#include <Trade\Trade.mqh>

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

// --- [Task 17 / Fix 4] Stop-loss normalization / stops-level & freeze-level clamp ---

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
   int    digits            = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double point             = SymbolInfoDouble(symbol, SYMBOL_POINT);
   double stopsLevelPoints  = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_STOPS_LEVEL);
   double freezeLevelPoints = (double)SymbolInfoInteger(symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double minDistance       = MathMax(stopsLevelPoints, freezeLevelPoints) * point;
   double currentPrice      = isLong ? SymbolInfoDouble(symbol, SYMBOL_BID) : SymbolInfoDouble(symbol, SYMBOL_ASK);
   return ClampStopLossToMinDistance(stopLoss, isLong, currentPrice, minDistance, digits);
  }
```

Called from `Autobot_v1.mq5` (Task 15, updated by Task 17 / Fix 4) at three sites: the entry `stopLoss` right before `ExecuteMarketOrder`, the breakeven SL right before `PositionModify`, and the structure-trail SL right before `PositionModify`.

`Test_TradeExecution_Stops.mq5` (added in Task 17 / Fix 4) tests only the pure `ClampStopLossToMinDistance` function with hardcoded long/short, too-close/far-enough cases - no live-account guard needed since it never touches the MT5 API. See addendum at end of document.

- [ ] **Step 2: Write the test script**

`Test_TradeExecution.mq5`:

```mql
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

   // --- Live-state: ExecuteMarketOrder ---
   // Opens a real minimum-volume market position on the demo account (the
   // demo-account guard above already covers this block), verifies the SL
   // actually landed on the live position (not just accepted client-side),
   // then closes it immediately. This is the function Task 15's main EA
   // uses for every real entry, so it must be proven against a live
   // broker round-trip, not just unit-tested in isolation.
   double bid2         = SymbolInfoDouble(TEST_SYMBOL, SYMBOL_BID);
   double stopDistance = bid2 * 0.05; // 5% away - can't be hit by normal spread/slippage during the test
   double sl           = NormalizeDouble(bid2 - stopDistance, (int)SymbolInfoInteger(TEST_SYMBOL, SYMBOL_DIGITS));
   double minLots      = SymbolInfoDouble(TEST_SYMBOL, SYMBOL_VOLUME_MIN);

   bool orderSent = ExecuteMarketOrder(trade, TEST_SYMBOL, ORDER_TYPE_BUY, minLots, sl, TEST_MAGIC,
                                        "Autobot_v1 ExecuteMarketOrder test", 200, 3);
   T_AssertTrue("ExecuteMarketOrder market buy succeeds", orderSent);

   if(orderSent)
     {
      bool   foundPosition = false;
      double actualSL      = 0.0;

      // Brief retry in case of fill-reporting latency between trade.Buy()
      // returning true and the position appearing in PositionsTotal().
      for(int attempt = 0; attempt < 5 && !foundPosition; attempt++)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == TEST_SYMBOL && (ulong)PositionGetInteger(POSITION_MAGIC) == TEST_MAGIC)
              {
               foundPosition = true;
               actualSL      = PositionGetDouble(POSITION_SL);
               break;
              }
           }
         if(!foundPosition)
            Sleep(200);
        }

      T_AssertTrue("opened position found after ExecuteMarketOrder", foundPosition);
      T_AssertTrue("stop loss attached to the live position", actualSL > 0.0);
     }

   // Unconditional safety-net cleanup: close ANY position matching this
   // test's symbol+magic, regardless of whether the search above found it,
   // so a transient lookup miss can never leave a real position open.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket != 0 && PositionGetString(POSITION_SYMBOL) == TEST_SYMBOL && (ulong)PositionGetInteger(POSITION_MAGIC) == TEST_MAGIC)
         trade.PositionClose(ticket);
     }

   T_AssertTrue("no leftover ExecuteMarketOrder position after close", HasExistingPositionOrOrder(TEST_SYMBOL, TEST_MAGIC) == false);

   T_PrintSummary("Test_TradeExecution");
  }
```

- [ ] **Step 3: Compile-check.** Expected: `0 errors`.

- [ ] **Step 4: Manual run.** Ask the user to confirm the terminal is on the demo account before running. Expected: 11 `PASS:` lines (or the single ABORTED failure line if run against a non-demo account, which is the correct, intended behavior — do not treat that as a task failure, it's the safety guard working), `ALL TESTS PASSED: Test_TradeExecution`. This run briefly opens and closes a real minimum-volume position on the demo account as part of verifying `ExecuteMarketOrder` end-to-end.

- [ ] **Step 5: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/TradeExecution.mqh MQL5/Scripts/Autobot_v1_Tests/Test_TradeExecution.mq5
git commit -m "feat: add order execution wrapper with retries and duplicate-order prevention"
```

---

### Task 14: MarketData.mqh — Indicator Handles and Data-Fetching Glue

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Include\MarketData.mqh`

**Interfaces:**
- Consumes: `SymbolConfig` (Task 2)
- Produces: `bool CreateIndicatorHandles(const SymbolConfig &configs[], int &emaHandles[], int &atrH4Handles[], int &atrH1Handles[], int emaPeriod, int atrPeriod)`, `void ReleaseIndicatorHandles(int &emaHandles[], int &atrH4Handles[], int &atrH1Handles[])`, `bool ComputeH4Bias(string symbol, int emaHandle, int atrH4Handle, double &closeOut, double &emaOut, double &atrOut)`, `bool ComputeDonchian(string symbol, int period, double &highestHigh, double &lowestLow)`, `bool ComputeATRH1(int atrH1Handle, double &atrOut)`

This module is pure MT5-API glue (indicator handles, `CopyClose`/`CopyBuffer`/`CopyHigh`/`CopyLow`) and is intentionally **not** unit-tested with hardcoded inputs — it has no live market/history data to unit-test against outside the terminal. It is verified by (a) compiling cleanly and (b) the Task 16 Strategy Tester smoke test, which exercises it against real historical data.

- [ ] **Step 1: Write MarketData.mqh**

```mql
//+------------------------------------------------------------------+
//| MarketData.mqh - indicator handle lifecycle and data-fetching    |
//| glue. Not unit-tested in isolation - see Task 16 for verification|
//| against real historical data via the Strategy Tester.            |
//+------------------------------------------------------------------+
#property strict
#include "Config.mqh"

bool CreateIndicatorHandles(const SymbolConfig &configs[], int &emaHandles[], int &atrH4Handles[], int &atrH1Handles[],
                             int emaPeriod, int atrPeriod)
  {
   int n = ArraySize(configs);
   ArrayResize(emaHandles, n);
   ArrayResize(atrH4Handles, n);
   ArrayResize(atrH1Handles, n);

   for(int i = 0; i < n; i++)
     {
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
```

- [ ] **Step 2: Compile-check**

Since this module has no accompanying test script (see rationale above), verify it compiles as part of a throwaway one-line smoke script:

```bash
cat > "/tmp/mktdata_smoke.mq5" << 'EOF'
#property strict
#include "../../Experts/Autobot_v1/Include/MarketData.mqh"
void OnStart() { Print("compiles"); }
EOF
cp "/tmp/mktdata_smoke.mq5" "D:/TradeBots/Autobot_v1/MQL5/Scripts/Autobot_v1_Tests/_MarketDataCompileCheck.mq5"
"/c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Scripts\Autobot_v1_Tests\_MarketDataCompileCheck.mq5" /log:"D:\TradeBots\Autobot_v1\compile.log"
cat "D:/TradeBots/Autobot_v1/compile.log"
rm "D:/TradeBots/Autobot_v1/MQL5/Scripts/Autobot_v1_Tests/_MarketDataCompileCheck.mq5" "D:/TradeBots/Autobot_v1/MQL5/Scripts/Autobot_v1_Tests/_MarketDataCompileCheck.ex5"
```

Expected: `0 errors`. The throwaway script is deleted immediately after — `MarketData.mqh` gets its real compile coverage for free once Task 15 includes it from `Autobot_v1.mq5`.

- [ ] **Step 3: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Include/MarketData.mqh
git commit -m "feat: add indicator handle lifecycle and market-data glue functions"
```

---

### Task 15: Autobot_v1.mq5 — Main EA Wiring

**Files:**
- Create: `D:\TradeBots\Autobot_v1\MQL5\Experts\Autobot_v1\Autobot_v1.mq5`

**Interfaces:**
- Consumes: every module from Tasks 2-14.
- Produces: the compiled `Autobot_v1.ex5` EA.

- [ ] **Step 1: Write Autobot_v1.mq5**

**As of Task 17 (whole-branch review fixes), the file has been substantially updated** - see the addendum at the end of this document for the itemized rationale (Fixes 2, 3, 4, 5, 7, 8, 10). The code block below reflects the FINAL, current state of `Autobot_v1.mq5`, not the original Task 15 version.

```mql
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
// every OnTimer() call. See GetOtherCryptoOpenRiskPercent(). [Task 17 / Fix 7]
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
   // [Task 17 / Fix 10] Demo-only guard: v1 is deliberately scoped to
   // demo-account use per the design spec. The Strategy Tester and
   // optimization passes are exempted since they aren't real accounts.
   // This must be the first substantive check in OnInit, before any other
   // setup.
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
      // [Task 17 / Fix 2] We can't trust anything in this branch - stay
      // maximally conservative on both breaker flags, not just max-drawdown.
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
         // [Task 17 / Fix 2] A new day has started since the file was
         // written - mirror OnTimer's day-rollover logic. Yesterday's daily
         // trip must never carry into today.
         g_dailyStartEquity    = nowEquity;
         g_dailyStartDayCode   = CurrentDayCode();
         g_dailyBreakerTripped = false;
        }
      else
         g_dailyBreakerTripped = loadedDailyBreakerTripped;

      // [Task 17 / Fix 2] Sticky across restarts unless a human explicitly
      // clears it via InpClearMaxDrawdownBreaker - a restart alone must
      // never clear it.
      g_maxDrawdownTripped = InpClearMaxDrawdownBreaker ? false : loadedMaxDrawdownTripped;
     }
   else
     {
      g_dailyStartEquity    = nowEquity;
      g_dailyStartDayCode   = CurrentDayCode();
      g_equityPeak          = nowEquity;
      g_dailyBreakerTripped = false;
      g_maxDrawdownTripped  = false;
      SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped);
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

// [Task 17 / Fix 3] Fires on every deal (fill), including closes. Used only
// to log the "exit" event for our own symbols/magics - entries are already
// logged in ProcessSymbol at the point the order is sent.
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

// [Task 17 / Fix 7] Returns the larger of: (a) the OTHER correlated-group
// symbol's live open risk (from an already-materialized position), or (b)
// risk committed to a correlated-group symbol earlier in this SAME OnTimer
// pass whose position may not have materialized in PositionsTotal() yet.
// Without (b), two crypto signals firing in the same pass could both read
// "no other position open" and both pass the cap check, exceeding
// InpCorrelatedCapPercent.
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
         // [Task 17 / Fix 4] normalize/clamp to the broker's stops-level and
         // freeze-level before sending.
         newSL = NormalizeAndClampStopLoss(symbol, newSL, isLong);

         // [Task 17 / Fix 3, Fix 5] capture and log the PositionModify
         // result instead of silently discarding failures.
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
      return;
     }

   double priorBarLow  = iLow(symbol, PERIOD_H1, 1);
   double priorBarHigh = iHigh(symbol, PERIOD_H1, 1);
   double newTrailSL   = CalculateStructureTrailSL(priorBarLow, priorBarHigh, isLong);
   newTrailSL = NormalizeAndClampStopLoss(symbol, newTrailSL, isLong); // [Task 17 / Fix 4]

   bool improves = isLong ? (newTrailSL > currentSL) : (newTrailSL < currentSL);
   if(improves)
     {
      bool modified = g_trade.PositionModify(ticket, newTrailSL, 0.0); // [Task 17 / Fix 3, Fix 5]
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
      // [Task 17 / Fix 8] log skipped data-unavailable events instead of a
      // silent return.
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

   stopLoss = NormalizeAndClampStopLoss(symbol, stopLoss, isLong); // [Task 17 / Fix 4]

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
         g_pendingCryptoRiskThisPass += InpRiskPercent; // [Task 17 / Fix 7]
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
   g_pendingCryptoRiskThisPass = 0.0; // [Task 17 / Fix 7] reset every pass

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
         SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped);
     }

   bool wasDailyBreakerTripped = g_dailyBreakerTripped; // [Task 17 / Fix 2, Fix 3]
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
         SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped);
     }

   double previousPeak = g_equityPeak;
   g_equityPeak = UpdateEquityPeak(g_equityPeak, currentEquity);
   if(g_equityPeak != previousPeak && !g_entriesBlockedPersistenceFailsafe)
      SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped);

   bool wasMaxDDTripped = g_maxDrawdownTripped;
   g_maxDrawdownTripped = g_maxDrawdownTripped || IsMaxDrawdownTripped(g_equityPeak, currentEquity, InpMaxDrawdownPercent);
   if(g_maxDrawdownTripped && !wasMaxDDTripped)
     {
      LogEvent(TimeToString(TimeCurrent()), "ACCOUNT", "circuit-breaker-tripped", 0, 0, 0, currentEquity, "max-drawdown"); // [Task 17 / Fix 3]
      SendAlert(StringFormat("Autobot_v1: MAX DRAWDOWN circuit breaker tripped. Peak=%.2f Current=%.2f. New entries disabled - manual re-enable required.",
                             g_equityPeak, currentEquity),
                InpEnableTelegram, InpTelegramBotToken, InpTelegramChatID);
      // Make the trip durable immediately rather than waiting for the next
      // scheduled save point.
      if(!g_entriesBlockedPersistenceFailsafe)
         SavePersistedState(g_dailyStartEquity, g_dailyStartDayCode, g_equityPeak, g_dailyBreakerTripped, g_maxDrawdownTripped);
     }

   bool newEntriesAllowed = !g_dailyBreakerTripped && !g_maxDrawdownTripped && !g_entriesBlockedPersistenceFailsafe;

   for(int i = 0; i < ArraySize(g_symbolConfigs); i++)
      ProcessSymbol(i, newEntriesAllowed, currentEquity);

   MaybeSendHeartbeat();
  }
```

- [ ] **Step 2: Compile-check**

```bash
"/c/Program Files/MetaTrader 5/MetaEditor64.exe" /compile:"C:\Users\jahir\AppData\Roaming\MetaQuotes\Terminal\D0E8209F77C8CF37AD8BF550E51FF075\MQL5\Experts\Autobot_v1\Autobot_v1.mq5" /log:"D:\TradeBots\Autobot_v1\compile.log"
cat "D:/TradeBots/Autobot_v1/compile.log"
```

Expected: `0 errors`. Fix any compiler errors before proceeding — small signature/type mismatches between this file and the modules from Tasks 2-14 are the most likely issue; correct whichever side is wrong and recompile.

- [ ] **Step 3: Manual smoke run**

Ask the user to: (1) confirm the terminal is on the demo account, (2) attach `Autobot_v1` to any XAUUSD/BTCUSD/ETHUSD chart with default inputs, and (3) paste back the Experts-tab log for the first ~30 seconds.

Expected: a line matching `Autobot_v1 initialized. dailyStartEquity=... equityPeak=... persistenceFailsafe=false` (on first run) and no error/exception lines. Remove the EA from the chart after confirming (this is a smoke check, not a live-trading start).

**Updated by Task 17 / Fix 10**: as of the whole-branch review fixes, `OnInit()` now checks `AccountInfoInteger(ACCOUNT_TRADE_MODE) != ACCOUNT_TRADE_MODE_DEMO` as its very first step and returns `INIT_FAILED` with a `Print()` message on any non-demo account (unless `InpAllowLiveAccount=true`). On a genuine demo account (the expected setup for this smoke test) this check passes through silently and the rest of `OnInit()` behaves exactly as before - no change to the expected output above. A human verifying this step should additionally confirm the terminal really is on a demo account (not just assume it), since that assumption is now enforced by the EA itself rather than only documented.

- [ ] **Step 4: Commit**

```bash
cd "D:/TradeBots/Autobot_v1"
git add MQL5/Experts/Autobot_v1/Autobot_v1.mq5
git commit -m "feat: wire up Autobot_v1 main EA (OnInit/OnTimer/OnTick/OnDeinit)"
```

---

### Task 16: Strategy Tester Smoke Test and Deployment Checklist

This is a verification-only task — no new code. It's the integration gate confirming the whole EA runs against real historical data without crashing, and documents the manual steps needed before any live/demo unattended run.

**Files:** none created or modified.

- [ ] **Step 1: Ensure historical data is available**

Ask the user to open History Center (or simply open a chart) for XAUUSD, BTCUSD, and ETHUSD on H1 and H4 timeframes, and scroll back far enough to force MT5 to download at least 30 days of history for each. MT5's multi-currency Strategy Tester only includes symbols it has historical data for — this step prevents a silent "0 trades" result caused by missing data on BTCUSD/ETHUSD rather than the strategy itself.

- [ ] **Step 2: Run a short Strategy Tester pass**

Ask the user to open Strategy Tester (View > Strategy Tester), select `Autobot_v1`, any one of the three symbols as the base chart symbol, model "Every tick based on real ticks," a short recent date range (e.g. the last 30 days), default inputs, and click Start.

- [ ] **Step 3: Verify the run**

Ask the user to report back:
- Whether the run completed without a crash/exception in the Journal tab.
- Whether the "Trade" or "Results" tab shows activity on more than just the base chart symbol (confirms multi-currency testing picked up BTCUSD/ETHUSD too — if not, re-check Step 1's history download).
- Whether `Autobot_v1_state.bin` and `Autobot_v1_log.csv` were created under the terminal's `MQL5\Files\Common` (or `Common\Files`) folder, and whether the CSV contains rows beyond just the header.

If the run crashes or produces zero activity across all three symbols over 30 days, treat that as a bug to fix (return to the relevant task, e.g. re-check `MarketData.mqh`'s Donchian/ATR shift indices), not as an acceptable outcome — this is the first point where the fully-wired system runs against real data, and it is expected to at least log skip/entry events even if it takes no trades in a quiet 30-day window.

- [ ] **Step 4: Document remaining manual deployment steps**

These are one-time setup steps for actually running the EA live/demo unattended — not something to automate now, just confirm the user has done them before leaving the EA running unattended:
- If Telegram alerts are wanted: create a bot via @BotFather, get the bot token and chat ID, add `https://api.telegram.org` to Tools > Options > Expert Advisors > "Allow WebRequest for listed URL," and set `InpEnableTelegram=true` with the token/chat ID as EA inputs (never edit them into the source file).
- Enable MT5 mobile push notifications: Tools > Options > Notifications, pair the mobile app via QR/MetaQuotes ID.
- Confirm "Algo Trading" (AutoTrading) is enabled in the terminal toolbar before attaching the EA for real use.

- [ ] **Step 5: No commit for this task** (verification-only). If Step 3 uncovered a bug and required going back to fix a task's code, that fix gets its own commit under that task's normal step 5 pattern.

---

## Self-Review

**Spec coverage**: Architecture (Task 1, 15), symbol config/magic numbers (Task 2), H4 bias + deadband (Task 4), H1 Donchian entry (Task 5), position sizing with correct tick-value fields (Task 6), sticky daily breaker + max-drawdown breaker (Task 7), correlated cap + BTC-before-ETH tie-break (Task 8), breakeven/structure trailing + phase reconstruction (Task 9), persistence with fail-safe and `FILE_COMMON` (Task 10), CSV logging (Task 11), push + Telegram alerting gated out of the tester, heartbeat (Task 12, 15), execution retries/duplicate-prevention/always-attached SL (Task 13), indicator handle lifecycle/data glue (Task 14), OnTimer-based multi-symbol loop (Task 15), Strategy Tester verification (Task 16). All spec sections are covered.

**Placeholder scan**: no TBD/TODO markers; every step has complete, concrete code or a concrete manual-verification procedure with expected output stated.

**Type consistency**: `SymbolConfig`/`SymbolState`/`ENUM_BIAS`/`ENUM_SIGNAL`/`TRAIL_PHASE_*` are each defined exactly once (Config.mqh, SymbolState.mqh, EntrySignal.mqh) and consumed identically by name in every later task and in `Autobot_v1.mq5`. Function signatures used in Task 15 (`CalculateLotSize`, `UpdateDailyBreakerState`, `CanOpenCryptoPosition`, `ShouldMoveToBreakeven`, `CalculateBreakevenSL`, `CalculateStructureTrailSL`, `InferTrailPhase`, `ExecuteMarketOrder`, `HasExistingPositionOrOrder`, `ComputeH4Bias`, `ComputeDonchian`, `ComputeATRH1`, `LogEvent`, `SendAlert`) all match their Task 2-14 definitions exactly.

---

## Task 17: Whole-Branch Review Fixes (post-Task-16)

A final whole-branch review of the completed Tasks 1-16 build found 10 Important-severity findings. All 10 were fixed in this task. This section documents *why* each fix exists; the individual task sections above have already been updated in place to show the *current, final* code for every function/section touched (search for `[Task 17 / Fix N]` inline comments in the code blocks above to find each change in context).

**Files touched:** `Include/Persistence.mqh`, `Include/Config.mqh`, `Include/Logger.mqh`, `Include/RiskManager.mqh`, `Include/TradeExecution.mqh`, `Autobot_v1.mq5`, `Scripts/Autobot_v1_Tests/Test_Persistence.mq5`, `Scripts/Autobot_v1_Tests/Test_Logger.mq5`, `Scripts/Autobot_v1_Tests/Test_RiskManager_Sizing.mq5`, `Scripts/Autobot_v1_Tests/Test_TradeExecution_Stops.mq5` (new).

- **Fix 1 (tester-state carryover)**: `SavePersistedState`/`LoadPersistedState` now early-exit (no-op save / "not found" load) whenever `MQL_TESTER`/`MQL_OPTIMIZATION` is true, before touching any file. Every backtest now starts as a genuine first run seeded from its own deposit; a poisoned equity peak or breaker flag from a prior tester run on the same agent can no longer leak forward. `PersistenceFileFlag()` was removed - all real I/O now uses `FILE_COMMON` unconditionally, since by the time that code runs we know we're not in the tester.
- **Fix 2 (breaker flags not persisted)**: `dailyBreakerTripped`/`maxDrawdownTripped` are now part of the persisted binary format (as `long` 0/1), gated behind a bumped `PERSIST_MAGIC_HEADER` (954217 -> 954218) so old-format files are correctly rejected by the existing corruption fail-safe rather than misread. New input `InpClearMaxDrawdownBreaker` (Config.mqh, Risk Management group) is the only sanctioned way to clear a max-drawdown trip across a restart. `OnInit()`'s restore branch now honors the loaded flags (with a day-rollover check that resets the daily flag on a new day) instead of unconditionally clearing the daily flag and recomputing max-drawdown from scratch. `OnTimer()` now saves state immediately on both breakers' rising edge, not just at the next scheduled save point.
- **Fix 3 (missing log events)**: daily-breaker trip now both logs (`circuit-breaker-tripped`/`daily-loss`) and alerts (previously neither existed); max-drawdown trip now also logs (previously alert-only). `ManageOpenPosition` now logs `trail-update`/`trail-update-failed` for both the breakeven and structure-trail `PositionModify` calls. A new `OnTradeTransaction` handler logs an `exit` event on every closing deal for the EA's own magics.
- **Fix 4 (unnormalized SL, no stops/freeze-level check)**: new pure function `ClampStopLossToMinDistance` + glue `NormalizeAndClampStopLoss` in `TradeExecution.mqh`, called at all three SL call sites (entry, breakeven move, structure trail) right before the value is used. New test `Test_TradeExecution_Stops.mq5` covers the pure function directly.
- **Fix 5 (silent PositionModify failures)**: implemented together with Fix 3 - both `PositionModify` call sites now check their boolean result and log success/failure explicitly instead of discarding it.
- **Fix 6 (hardcoded 2-decimal lot rounding)**: `CalculateLotSize` now rounds to the broker's actual `volumeStep` precision (`volDigits` derived from `-log10(volumeStep)`) instead of a hardcoded `NormalizeDouble(steppedLots, 2)`. New Case 5 in `Test_RiskManager_Sizing.mq5` proves a `volumeStep=0.001` result keeps 3 decimals.
- **Fix 7 (correlated-cap same-pass race)**: new global `g_pendingCryptoRiskThisPass`, reset at the top of every `OnTimer()`, incremented by `InpRiskPercent` immediately after a successful correlated-group order send. `GetOtherCryptoOpenRiskPercent` now returns `MathMax(liveRisk, g_pendingCryptoRiskThisPass)` so a second crypto signal in the same pass can no longer both pass the cap check before either position materializes in `PositionsTotal()`.
- **Fix 8 (silent Compute* failures)**: each of the three `if(!Compute...(...)) return;` branches in `ProcessSymbol` now logs `signal-skipped-data-unavailable` with a distinguishing reason tag (`compute-h4-bias-failed` / `compute-donchian-failed` / `compute-atr-failed`) before returning. Self-rate-limiting since it only runs once per symbol per new H1 bar.
- **Fix 9 (tests touching production file paths)**: `PersistenceFileName`/`SavePersistedState`/`LoadPersistedState` and `LogFileName`/`EnsureLogHeader`/`LogEvent` all gained a trailing optional `testMode = false` parameter (placed after Fix 2's new breaker-flag parameters, per the ordering constraint). `testMode=true` swaps to `Autobot_v1_state.TEST.bin`/`Autobot_v1_log.TEST.csv`. `Autobot_v1.mq5`'s existing call sites never pass this parameter and are unaffected. `Test_Persistence.mq5`/`Test_Logger.mq5` now pass `true` everywhere, including their own direct `FileIsExist`/`FileOpen`/`FileDelete` cleanup calls.
- **Fix 10 (no live-account guard)**: new input `InpAllowLiveAccount` (Config.mqh, Execution group, default `false`). `OnInit()`'s first substantive check now returns `INIT_FAILED` on any non-demo, non-tester, non-optimization account unless this input is explicitly set `true`.

**Fix 1 / Fix 9 interaction (explicitly verified, not just assumed)**: Fix 1 makes `SavePersistedState`/`LoadPersistedState` no-op whenever `MQL_TESTER`/`MQL_OPTIMIZATION` is true. Fix 9's `testMode` parameter is used exclusively by `Test_Persistence.mq5`/`Test_Logger.mq5`, which run as ordinary scripts in the live terminal - `MQLInfoInteger(MQL_TESTER)` is false in that context, so Fix 1's early-exit never fires for these tests and `testMode=true` behaves exactly as intended (production-file isolation only, no tester-related no-op). The two fixes touch the same functions' signatures but operate on independent conditions and do not interfere.

**Call-site audit**: every call site of `SavePersistedState`, `LoadPersistedState`, and `LogEvent` across the whole repository was located via `grep` and updated/verified against the new signatures - `Autobot_v1.mq5` (OnInit first-run save, OnInit corrupt/missing-with-history branches which don't call Save, OnTimer day-rollover save, OnTimer peak-update save, OnTimer daily/max-drawdown rising-edge saves, all `LogEvent` call sites in `ProcessSymbol`/`ManageOpenPosition`/`OnTradeTransaction`/`OnTimer`) and the two test scripts (`Test_Persistence.mq5`, `Test_Logger.mq5`). All compile with 0 errors, 0 warnings.

**Verification**: all touched `.mqh`/`.mq5` files plus every existing test script (changed or not) were compile-checked individually via MetaEditor CLI after these changes, plus the full `Autobot_v1.mq5` (which transitively includes every module) - all report `0 errors, 0 warnings`. No automated MQL5 test runner exists in this environment (see Global Constraints), so the actual PASS/FAIL assertion output of the updated/new test scripts, and a live Strategy Tester run confirming the new logging doesn't disrupt a backtest, remain a manual verification step for a human with the terminal open - see the task's final report for the itemized list.
