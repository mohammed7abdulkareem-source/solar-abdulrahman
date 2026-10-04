-- Adding this feature never executes a reset. Destruction requires a fresh
-- password check in solar-reset-data and a reviewed, unchanged backup token.
create table if not exists solar_private.reset_backups(id uuid primary key default gen_random_uuid(),created_at timestamptz not null default now(),data jsonb not null);
create table if not exists solar_private.reset_record_ids(table_name text not null,record_id bigint not null,primary key(table_name,record_id));
alter table solar_private.reset_backups enable row level security;
alter table solar_private.reset_record_ids enable row level security;
revoke all on solar_private.reset_backups,solar_private.reset_record_ids from public,anon,authenticated;
create table solar_private.reset_requests (
 id uuid primary key default gen_random_uuid(),
 actor_id uuid not null references public.profiles(id),
 backup_id uuid not null references solar_private.reset_backups(id),
 fingerprint text not null,
 created_at timestamptz not null default now(),
 expires_at timestamptz not null default now()+interval '15 minutes',
 consumed_at timestamptz
);
alter table solar_private.reset_requests enable row level security;
revoke all on solar_private.reset_requests from public,anon,authenticated;

create or replace function solar_private.reset_snapshot() returns jsonb
language plpgsql security definer set search_path='' as $$
declare name text; rows jsonb; result jsonb='{}';begin
 -- This same allowlist governs backup, fingerprinting and the explicit wipe below.
 foreach name in array array['public.brands','public.customers','public.suppliers','public.products',
 'public.transactions','public.transaction_items','public.cash_ledger','public.solar_cash_entries',
 'public.solar_notifications','public.solar_quotes','public.solar_price_estimates','public.solar_estimate_specs',
 'solar_private.cash_transfers','solar_private.supplier_payment_requests','solar_private.receipt_counters'] loop
  execute format('select coalesce(jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text),''[]''::jsonb) from %s t',name) into rows;
  result=result||jsonb_build_object(name,rows);
 end loop;
 return result;
end $$;
revoke all on function solar_private.reset_snapshot() from public,anon,authenticated;

create or replace function solar_private.lock_reset_tables() returns void
language plpgsql security definer set search_path='' as $$begin
 perform pg_advisory_xact_lock(7311,1);
 lock table public.brands,public.customers,public.suppliers,public.products,
 public.transactions,public.transaction_items,public.cash_ledger,public.solar_cash_entries,
 public.solar_notifications,public.solar_quotes,public.solar_price_estimates,public.solar_estimate_specs,
 solar_private.cash_transfers,solar_private.supplier_payment_requests,solar_private.receipt_counters
 in share row exclusive mode;
end $$;
revoke all on function solar_private.lock_reset_tables() from public,anon,authenticated;

create or replace function public.solar_prepare_reset() returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' set statement_timeout='30s' as $$
declare actor uuid=auth.uid(); snapshot jsonb; backup uuid; request uuid; counts jsonb;begin
 if not exists(select 1 from public.profiles where id=actor and active and is_admin and user_type not in ('installer','warehouse')) then
  raise exception 'للأدمن فقط' using errcode='42501';end if;
 perform solar_private.lock_reset_tables();
 snapshot=solar_private.reset_snapshot();
 insert into solar_private.reset_backups(data) values(jsonb_build_object('format','solar-reset-v1','createdBy',actor,'tables',snapshot)) returning id into backup;
 insert into solar_private.reset_requests(actor_id,backup_id,fingerprint) values(actor,backup,md5(snapshot::text)) returning id into request;
 select jsonb_object_agg(key,jsonb_array_length(value)) into counts from jsonb_each(snapshot);
 return jsonb_build_object('requestId',request,'backupId',backup,'counts',counts,'expiresAt',now()+interval '15 minutes');
end $$;
revoke all on function public.solar_prepare_reset() from public,anon;
grant execute on function public.solar_prepare_reset() to authenticated;

create or replace function public.solar_reset_backup(request_id uuid) returns jsonb
language plpgsql security definer set search_path='' as $$
declare result jsonb;begin
 if not exists(select 1 from public.profiles where id=auth.uid() and active and is_admin and user_type not in ('installer','warehouse')) then raise exception 'للأدمن فقط' using errcode='42501';end if;
 select jsonb_build_object('backupId',b.id,'createdAt',b.created_at,'data',b.data) into result
 from solar_private.reset_requests r join solar_private.reset_backups b on b.id=r.backup_id
 where r.id=request_id and r.actor_id=auth.uid();
 if result is null then raise exception 'النسخة الاحتياطية غير متاحة';end if;
 return result;
end $$;
revoke all on function public.solar_reset_backup(uuid) from public,anon;
grant execute on function public.solar_reset_backup(uuid) to authenticated;

create or replace function public.solar_execute_reset(actor_id uuid,request_id uuid,confirmation text) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' set statement_timeout='30s' as $$
declare request solar_private.reset_requests; snapshot jsonb; name text;begin
 if confirmation is distinct from 'تصفير بيانات عبدالرحمن سولار' then raise exception 'اكتب عبارة التأكيد كاملة';end if;
 if not exists(select 1 from public.profiles p where p.id=actor_id and p.active and p.is_admin and p.user_type not in ('installer','warehouse')) then raise exception 'للأدمن فقط' using errcode='42501';end if;
 select * into request from solar_private.reset_requests r where r.id=request_id and r.actor_id=solar_execute_reset.actor_id for update;
 if request.id is null or request.consumed_at is not null or request.expires_at<now() then raise exception 'انتهت صلاحية الطلب؛ جهّز معاينة جديدة';end if;
 perform solar_private.lock_reset_tables();
 snapshot=solar_private.reset_snapshot();
 if md5(snapshot::text)<>request.fingerprint then raise exception 'تغيرت البيانات بعد المعاينة؛ جهّز نسخة احتياطية ومعاينة جديدة قبل التصفير' using errcode='40001';end if;
 -- Prevent stale devices from resurrecting deleted operational/master rows.
 foreach name in array array['brands','customers','suppliers','products','transactions'] loop
  execute format('insert into solar_private.reset_record_ids(table_name,record_id) select %L,id from public.%I on conflict do nothing',name,name);
 end loop;
 delete from public.cash_ledger;
 delete from public.solar_cash_entries;
 delete from public.solar_notifications;
 delete from solar_private.cash_transfers;
 delete from solar_private.supplier_payment_requests;
 delete from public.transactions; -- cascades its invoice lines, without stock rewrite.
 delete from public.transaction_items;
 delete from public.solar_quotes;
 delete from public.solar_price_estimates;
 delete from public.solar_estimate_specs;
 delete from public.products;
 delete from public.brands;
 delete from public.customers;
 delete from public.suppliers;
 delete from solar_private.receipt_counters;
 update solar_private.reset_requests set consumed_at=now() where id=request.id;
 -- Users, permissions, notification devices, audit records and ALL backups survive.
 return jsonb_build_object('ok',true,'backupId',request.backup_id,'resetAt',now());
end $$;
revoke all on function public.solar_execute_reset(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.solar_execute_reset(uuid,uuid,text) to service_role;
