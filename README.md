# wheel_wise_supabase

Supabase backend (database, auth, storage, realtime) for the WHEEL WISE™ app. The React Native app lives in
a separate repo (`WheelUI`) and talks to this project through `src/lib/supabase.ts`.

- Supabase project ref: `xgujbqsqipsuiibsmcvy`
- URL: `https://xgujbqsqipsuiibsmcvy.supabase.co`

## Tables

| Table | Holds |
|---|---|
| `profiles` | One row per member: `full_name`, `language` (chosen at sign-up, editable in Profile), `membership_id` (`WW100001`, …), `deleted_at` (set when the member deletes their account; soft delete), `deleted_email` (the deleted member's original email, kept for the team; the auth user's email is swapped for a placeholder so the email is free again), and the chat privacy settings `show_in_member_list` (off = left out of the Members list) and `allow_messages` (off = no messaging at all, both ways and in every chat: nobody can message them and they can't send messages; old messages stay visible), both on by default. Created automatically on sign-up by the `on_auth_user_created` trigger. Members can update only `full_name`, `language`, `show_in_member_list` and `allow_messages`. |
| `user_settings` | One row per member, one column per setting: `wheel_type` (`european` / `americanDoubleZero` / `tripleZero`), `display_style` (`standard` / `highContrast`), `last_number` (last selected pocket: `0`–`36`, `00`, `000`, or null), `show_clock_face` (clock face around the wheel on/off, default on), `updated_at`. The database rejects invalid values. Gives a member the same settings on every device. |
| `teaching_progress` | One row per member: where they are in the Brain De Fogger™ lessons. `status` (`new` / `started` / `skipped` / `completed`; the app opens the lessons by itself after sign-in until they are completed or skipped), `lesson` and `step` (last step the member was on, 0-based), `done_lessons` (finished lessons, 0-based), `saved_at` (set by the app; the newer of the device copy and this row wins). Members can read, insert and update only their own row. |

Row-level security is on for these tables: each member can only read and write their own row.

### Member chat (B20)

| Table | Holds |
|---|---|
| `conversations` | One row per chat. `kind` is `direct` (1:1) or `group` (reserved). `direct_key` (the two member ids, sorted) makes each pair share one chat. `last_message_at` orders the inbox (kept up to date by the `messages_touch_conversation` trigger). |
| `conversation_members` | Who is in each chat, plus `last_read_at` (that member's read marker, used for unread counts and read receipts: the other member sees "Seen" on messages sent before it). `cleared_at` ("Clear chat": messages up to then are hidden from that member only) and `removed_at` ("Remove": the chat also leaves that member's inbox until a new message arrives). Published to **Realtime** so read receipts update live. Members cannot write this table directly. |
| `messages` | `kind` is `text`, `image` or `video`. `body` is the text, or an optional caption for media (max 1000 chars; text messages cannot be empty). `deleted_at` is set when the sender deletes the message (`delete_message`). It is a soft delete: the text, attachments and files are kept so the message can be retrieved, and the team can restore it by clearing `deleted_at`. Every member-facing query skips deleted messages. `edited_at` is set when the sender edits the text or caption (`edit_message`); the app shows "Edited". Published to **Realtime** so new messages, and edits and deletions (as updates), are pushed live. |
| `blocked_members` | Who each member has blocked (`blocker_id`, `blocked_id`, `created_at`). A member adds and removes only their own rows (block / unblock) and sees only their own blocks, never who blocked them. While a block exists, in either direction, neither member can send messages or upload files in their chat. Earlier messages stay visible. |
| `message_attachments` | Files for image/video messages (several per message allowed): `storage_path`, `mime_type`, `size_bytes`, `width`, `height`, `duration_ms`, `thumbnail_path` (not used yet). |

Storage: private bucket **`chat-media`** (50 MB per file; images: jpeg, png, heic, heif, webp, gif;
videos: mp4, quicktime, 3gpp, webm). Files live at `<conversation_id>/<sender_id>/<file>`.
Only members of that conversation can read them, and a member can upload only into their own
folder. Members cannot delete files. The app shows files through short-lived signed URLs.

Typing indicator: Realtime broadcast on the private channel `typing:<conversation_id>`; nothing is saved.
Policies on `realtime.messages` let only members of that conversation join, send or receive.

Who can see what: only members of a conversation can read its messages, attachments and files.
Messages can only be sent as yourself, and not while either member has blocked the other.
A new chat can't be started with a member who has `allow_messages` off.
The rules for privacy controls, reporting and moderation are still to be agreed with the client.

### Feedback (M)

| Table | Holds |
|---|---|
| `feedback` | One row per message a member sends from the Feedback screen: `topic` (`bug` / `idea` / `wheel` / `teaching` / `other`), `rating` (1–5, drawn as wheels in the app), `message` (max 2000 chars, cannot be empty), `language` and `platform` at send time, `status` (`new` / `reviewed` / `closed`), `created_at`. |

Members can only **insert** their own feedback; they cannot read, edit or delete it. The team reviews
it in the Supabase dashboard (Table editor → `feedback`, filter `status = new`) and updates
`status` there. No screenshot attachments yet (would need a storage bucket). Topics and the review
process are placeholders until the client agrees them.

### Membership (App Store / Google Play)

Membership is one auto-renewing subscription (Annual or Monthly) bought through the App Store or
Google Play, and it belongs to the member's **WHEEL WISE account** (their email login), not to the
phone. It follows the member to any device, and someone else who signs in on the same phone does
not get it.

| Table | Holds |
|---|---|
| `store_subscriptions` | One row per store subscription, linked to one account (`user_id`). `platform` (`apple` / `google`), `store_subscription_id` (Apple `originalTransactionId`, which stays the same across renewals; Google purchase token), `product_id`, `plan_id` (`annual` / `monthly`), `status` (`active`, `grace_period`, `billing_retry`, `on_hold`, `paused`, `pending`, `expired`, `revoked` = refunded, `replaced` = Google plan change), `expires_at` (end of the paid or grace period), `auto_renew`, `environment` (`production` / `sandbox`), `store_data` (last store response, for support). A subscription can belong to only one account (unique per platform + store id). Members can **read** their own rows only; only the edge functions (service role) write. |
| `store_events` | Log of every App Store / Google Play server notification: type, subscription, `outcome` (`saved:<status>`, `no_account`, `not_found`, `ignored_other_app`, `error`, ...), payload. Service role only; for support (Table editor → `store_events`). |

A member has access while one of their subscriptions is `active` or `grace_period` and `expires_at`
is in the future.

How a purchase becomes a membership:

1. The app starts the store purchase with the member's user id attached (Apple `appAccountToken`,
   Google `obfuscatedAccountId`).
