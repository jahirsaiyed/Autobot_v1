# Subscribing and Running (Buyer Side)

This is the flow for someone who found Autobot_v1 on the MQL5 Market (as opposed to building it from this repo's source — see [01-running-the-ea.md](01-running-the-ea.md) for that path).

## 1. Get the product

1. In the MT5 terminal: open the **Market** tab in the Toolbox (bottom panel), or browse mql5.com's Market section in a browser and open the product page.
2. Depending on how the seller listed it, choose **Free**, **Rent** (time-limited), or **Buy** (permanent license).
3. Confirm the purchase/activation in your MQL5.com account if prompted.

## 2. Download into your terminal

1. Back in MT5's **Market** tab, find the product under **Purchased**.
2. Click **Download** (or it may auto-sync on next terminal restart). This places the compiled `.ex5` directly into your terminal's `MQL5/Experts/` folder — no MetaEditor/compiling needed on the buyer side, since Market products ship pre-compiled and protected.

## 3. Attach and activate

1. Open a chart for a symbol the EA trades (XAUUSD, BTCUSD, or ETHUSD — check the product description for which symbols/names your broker uses).
2. Drag the EA from the Navigator onto the chart.
3. On first run, MT5 may prompt an **activation** step tied to your MQL5 account/account number (this is the Market's built-in licensing, separate from anything in the EA's own inputs).
4. Make sure **Algo Trading** is enabled in the toolbar.

## 4. Configure inputs

Same input set as the source-build path — see the tables in [01-running-the-ea.md](01-running-the-ea.md#input-reference). In particular:

- Confirm you're on a **demo account** unless you've made your own informed decision to enable `InpAllowLiveAccount` (read the product description's stance on this — see the callout in [04-publishing-to-mql5-market.md](04-publishing-to-mql5-market.md#before-you-publish-the-demo-only-guard)).
- If you want Telegram alerts, follow [02-telegram-alerts.md](02-telegram-alerts.md) — this works identically whether you're running the source build or a Market copy, since the bot token/chat ID are input fields you fill in yourself, not something the seller can see or set for you.

## 5. Running unattended

Nothing here differs from the source-build path — see [03-vps-deployment.md](03-vps-deployment.md). One Market-specific note: an "activated"/purchased EA is typically tied to a limited number of accounts (check the product's license terms) — moving to a VPS may count as a new activation, so check the seller's terms on activation limits before deploying to a VPS if you're on a paid license.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| EA won't start, log shows a "demo-only" refusal message | Working as designed — see the demo-only guard note above; this is not a bug |
| No Telegram messages | WebRequest URL not allow-listed on *this* terminal, or `InpEnableTelegram=false` — see [02-telegram-alerts.md](02-telegram-alerts.md) |
| "Invalid account" / activation prompt loops | Check the Market license's activation limit for your purchase type |
| EA attached but never trades | Confirm Algo Trading is on, confirm the chart symbol matches one of `InpTradeXAUUSD`/`InpTradeBTCUSD`/`InpTradeETHUSD`, and check spread against the relevant `InpMaxSpreadPoints*` guard |
