# VPS Deployment

Running Autobot_v1 on a VPS keeps it trading 24/5 without depending on your own PC staying on and connected. Two paths: MetaQuotes' built-in VPS, or a general-purpose Windows VPS.

## Option A: MetaQuotes VPS (simplest)

1. In MT5, with the EA already attached and running on your own machine: **right-click the chart > Trading > VPS Hosting** (or the *File > Open an Account* VPS prompt).
2. Choose a VPS location close to your broker's server for lower latency.
3. Rent the VPS. MT5 migrates your currently-running terminal state — including the attached EA and its chart/inputs — to the VPS.
4. Confirm on the VPS view that **Algo Trading** is enabled and the EA shows in the top-right corner without a red "X" (no errors).

This is the lowest-effort option since MetaQuotes handles the OS/terminal setup for you.

## Option B: Third-party Windows VPS

Use this if you want more control (e.g. running other software, or a specific region MetaQuotes doesn't offer).

1. Provision a Windows Server/Windows VPS from any provider. Minimum spec: this EA is lightweight (5-second timer, a handful of indicator handles per symbol) — a small instance is sufficient.
2. RDP into the VPS.
3. Install the MT5 terminal for your broker (download from the broker's site, not a generic MetaQuotes installer, to ensure it connects to the right trade servers).
4. Log in with your **demo account** credentials (see the demo-only guard in [01-running-the-ea.md](01-running-the-ea.md)).
5. Repeat the install steps from [01-running-the-ea.md](01-running-the-ea.md): copy `Autobot_v1.mq5` + `Include/`, compile, enable Algo Trading, attach to each symbol chart.
6. If using Telegram alerts, repeat the WebRequest allow-listing from [02-telegram-alerts.md](02-telegram-alerts.md) on this terminal — it is a per-install setting, not something that transfers automatically.
7. Set the terminal to auto-login and auto-start on VPS reboot: **Tools > Options > General** and enable auto-login, and place a shortcut to `terminal64.exe` in the Windows Startup folder so it survives a VPS reboot without you RDP'ing back in.

## Things specific to this EA on a VPS

- **One terminal instance per machine.** State (`Autobot_v1_state.bin`) and the trade log (`Autobot_v1_log.csv`) are written to the terminal's shared **Common** files folder (`FILE_COMMON`), not per-terminal-data-folder. Running two separate terminal installs under the same Windows user on the same VPS would have them silently share/clobber the same state file. Stick to one terminal install per VPS.
- **After any VPS crash/reboot/interruption**, re-open the chart and confirm the EA reloaded correctly — persistence is designed to survive this (equity baselines, circuit-breaker trip flags, trail phase are all restored from disk on `OnInit`), but it's worth a manual check the first few times, especially confirming the daily-loss/max-drawdown breaker state matches what you expect.
- **Time zone**: the daily-loss breaker resets on the broker's trade-server day (`TimeTradeServer()`), not the VPS's local clock — no action needed, just don't be surprised if "daily" resets don't line up with your own timezone.
- **Telegram heartbeat is your VPS health check** — if `InpEnableTelegram` is on, a missed heartbeat (per `InpHeartbeatHours`) is a good signal something died (VPS down, terminal crashed, disconnected from broker).

## Verifying it's actually running unattended

- Close your RDP session (don't shut down the VPS) and confirm via Telegram heartbeat, or by reconnecting later, that the EA kept running.
- Check the **Experts** and **Journal** tabs after a reconnect for any errors that occurred while you were away.