2. The app sends the purchase to the `verify-purchase` edge function, which reads it from Apple /
   Google's server API, checks it is a WHEEL WISE membership for this app, and links it to the
   account. If the purchase carries a different account's id, or is already linked to another
   account, the reply is `other_account` and nothing is granted. Google purchases are
   acknowledged here (Google refunds unacknowledged purchases after 3 days).
3. Only then does the app finish the store transaction, so a purchase interrupted by a crash or
   lost connection is sent again on the next launch.
4. Renewals, cancellations, billing problems, refunds and expiry arrive as store notifications
   (`apple-notifications`, `google-notifications`), which update the row. The app re-reads
   `get_my_membership()` on sign-in, on returning to the foreground and when the paid period ends.

### Functions the app calls (RPC)

All require a signed-in member and act only on that member's own data.

| Function | Does |
|---|---|
| `list_members()` | The member directory: every other member's `id`, `full_name`, `membership_id`, and `allow_messages`. Leaves out deleted members and members with `show_in_member_list` off. |
| `get_or_create_direct_conversation(other_id)` | Returns the 1:1 chat with that member, creating it (with both members) on first use. Refuses with `messages_off` if either member has `allow_messages` off. |
| `list_conversations()` | The inbox, latest first: the other member (with their `allow_messages`), the last message, and `unread_count`, all counted after the member's `cleared_at`. A cleared chat with nothing new still shows (last message columns null); a removed chat shows again once a new message arrives. |
| `send_media_message(conv, kind, caption, storage_path, mime_type, size_bytes, width, height, duration_ms)` | Saves an image/video message and its attachment together, after the file is uploaded. Refuses if the file is missing or the path/type is wrong. |
| `mark_conversation_read(conv)` | Moves the member's read marker to now (never backwards). |
| `clear_conversation(conv)` | "Clear chat" for the member only: sets `cleared_at` and the read marker to now (and clears `removed_at`). The history is hidden from them by the messages read policy; the chat stays in their inbox. Nothing is deleted. |
| `remove_conversation(conv)` | "Remove" (delete the chat for me): like `clear_conversation` and also sets `removed_at`, so the chat leaves the inbox until a new message arrives. Nothing is deleted. |
| `delete_message(msg)` | Deletes one of the member's own messages for both people by setting `deleted_at` (soft delete: text, attachments and files are kept and can be retrieved; restore by clearing `deleted_at`). Refuses another member's message; does nothing if already deleted. |
| `edit_message(msg, new_body)` | Edits the text (or image/video caption) of one of the member's own messages and sets `edited_at`. No time limit. Text is trimmed; a text message can't be emptied (an empty caption becomes null); max 1000 characters. Refuses another member's message, a deleted message, or while either member has blocked the other or has `allow_messages` off. Unchanged text does nothing. |
| `get_my_membership()` | The member's membership: `is_member`, `platform`, `product_id`, `plan_id`, `status`, `expires_at`, `auto_renew` from their best subscription (one with access first, then the latest expiry). No row = never subscribed. |
| `delete_my_account()` | Soft-deletes the member and frees their email: sets `profiles.deleted_at`, saves the email in `profiles.deleted_email`, swaps the auth email for a placeholder (`deleted+<user id>@deleted.invalid`), bans their auth user so they can't sign in again, and ends their sessions. All their data stays (earlier chat messages remain visible to the other member). Deleted members are left out of `list_members()`. Signing up again with the same email creates a brand-new account; old data does not carry over. The team can restore the old account by clearing `profiles.deleted_at` and `auth.users.banned_until` and copying `deleted_email` back, only if no new account has taken that email. |

