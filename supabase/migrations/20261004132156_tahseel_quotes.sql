-- Quotations are standalone snapshots: no inventory, cash or transaction triggers.
create table public.solar_quotes (
  id uuid primary key,
  user_id uuid not null references public.profiles(id) on delete cascade,
  payload jsonb not null check (jsonb_typeof(payload) = 'object' and octet_length(payload::text) <= 65536),
  revision integer not null default 1 check (revision > 0),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index solar_quotes_owner_updated on public.solar_quotes(user_id, updated_at desc, id);
alter table public.solar_quotes enable row level security;
revoke all on public.solar_quotes from public, anon, authenticated;
grant select, insert, update, delete on public.solar_quotes to authenticated;
grant all on public.solar_quotes to service_role;

-- The existing profiles SELECT policy lets users read only their own profile.
-- A false explicit quotation permission overrides the legacy system permission.
create policy quote_access on public.solar_quotes as restrictive for all to authenticated
using (exists (
 select 1 from public.profiles p where p.id = (select auth.uid()) and p.active
 and coalesce(p.user_type,'') not in ('installer','warehouse')
 and (p.is_admin or case when p.permissions ? 'tahseel'
      then p.permissions->'tahseel' = 'true'::jsonb
      else p.permissions->'system' = 'true'::jsonb end)
))
with check (exists (
 select 1 from public.profiles p where p.id = (select auth.uid()) and p.active
 and coalesce(p.user_type,'') not in ('installer','warehouse')
 and (p.is_admin or case when p.permissions ? 'tahseel'
      then p.permissions->'tahseel' = 'true'::jsonb
      else p.permissions->'system' = 'true'::jsonb end)
));
create policy quote_owner_select on public.solar_quotes for select to authenticated
using (user_id = (select auth.uid()));
create policy quote_owner_insert on public.solar_quotes for insert to authenticated
with check (user_id = (select auth.uid()));
create policy quote_owner_update on public.solar_quotes for update to authenticated
using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy quote_owner_delete on public.solar_quotes for delete to authenticated
using (user_id = (select auth.uid()));
