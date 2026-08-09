//+------------------------------------------------------------------+
//| Notifier.mqh - push + Telegram alerts, tester-safe, best-effort  |
//+------------------------------------------------------------------+
#property strict

// Include guard: MQL5 has no #pragma once and no automatic double-include
// protection. Without this guard, multi-module compile would fail with
// "already defined" errors.
#ifndef AUTOBOT_V1_NOTIFIER_MQH
#define AUTOBOT_V1_NOTIFIER_MQH

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

#endif // AUTOBOT_V1_NOTIFIER_MQH
