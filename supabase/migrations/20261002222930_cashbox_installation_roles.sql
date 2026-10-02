create schema if not exists solar_private;
revoke all on schema solar_private from public,anon;
grant usage on schema solar_private to authenticated;
create or replace function solar_private.role_name() returns text
language sql stable security definer set search_path='' as $$
 select case when p.user_type='installer' then 'installer' when p.is_admin then 'admin' else 'staff' end
 from public.profiles p where p.id=auth.uid() and p.active=true
$$;
revoke all on function solar_private.role_name() from public,anon;
grant execute on function solar_private.role_name() to authenticated;

-- Restrictive policies also constrain the pre-existing shared-data policies.
do $$ declare t text; begin
 foreach t in array array['brands','products','customers','suppliers','transactions','transaction_items','cash_ledger'] loop
 execute format('create policy solar_staff_only on public.%I as restrictive for all to authenticated using ((select solar_private.role_name()) in (''admin'',''staff'')) with check ((select solar_private.role_name()) in (''admin'',''staff''))',t);
 end loop;
end $$;
create policy solar_cash_owner on public.transactions as restrictive for all to authenticated
using ((select solar_private.role_name())='admin' or coalesce(cashbox_user_id,created_by)=(select auth.uid()))
with check ((select solar_private.role_name())='admin' or (coalesce(cashbox_user_id,created_by)=(select auth.uid()) and created_by=(select auth.uid())));
create policy solar_item_owner on public.transaction_items as restrictive for all to authenticated
using (exists(select 1 from public.transactions t where t.id=transaction_id))
with check (exists(select 1 from public.transactions t where t.id=transaction_id));
create policy solar_ledger_owner on public.cash_ledger as restrictive for all to authenticated
using (exists(select 1 from public.transactions t where t.id=transaction_id))
with check (exists(select 1 from public.transactions t where t.id=transaction_id));

alter table public.transactions add column if not exists installation_started_at timestamptz;
alter table public.transactions add column if not exists installation_report jsonb not null default '{}'::jsonb;
alter table public.transactions add column if not exists installation_revision bigint not null default 0;

create or replace function solar_private.installation_jobs() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 if p.user_type<>'installer' and not p.is_admin and not (coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'system','false')='true') then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',t.id,'kind','system','party',t.party_name,'installerId',t.installer_id,
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'installDate',t.install_date,'installTime',t.install_time,'customerPhone',t.customer_phone,'customerAddress',t.customer_address,
 'installationStatus',t.installation_status,'installationStartedAt',t.installation_started_at,
 'installationCompletedAt',t.installation_completed_at,'installationClosedAt',t.installation_closed_at,
 'installationRevision',t.installation_revision,'installationReport',t.installation_report,
 'canManage',p.user_type<>'installer' and (p.is_admin or coalesce(p.permissions->>'installations','false')='true'),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'brand',i.brand_name,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) || case when p.user_type<>'installer' and (p.is_admin or coalesce(p.permissions->>'installations','false')='true') then
 jsonb_build_object('cost',t.cost,'expenses',t.expenses,'total',t.total,'installationExpenses',t.installation_expenses,'installationExpenseNotes',t.installation_expense_notes)
 else '{}'::jsonb end order by t.install_date nulls last,t.install_time nulls last,t.id),'[]'::jsonb) into result
 from public.transactions t where t.kind='system' and t.installation_status<>'none' and
 (case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id end);
 return result;
end $$;
revoke all on function solar_private.installation_jobs() from public,anon;
grant execute on function solar_private.installation_jobs() to authenticated;
create or replace function public.solar_installation_jobs() returns jsonb language sql security invoker set search_path='' as $$ select solar_private.installation_jobs() $$;
revoke all on function public.solar_installation_jobs() from public,anon;
grant execute on function public.solar_installation_jobs() to authenticated;