Block and unblock are plain insert/delete on `blocked_members` (no RPC).

Internal helpers used by the security rules: `is_conversation_member(conv)`,
`is_chat_folder_member(folder)`, `is_blocked_in_conversation(conv)`,
`is_messaging_off_in_conversation(conv)` (either member has `allow_messages` off: no sends, uploads or edits),
`conversation_cleared_at(conv)` (members read only messages after their own `cleared_at`).

Not created yet, because the client hasn't agreed the rules: QR/booklet links, ordering,
push notifications.

## Migrations

All schema changes live in `supabase/migrations/` and are applied in filename order.

| Migration | Status |
|---|---|
| `20261117100945_members_and_settings.sql` | applied (17 Nov 2026) |
| `20261117101054_harden_policies.sql` | applied (17 Nov 2026) |
| `20261118052743_user_settings_columns.sql` | applied (18 Nov 2026) |
| `20261118100359_list_members_rpc.sql` | applied (18 Nov 2026) |
| `20261119040231_member_chat.sql` | applied (19 Nov 2026) |
| `20261119040719_chat_media.sql` | applied (19 Nov 2026) |
| `20261119051814_chat_unread_counts.sql` | applied (19 Nov 2026), also removes the unsafe read-marker update policy from `member_chat` |
| `20261119090945_feedback.sql` | applied (19 Nov 2026) |
| `20261119102015_chat_blocking.sql` | applied (19 Nov 2026), adds `blocked_members` and stops sends/uploads while blocked |
| `20261119104031_delete_account.sql` | applied (19 Nov 2026), first version of `delete_my_account()` (hard delete); replaced by the next migration |
| `20261119104201_soft_delete_account.sql` | applied (19 Nov 2026), account deletion becomes a soft delete: adds `profiles.deleted_at`, bans the auth user, hides deleted members from `list_members()`, removes the chat-media delete policy |
| `20261119104944_reactivate_account.sql` | applied (19 Nov 2026), adds `reactivate_account()`: signing up again with a deleted account's email and original password reactivates it |
| `20261119111618_chat_privacy_settings.sql` | applied (19 Nov 2026), adds `profiles.show_in_member_list` / `allow_messages`; `list_members()` hides opted-out members; new chats refused when messages are off. Accidentally dropped the deleted-member filter from `list_members()` |
| `20261119111735_list_members_hide_deleted.sql` | applied (19 Nov 2026), restores the deleted-member filter in `list_members()` |
| `20261120053140_user_settings_show_clock_face.sql` | applied (20 Nov 2026), adds `user_settings.show_clock_face` (Settings → clock face on/off) |
| `20261120085547_chat_delete_message.sql` | applied (20 Nov 2026), first version of `delete_message()`: cleared the text and removed attachments/files; replaced by the next migration |
| `20261120090217_chat_keep_deleted_messages.sql` | applied (20 Nov 2026), message deletion becomes a soft delete: `delete_message()` only sets `deleted_at` and keeps everything; removes the chat-media delete policy and restores the non-empty text check |
| `20261120090533_chat_read_receipts_typing.sql` | applied (20 Nov 2026), publishes `conversation_members` to Realtime (live read receipts) and adds `realtime.messages` policies for the private `typing:<conversation_id>` broadcast channel |
| `20261123052331_deleted_account_frees_email.sql` | applied (23 Nov 2026), deleting an account frees its email (saved in new `profiles.deleted_email`, placeholder on the auth user) so the same email can sign up as a new account; frees the emails of already-deleted accounts; drops `reactivate_account()` (signed-out password check) |
| `20261123063940_teaching_progress.sql` | applied (23 Nov 2026), new `teaching_progress` table for the Brain De Fogger™ lessons (status, current lesson and step, finished lessons) with row-level security |
| `20261124082522_chat_edit_message.sql` | applied (24 Nov 2026), adds `edit_message()`: members edit the text/caption of their own messages (no time limit), setting `edited_at` |
| `20261124085835_chat_clear_and_remove.sql` | applied (24 Nov 2026), adds `conversation_members.cleared_at` / `removed_at`, `clear_conversation()` and `remove_conversation()` (both for the member only, nothing deleted); the messages read policy hides messages before the member's `cleared_at`; `list_conversations()` respects both |
| `20261124091900_list_members_has_chat.sql` | applied (24 Nov 2026), `list_members()` also returns `has_chat`, so the app shows "not accepting messages" only when a message would really be refused (including chats removed from the inbox) |
| `20261124092622_chat_messages_off_both_ways.sql` | applied (24 Nov 2026), `allow_messages` off now stops all messaging both ways in every chat (sends, uploads, edits, opening a chat), like a block; `list_conversations()` returns `member_allow_messages`; removes `has_chat` from `list_members()` again |
| `20261125100531_membership_store_subscriptions.sql` | applied (25 Nov 2026), membership linked to the member's account: `store_subscriptions` (verified App Store / Google Play subscriptions, members read their own, only the edge functions write), `store_events` (store notification log, service role only) and `get_my_membership()` |

