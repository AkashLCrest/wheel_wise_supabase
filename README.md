# wheel_wise_supabase

Supabase backend (database, auth, storage, realtime) for the WHEEL WISE™ app. The React Native app lives in
a separate repo (`WheelUI`) and talks to this project through `src/lib/supabase.ts`.

- Supabase project ref: `xgujbqsqipsuiibsmcvy`
- URL: `https://xgujbqsqipsuiibsmcvy.supabase.co`

## Tables

| Table | Holds |
|---|---|
| `profiles` | One row per member: `full_name`, `language` (chosen at sign-up, editable in Profile), `membership_id` (`WW100001`, …). Created automatically on sign-up by the `on_auth_user_created` trigger. Members can update only `full_name` and `language`. |
| `user_settings` | One row per member, one column per setting: `wheel_type` (`european` / `americanDoubleZero` / `tripleZero`), `display_style` (`standard` / `highContrast`), `last_number` (last selected pocket: `0`–`36`, `00`, `000`, or null), `updated_at`. The database rejects invalid values. Gives a member the same settings on every device. |

Row-level security is on for both tables: each member can only read and write their own row.

### Member chat (B20)

| Table | Holds |
|---|---|
| `conversations` | One row per chat. `kind` is `direct` (1:1) or `group` (reserved). `direct_key` (the two member ids, sorted) makes each pair share one chat. `last_message_at` orders the inbox (kept up to date by the `messages_touch_conversation` trigger). |
| `conversation_members` | Who is in each chat, plus `last_read_at` (that member's read marker, used for unread counts). Members cannot write this table directly. |
| `messages` | `kind` is `text`, `image` or `video`. `body` is the text, or an optional caption for media (max 1000 chars; text messages cannot be empty). `edited_at` / `deleted_at` are reserved for editing and moderation. Published to **Realtime** so new messages are pushed live. |
| `message_attachments` | Files for image/video messages (several per message allowed): `storage_path`, `mime_type`, `size_bytes`, `width`, `height`, `duration_ms`, `thumbnail_path` (not used yet). |

Storage: private bucket **`chat-media`** (50 MB per file; images: jpeg, png, heic, heif, webp, gif;
videos: mp4, quicktime, 3gpp, webm). Files live at `<conversation_id>/<sender_id>/<file>`.
Only members of that conversation can read them, and a member can upload only into their own
folder. The app shows files through short-lived signed URLs.

Who can see what: only members of a conversation can read its messages, attachments and files.
Messages can only be sent as yourself. The rules for privacy controls, blocking/reporting and
moderation are still to be agreed with the client.

### Functions the app calls (RPC)

All require a signed-in member and act only on that member's own data.

| Function | Does |
|---|---|
| `list_members()` | Every other member's `id`, `full_name`, `membership_id` (the member directory). |
| `get_or_create_direct_conversation(other_id)` | Returns the 1:1 chat with that member, creating it (with both members) on first use. |
| `list_conversations()` | The inbox, latest first: the other member, the last message, and `unread_count`. |
| `send_media_message(conv, kind, caption, storage_path, mime_type, size_bytes, width, height, duration_ms)` | Saves an image/video message and its attachment together, after the file is uploaded. Refuses if the file is missing or the path/type is wrong. |
| `mark_conversation_read(conv)` | Moves the member's read marker to now (never backwards). |

Internal helpers used by the security rules: `is_conversation_member(conv)`,
`is_chat_folder_member(folder)`.

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
