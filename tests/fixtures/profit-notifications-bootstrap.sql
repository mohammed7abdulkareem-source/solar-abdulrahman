-- The historical local fixture predates notifications; production already has these.
create table public.solar_notifications(id uuid primary key default gen_random_uuid(),user_id uuid not null references public.profiles(id),job_id bigint references public.transactions(id),transfer_id uuid,event text not null check(event in('assigned','completed','test')),title text not null,body text not null,created_at timestamptz not null default now(),read_at timestamptz);
alter table public.solar_notifications enable row level security;
revoke all on public.solar_notifications from public,anon,authenticated;
grant select,update(read_at) on public.solar_notifications to authenticated;
create policy notification_own_read on public.solar_notifications for select to authenticated using(user_id=auth.uid());