File version numbers match the project's migration history, so `supabase migration list`
shows local and remote in step.

Add a change:

```sh
supabase login
supabase link --project-ref xgujbqsqipsuiibsmcvy
supabase migration new <name>     # write SQL in the new file
supabase db push                  # apply to the remote project
```

Never edit a migration that has already been applied. Add a new one instead.

## Edge functions (membership)

Source in `supabase/functions/` (shared code in `_shared/`). Deploy with
`supabase functions deploy <name>`; `config.toml` turns the platform JWT check off for the two
webhooks, which are called by Apple / Google rather than a signed-in member.

| Function | Called by | Does |
|---|---|---|
| `verify-purchase` | the app, with the member's session (JWT check on) | Checks a purchase with Apple / Google and links it to the member. Body `{ platform: 'apple', transactionId }` or `{ platform: 'google', productId, purchaseToken }`. Replies `{ result }`: `verified`, `other_account`, `not_found` or `wrong_product`. |
| `apple-notifications` | App Store Server Notifications V2 | Updates the subscription a notification is about. |
| `google-notifications` | Google Play Real-time developer notifications (Pub/Sub push) | Same for Google; refunds (voided purchases) mark the row `revoked`. |

The webhooks never trust the notification itself: they only use it to find which subscription
changed, then read its current state from Apple / Google's API. A forged call can't grant or
change a membership. Their URLs also carry a secret (`?secret=<STORE_WEBHOOK_SECRET>`).

