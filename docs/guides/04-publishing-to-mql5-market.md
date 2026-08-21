# Publishing to the MQL5 Market

This covers publishing Autobot_v1 as a product on the MQL5 Market (mql5.com), from the seller side. MQL5.com's own submission checklist is the source of truth for exact current requirements — treat this as an orientation, not a substitute for it, since Market policies do change over time.

## Before you publish: the demo-only guard

Autobot_v1 currently **refuses to trade on a live account** by default (`OnInit` in `Autobot_v1.mq5`, gated by `InpAllowLiveAccount` — see [01-running-the-ea.md](01-running-the-ea.md#demo-only-guard)). This was a deliberate, verified design decision, not an oversight.

That has a direct consequence for Market publishing: most Market buyers expect to eventually run a product on a live account. You have two honest options, and this guide isn't going to pick one for you:

1. **Publish as-is, listed clearly as demo-only** (e.g. free, or as an "evaluate on demo" product). Buyers can set `InpAllowLiveAccount=true` themselves after their own evaluation, same as you would.
2. **Deliberately decide to relax the guard** for the published version, as a separate, conscious change — not something to do casually while writing docs. If you go this route, treat it as a real code change with its own review, not a docs edit.

Whichever you choose, don't let the product page imply live-readiness that the code doesn't actually have.

## 1. Seller account

1. Create/verify a seller account on mql5.com (a MetaQuotes ID account with seller status enabled — requires identity verification for withdrawals if you plan to charge money).
2. Free products typically have a lower bar than paid ones; if this is your first listing, consider starting free.

## 2. Prepare the product

1. Compile a clean, warning-free `.ex5` (MQL5 Market re-compiles/verifies your source server-side during submission — it does not accept a pre-compiled binary you upload standalone).
2. Write a clear product description: what it trades (XAUUSD/BTCUSD/ETHUSD), the strategy (H4 trend bias + H1 Donchian breakout), the full input reference (mirror the table in [01-running-the-ea.md](01-running-the-ea.md)), and — explicitly — that it ships demo-only unless the buyer opts in.
3. Prepare screenshots: EA attached to a chart, Strategy Tester results, and the Inputs dialog.
4. Have a Strategy Tester report ready (MQL5 Market screening includes automated testing on MetaQuotes' own infrastructure) — the `.superpowers/sdd/progress.md` record of a clean 2026-07-01→2026-08-08 BTCUSD/H1 tester run is the kind of evidence to keep on hand, though you'll want a fresh run against current market data before submitting.

## 3. Source protection

Since you're not distributing raw `.mq5` source:

- **MQL5 Cloud Protector** is automatic for anything sold through the Market — MetaQuotes applies asymmetric encryption and account/hardware binding server-side. No extra work required for Market-only distribution.
- If you also plan to distribute outside the Market (e.g. direct sales), see `.agents/skills/mql-developer/references/security-licensing.md` for custom account-based licensing and manual Cloud Protector usage.
- Either way: never hardcode a Telegram token, license key, or any other secret into the `.mq5` source before submission — those stay as empty-default `input` fields the buyer fills in themselves, exactly as `InpTelegramBotToken`/`InpTelegramChatID` already are.

## 4. Submit for review

1. Upload via the MQL5 Market seller dashboard on mql5.com.
2. Automated screening checks for things like: no external DLL calls, no undisclosed network calls (your Telegram `WebRequest` call is fine since it's user-configured and off by default via `InpEnableTelegram=false`), and that it runs cleanly on MetaQuotes' own demo/tester environment.
3. Expect a review cycle — MetaQuotes staff may reject with specific feedback; address and resubmit.
4. Set pricing (or free), rental options if desired, and publish once approved.

## 5. After publishing

- Keep a versioned changelog; the Market shows version history to buyers, and `#property version` in `Autobot_v1.mq5` should be bumped on every update.
- Monitor product-page comments/support requests — this is buyer-facing once listed, unlike the internal `.superpowers/sdd/` task tracking used during development.

## Next

For the buyer's side of this same product: [05-subscribing-and-running.md](05-subscribing-and-running.md)
