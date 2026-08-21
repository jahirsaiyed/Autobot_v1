# Telegram Alerts

Autobot_v1 can push trade events, circuit-breaker trips, and a periodic heartbeat to Telegram via `Include/Notifier.mqh`. This is best-effort: a slow or failed Telegram call never blocks trade management, and alerts are automatically suppressed during Strategy Tester and optimization runs.

## 1. Create a Telegram bot

1. In Telegram, message **@BotFather**.
2. Send `/newbot` and follow the prompts (choose a name and a unique username ending in `bot`).
3. BotFather replies with a **bot token** — a string like `123456789:AAH...`. Keep it private.

## 2. Get your chat ID

1. Send any message to your new bot (or add it to a group/channel and send a message there).
2. In a browser, open:
   `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates`
3. Find `"chat":{"id": ... }` in the JSON response — that number is your `InpTelegramChatID`. For a group chat this is typically negative.

## 3. Allow-list the Telegram API URL in MT5

MT5 blocks all `WebRequest` calls to URLs not explicitly allow-listed, per terminal install:

1. In MT5: **Tools > Options > Expert Advisors**.
2. Check **Allow WebRequest for listed URL**.
3. Add: `https://api.telegram.org`
4. Click OK.

Do this on every terminal instance that will run the EA — the allow-list is per-terminal, not inherited from source, so it must be repeated on a VPS install too.

## 4. Configure the EA inputs

When attaching (or re-attaching) `Autobot_v1` to a chart, set on the **Inputs** tab under **Alerting**:

| Input | Value |
|---|---|
| `InpEnableTelegram` | `true` |
| `InpTelegramBotToken` | your bot token |
| `InpTelegramChatID` | your chat ID |
| `InpHeartbeatHours` | how often you want a "still alive" ping (default 24) |

Never hardcode the token/chat ID into the `.mq5` source — set them per-deployment via the input dialog, so a shared/published copy of the EA doesn't leak your credentials.

## 5. Verify it works

- Trigger a manual test: temporarily set `InpHeartbeatHours` to `1` and wait, or just leave the EA running past its next heartbeat interval, and confirm a message like *"Autobot_v1: heartbeat - EA is running."* arrives.
- If nothing arrives, check the **Experts** log tab for:
  `Notifier: Telegram WebRequest failed, error <code> (is the URL allow-listed in Tools>Options>Expert Advisors?)`
  This means step 3 wasn't applied to this specific terminal.

## What gets sent

- Circuit-breaker trips (daily loss, max drawdown)
- Order-send failures and `PositionModify` failures
- Periodic heartbeat (interval controlled by `InpHeartbeatHours`)

Push notifications to the MetaTrader mobile app (`SendNotification`) also fire alongside Telegram, independent of `InpEnableTelegram`, if you've linked a MetaQuotes ID in the terminal — Telegram is additive, not a replacement.