### Secrets (Dashboard → Edge Functions → Secrets, or `supabase secrets set`)

| Secret | Value |
|---|---|
| `APPLE_ISSUER_ID` | App Store Connect → Users and Access → Integrations → In-App Purchase: Issuer ID |
| `APPLE_KEY_ID` | the In-App Purchase key's Key ID (same page; generate a key if there is none) |
| `APPLE_PRIVATE_KEY` | full contents of the downloaded `SubscriptionKey_<KEY_ID>.p8` |
| `APPLE_BUNDLE_ID` | the iOS app's bundle id (must match the app in App Store Connect) |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | full JSON key of a Google Cloud service account with the Google Play Android Developer API enabled, invited in Play Console → Users and permissions with *View financial data* and *Manage orders and subscriptions* |
| `GOOGLE_PACKAGE_NAME` | the Android application id (currently `com.wheelui`) |
| `STORE_WEBHOOK_SECRET` | a long random string (e.g. `openssl rand -hex 32`), also put in both webhook URLs |

`SUPABASE_URL` and `SUPABASE_SERVICE_ROLE_KEY` are provided automatically.

### Store setup

- **Products**: create the auto-renewable subscriptions `com.wheelwise.membership.annual` and
  `com.wheelwise.membership.monthly` in App Store Connect (one subscription group) and Google Play
  Console (each with one base plan). The ids must match `_shared/products.ts` and the app's
  `src/constants/membership.ts`.
- **Apple notifications**: App Store Connect → the app → App Information → App Store Server
  Notifications → Version 2, production and sandbox URL:
  `https://xgujbqsqipsuiibsmcvy.supabase.co/functions/v1/apple-notifications?secret=<STORE_WEBHOOK_SECRET>`
- **Google notifications**: create a Pub/Sub topic, grant
  `google-play-developer-notifications@system.gserviceaccount.com` *Pub/Sub Publisher* on it, add a
  **push** subscription to
  `https://xgujbqsqipsuiibsmcvy.supabase.co/functions/v1/google-notifications?secret=<STORE_WEBHOOK_SECRET>`,
  then Play Console → Monetization setup → Real-time developer notifications → that topic
  (use "Send test notification"; it shows in `store_events` as `TEST`).
- **Testing**: Apple sandbox / TestFlight purchases and Google licence-tester purchases work
  against the same functions; they are saved with `environment = 'sandbox'`.

## Functions, triggers and views (reference copies)

`database/` holds a readable copy of every function and trigger as it exists in the live
project, so they can be reviewed without digging through migrations:

- `database/functions/<name>.sql`: one file per function in the `public` schema. Each has a
  header (what it does, where the app uses it, which migration created it, who may call it),
  the exact live definition, and its grants.
- `database/triggers.sql`: every trigger and which function it runs.
- Views: there are none yet.

These are **reference only**. The migrations are the source of truth: never apply these files,
and change a function by adding a new migration (then update its file here). `public.rls_auto_enable()`
and the `ensure_rls` event trigger come from Supabase's project setup, not from our migrations.

Refresh check: each file's definition matches `pg_get_functiondef()` / `pg_get_triggerdef()`
on the live database (last checked 19 Nov 2026; `delete_my_account` re-checked 23 Nov 2026;
`get_my_membership` and `store_subscriptions_updated_at` added 25 Nov 2026).

## Claude Code

`.mcp.json` connects Claude Code to this project through the Supabase MCP server. Run
`claude /mcp`, choose **supabase**, then **Authenticate**.
