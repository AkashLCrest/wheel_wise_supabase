-- QR groundwork (B22). Each QR code printed in the WHEEL WISE booklet carries a
-- short code. This table says where each code goes, so the team can repoint a
-- printed code later (dashboard → qr_links → target) without an app release
-- or a reprint. Placeholder only: no live destination yet.
create table public.qr_links (
  code text primary key check (code ~ '^[a-z0-9_-]{1,64}$'),
  target text not null check (char_length(target) between 1 and 2000),
  note text,
  updated_at timestamptz not null default now()
);

comment on table public.qr_links is
  'Where each booklet QR code goes. Repoint a code by editing target; the printed QR never changes.';
comment on column public.qr_links.code is 'Short code in the QR address (lowercase letters, digits, - and _).';
comment on column public.qr_links.target is
  'An app screen name (e.g. Wheel, BrainDeFogger, MembershipPlans) or a web address starting with https://.';
comment on column public.qr_links.note is 'What the code is for (team notes).';

alter table public.qr_links enable row level security;

-- Anyone can look a code up (the codes are printed in the booklet). Only the
-- team (dashboard / service role) can add or change them.
create policy "Anyone can read QR links" on public.qr_links
  for select to anon, authenticated
  using (true);

revoke all on public.qr_links from anon, authenticated;
grant select on public.qr_links to anon, authenticated;

insert into public.qr_links (code, target, note) values
  ('booklet', 'BrainDeFogger', 'Placeholder: the booklet''s main QR. Destination to be agreed with Sam.');
