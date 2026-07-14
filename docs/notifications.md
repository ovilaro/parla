# Desktop notification spec

Contract for Parla's notifications. Changes to this behavior must keep these
rules true or update this file in the same commit. Design mirrors the official
client (`third_party/deltachat-desktop/.../system-integration/notifications.ts`);
core semantics in `third_party/core`.

Code: `src/event_handler.vala` (dispatch, send/withdraw, ids, startup
reconcile), `src/window.vala` (`queue_chat_notification`, flush, composition,
`check_mention`, `notice_chat`, `is_chat_visible`), `src/conversation_view.vala`
(seen-marking).

**App focused** = `window.visible && window.is_active` (hide-to-tray clears
`visible`).

## Ids (same id = banner replaced, not duplicated)

| Id | Meaning |
|----|---------|
| `dc-chat-<acct>-<chat>` | message/reaction banner for one chat |
| `dc-chat-<acct>-0` | account-wide group banner |
| `dc-mention-<acct>-<chat>` | high-priority mention banner |
| `dc-msg-<acct>-<msg>` | legacy id, only ever withdrawn |

## Rules

Triggers
- **T1** Only `IncomingMsg` and `IncomingReaction` (reaction to own message)
  may create a banner, for current and background accounts alike.
- **T2** All other events (syncs, chatlist, `IncomingMsgBunch`, …) only update
  badges or withdraw banners. *(Guard: syncs used to re-pop the same banner.)*
- **T3** Never build banners from `get_fresh_msgs` — core excludes muted,
  contact-request and blocked chats there, which swallowed notifications.
  Mute is filtered client-side (M1).

Suppression (at queue time)
- **S1** Notifications disabled in settings → drop (also re-checked at flush).
- **S2** App focused → drop, for every account and chat (in-app badges suffice).
- **S3** Drop means drop: nothing fires later on unfocus.
- **S4** App unfocused/minimized/in tray → notify, even for the selected chat.

Batching
- **B1** Flush 400 ms after the first queued item; group by account, then chat.
- **B2** >3 chats for one account in a flush → single group banner
  (`…-0`): "N new messages" / "In M chats"; no per-chat banners.

Composition (per chat, at flush)
- **M1** `FullChat.isMuted` → no banner (mentions exempt, X2).
- **C1** Title = chat name (fallback "New message"); bg accounts prefixed
  `"[displayname-or-addr] "`; priority NORMAL.
- **C2** One message + contents allowed: title "Sender (Chat)", body = text |
  file name | "New message". Several: body "N new messages" (this flush only).
- **C3** Reactions only: latest wins; "X reacted <emoji>" / "New reaction".
- **C4** Contents hidden: generic bodies, no sender/text (title stays chat
  name, which in DMs equals the contact).

Click
- **A1** Default action `app.open-chat(acct, chat)`: present window, switch
  account, open chat (chat 0 → present only).
- **A2** Action attached only if the server advertises `actions` (queried
  once; notify-osd would render a modal dialog otherwise).

Withdrawal
- **W1** `MsgsNoticed(chat)` (read here or on another device) withdraws the
  chat's banner, its mention banner and the account group banner.
- **W2** Opening a chat (`notice_chat`) withdraws the same ids directly —
  covers reaction banners, which never produce `MsgsNoticed`.
- **W3** Startup reconcile withdraws every id of every account.
- **W4** Seen-marking: visible chat → seen immediately; current-but-unfocused
  chat → deferred until looked at, so its banner stays valid.

Mentions (`check_mention`, independent)
- **X1** Incoming text matching own display name / addresses = mention.
- **X2** Sent immediately, HIGH priority, ignores mute, exempt from S2 —
  suppressed only when viewing that chat in an active window.
- **X3** Also tints the chat row (current account) until opened.

Settings: `notifications_enabled` (S1, tray-toggleable),
`show_notification_contents` (C2/C4).

## Accepted quirks

- **Q1** Mention bodies ignore `show_notification_contents`.
- **Q2** X2 checks `is_active` but not `visible` (unlike `is_chat_visible`).
- **Q3** Group banner (B2) doesn't filter muted chats.
- **Q4** "N new messages" counts the flush, not the chat's total fresh count.
