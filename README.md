# wheel_wise_supabase

Supabase backend (database, auth, storage, realtime) for the WHEEL WISE™ app. The React Native app lives in
a separate repo (`WheelUI`) and talks to this project through `src/lib/supabase.ts`.

- Supabase project ref: `xgujbqsqipsuiibsmcvy`
- URL: `https://xgujbqsqipsuiibsmcvy.supabase.co`

## Tables

| Table | Holds |
|---|---|
| `profiles` | One row per member: `full_name`, `language` (chosen at sign-up, editable in Profile), `membership_id` (`WW100001`, …), `deleted_at` (set when the member deletes their account; soft delete), and the chat privacy settings `show_in_member_list` (off = left out of the Members list) and `allow_messages` (off = nobody can start a new chat with them; chats that already have messages carry on), both on by default. Created automatically on sign-up by the `on_auth_user_created` trigger. Members can update only `full_name`, `language`, `show_in_member_list` and `allow_messages`. |
| `user_settings` | One row per member, one column per setting: `wheel_type` (`european` / `americanDoubleZero` / `tripleZero`), `display_style` (`standard` / `highContrast`), `last_number` (last selected pocket: `0`–`36`, `00`, `000`, or null), `updated_at`. The database rejects invalid values. Gives a member the same settings on every device. |

Row-level security is on for both tables: each member can only read and write their own row.

### Member chat (B20)

| Table | Holds |
|---|---|
| `conversations` | One row per chat. `kind` is `direct` (1:1) or `group` (reserved). `direct_key` (the two member ids, sorted) makes each pair share one chat. `last_message_at` orders the inbox (kept up to date by the `messages_touch_conversation` trigger). |
| `conversation_members` | Who is in each chat, plus `last_read_at` (that member's read marker, used for unread counts). Members cannot write this table directly. |
| `messages` | `kind` is `text`, `image` or `video`. `body` is the text, or an optional caption for media (max 1000 chars; text messages cannot be empty). `edited_at` / `deleted_at` are reserved for editing and moderation. Published to **Realtime** so new messages are pushed live. |
| `blocked_members` | Who each member has blocked (`blocker_id`, `blocked_id`, `created_at`). A member adds and removes only their own rows (block / unblock) and sees only their own blocks, never who blocked them. While a block exists, in either direction, neither member can send messages or upload files in their chat. Earlier messages stay visible. |
| `message_attachments` | Files for image/video messages (several per message allowed): `storage_path`, `mime_type`, `size_bytes`, `width`, `height`, `duration_ms`, `thumbnail_path` (not used yet). |

Storage: private bucket **`chat-media`** (50 MB per file; images: jpeg, png, heic, heif, webp, gif;
videos: mp4, quicktime, 3gpp, webm). Files live at `<conversation_id>/<sender_id>/<file>`.
Only members of that conversation can read them, and a member can upload only into their own
folder. The app shows files through short-lived signed URLs.

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

### Functions the app calls (RPC)

All require a signed-in member and act only on that member's own data, except `reactivate_account`, which is called signed out.

| Function | Does |
|---|---|
| `list_members()` | The member directory: every other member's `id`, `full_name`, `membership_id` and `allow_messages`. Leaves out deleted members and members with `show_in_member_list` off. |
| `get_or_create_direct_conversation(other_id)` | Returns the 1:1 chat with that member, creating it (with both members) on first use. Refuses with `messages_off` if that member has `allow_messages` off and the pair has no messages yet. |
| `list_conversations()` | The inbox, latest first: the other member, the last message, and `unread_count`. |
| `send_media_message(conv, kind, caption, storage_path, mime_type, size_bytes, width, height, duration_ms)` | Saves an image/video message and its attachment together, after the file is uploaded. Refuses if the file is missing or the path/type is wrong. |
| `mark_conversation_read(conv)` | Moves the member's read marker to now (never backwards). |
| `delete_my_account()` | Soft-deletes the member: sets `profiles.deleted_at`, bans their auth user so they can't sign in again, and ends their sessions. All their data stays (earlier chat messages remain visible to the other member). Deleted members are left out of `list_members()`. Signing up again with the same email and the original password reactivates it (`reactivate_account`); the team can also restore it by clearing `profiles.deleted_at` and `auth.users.banned_until`. |
| `reactivate_account(email, password)` | Callable signed out. The app calls it before sign-up: if the email belongs to a deleted account and the password matches, it clears `deleted_at` and the ban, and the app signs the member in with all their old data. Returns false otherwise, without saying why. |

Block and unblock are plain insert/delete on `blocked_members` (no RPC).

Internal helpers used by the security rules: `is_conversation_member(conv)`,
`is_chat_folder_member(folder)`, `is_blocked_in_conversation(conv)`.

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
on the live database (last checked 19 Nov 2026).

## Claude Code

`.mcp.json` connects Claude Code to this project through the Supabase MCP server. Run
`claude /mcp`, choose **supabase**, then **Authenticate**.