create or replace function solar_private.installation_action(job_id bigint,expected_revision bigint,action text,payload jsonb default '{}'::jsonb) returns void
language plpgsql security definer set search_path='' as $$
declare p public.profiles; j public.transactions; amount numeric; e jsonb; report jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 select * into j from public.transactions where id=job_id and kind='system' for update;
 if j.id is null then raise exception 'Job unavailable' using errcode='42501'; end if;
 if p.user_type='installer' then
  if j.installer_id is distinct from p.id or action not in ('start','complete') then raise exception 'Not permitted' using errcode='42501'; end if;
 else
  if not (p.is_admin or (coalesce(p.permissions->>'installations','false')='true' and coalesce(j.cashbox_user_id,j.created_by)=p.id)) or action not in ('close','reopen') then raise exception 'Not permitted' using errcode='42501'; end if;
 end if;
 if expected_revision is distinct from j.installation_revision then raise exception 'Job changed; refresh and retry' using errcode='40001'; end if;
 if action='start' then
  if j.installation_status<>'pending' then raise exception 'Invalid stage'; end if;
  update public.transactions set installation_status='in_progress',installation_started_at=now(),installation_revision=installation_revision+1 where id=j.id;
 elsif action='complete' then
  if j.installation_status<>'in_progress' then raise exception 'Start the installation first'; end if;
  if jsonb_typeof(payload) is distinct from 'object' or length(trim(coalesce(payload->>'notes','')))=0 or length(payload->>'notes')>4000 then raise exception 'Completion report required'; end if;
  if payload->'checks'->>'materials' is distinct from 'true' or payload->'checks'->>'tested' is distinct from 'true' or payload->'checks'->>'handover' is distinct from 'true' then raise exception 'Complete the checklist'; end if;
  if jsonb_typeof(payload->'expenses') is distinct from 'array' then raise exception 'Invalid expenses'; end if;
  if jsonb_array_length(payload->'expenses')>50 then raise exception 'Too many expense lines'; end if;
  amount:=0;
  for e in select value from jsonb_array_elements(payload->'expenses') loop
   if jsonb_typeof(e->'amount') is distinct from 'number' or (e->>'amount')::numeric<=0 or (e->>'amount')::numeric>1000000000 or length(trim(coalesce(e->>'description','')))=0 or length(e->>'description')>500 then raise exception 'Invalid expense line'; end if;
   amount:=amount+(e->>'amount')::numeric;
  end loop;
  report:=jsonb_build_object('notes',trim(payload->>'notes'),'checks',payload->'checks','expenses',payload->'expenses','expenseTotal',amount,'submittedAt',now(),'submittedBy',p.id);
  update public.transactions set installation_status='completed',installation_completed_at=now(),installation_report=report,installation_revision=installation_revision+1 where id=j.id;
 elsif action='close' then
  if j.installation_status<>'completed' then raise exception 'Engineer report required before closing'; end if;
  if jsonb_typeof(payload->'amount') is distinct from 'number' then raise exception 'Invalid approved expenses'; end if;
  amount:=(payload->>'amount')::numeric;
  if amount<0 or amount>1000000000 then raise exception 'Invalid approved expenses'; end if;
  if length(coalesce(payload->>'notes',''))>4000 then raise exception 'Notes too long'; end if;
  if amount<>coalesce((j.installation_report->>'expenseTotal')::numeric,0) and length(trim(coalesce(payload->>'notes','')))=0 then raise exception 'Explain expense adjustment'; end if;
  update public.transactions set installation_status='closed',installation_closed_at=now(),installation_expenses=amount,installation_expense_notes=payload->>'notes',profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-amount,installation_revision=installation_revision+1 where id=j.id;
 elsif action='reopen' then
  if j.installation_status<>'closed' then raise exception 'Only closed files can reopen'; end if;
  update public.transactions set installation_status='completed',installation_closed_at=null,installation_revision=installation_revision+1 where id=j.id;
 else raise exception 'Invalid action'; end if;
end $$;
revoke all on function solar_private.installation_action(bigint,bigint,text,jsonb) from public,anon;
grant execute on function solar_private.installation_action(bigint,bigint,text,jsonb) to authenticated;
create or replace function public.solar_installation_action(job_id bigint,expected_revision bigint,action text,payload jsonb default '{}'::jsonb) returns void
language sql security invoker set search_path='' as $$ select solar_private.installation_action(job_id,expected_revision,action,payload) $$;
revoke all on function public.solar_installation_action(bigint,bigint,text,jsonb) from public,anon;
grant execute on function public.solar_installation_action(bigint,bigint,text,jsonb) to authenticated;

-- Generic writes cannot change the workflow; guarded private RPCs own transitions.
create or replace function solar_private.guard_installation() returns trigger language plpgsql set search_path='' as $$
begin
 if current_user in ('authenticated','anon') then
  if tg_op='INSERT' and new.kind='system' then
   if new.installation_status is distinct from 'pending' or new.installation_revision<>0 or new.installation_report<>'{}'::jsonb or coalesce(new.installation_expenses,0)<>0 or new.installation_completed_at is not null or new.installation_closed_at is not null or new.installation_started_at is not null then raise exception 'Invalid initial installation state'; end if;
  elsif tg_op='UPDATE' and (old.kind='system' or new.kind='system') then
   if (new.kind,new.installation_status,new.installation_revision,new.installation_report,new.installation_expenses,new.installation_expense_notes,new.installation_started_at,new.installation_completed_at,new.installation_closed_at) is distinct from (old.kind,old.installation_status,old.installation_revision,old.installation_report,old.installation_expenses,old.installation_expense_notes,old.installation_started_at,old.installation_completed_at,old.installation_closed_at) then raise exception 'Use installation workflow'; end if;
  end if;
 end if;
 return new;
end $$;
revoke all on function solar_private.guard_installation() from public,anon,authenticated;
create trigger solar_installation_guard before insert or update on public.transactions for each row execute function solar_private.guard_installation();

create or replace function solar_private.staff_directory() returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 if p.user_type='installer' then return '[]'::jsonb; end if;
 return (select coalesce(jsonb_agg(jsonb_build_object('id',x.id,'display_name',x.display_name,'username',x.username,'user_type',x.user_type,'active',x.active)),'[]'::jsonb) from public.profiles x where x.active and (p.is_admin or (x.user_type='installer' and (p.permissions->>'system'='true' or p.permissions->>'installations'='true'))));
end $$;
revoke all on function solar_private.staff_directory() from public,anon;
grant execute on function solar_private.staff_directory() to authenticated;
create or replace function public.solar_staff_directory() returns jsonb language sql security invoker set search_path='' as $$select solar_private.staff_directory()$$;
revoke all on function public.solar_staff_directory() from public,anon;
grant execute on function public.solar_staff_directory() to authenticated;
