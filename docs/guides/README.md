# Autobot_v1 Operations Guides

Practical, code-grounded guides for running, deploying, and distributing the Autobot_v1 EA. For the underlying strategy design, see `docs/superpowers/specs/2026-08-09-mt5-trend-ea-design.md`.

Read in this order:

1. [Running the EA](01-running-the-ea.md) — install, compile, attach, full input reference, demo-only guard
2. [Telegram Alerts](02-telegram-alerts.md) — bot setup, chat ID, WebRequest allow-listing
3. [VPS Deployment](03-vps-deployment.md) — MetaQuotes VPS vs third-party Windows VPS, 24/5 unattended running
4. [Publishing to the MQL5 Market](04-publishing-to-mql5-market.md) — seller side: submission, source protection, the demo-only decision
5. [Subscribing and Running](05-subscribing-and-running.md) — buyer side: purchasing, activation, running a Market copy

## A note that applies across all five guides

Autobot_v1 refuses to trade on a live account by default (`InpAllowLiveAccount=false`), a deliberate and verified design decision, not a bug. Every guide above treats that as a real constraint rather than something to route around.
