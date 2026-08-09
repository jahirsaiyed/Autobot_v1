//+------------------------------------------------------------------+
//| Config.mqh - Autobot_v1 tunable inputs and symbol configuration  |
//+------------------------------------------------------------------+
#property strict

// Include guard: MQL5 has no #pragma once and no automatic double-include
// protection. This header is included both directly (Autobot_v1.mq5) and
// transitively (via SymbolState.mqh, used by several other modules), so
// without this guard a multi-module compile unit fails with "already
// defined" errors on every input/struct/function below.
#ifndef AUTOBOT_V1_CONFIG_MQH
#define AUTOBOT_V1_CONFIG_MQH

input group "Risk Management"
input double InpRiskPercent            = 1.0;   // Risk per trade (% of equity)
input double InpDailyLossPercent       = 5.0;   // Daily loss circuit breaker (%)
input double InpMaxDrawdownPercent     = 15.0;  // Max drawdown circuit breaker (%)
input double InpCorrelatedCapPercent   = 1.5;   // BTC+ETH combined risk cap (%)
input bool   InpClearMaxDrawdownBreaker = false; // Explicit human re-enable after a max-drawdown trip

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

#endif // AUTOBOT_V1_CONFIG_MQH
