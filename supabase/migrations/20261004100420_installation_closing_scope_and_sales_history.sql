-- Scoped installation approval. No changes to cashbox/table RLS.
create or replace function solar_private.sales_history(
 search_text text default '', sale_kind text default '', date_from date default null,
 date_to date default null, job_status text default '', page_offset integer default 0
) returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null or p.user_type='installer' then raise exception 'Not permitted' using errcode='42501'; end if;
 with permitted as (
 select t.* from public.transactions t where t.kind in ('sale','system')
 and (p.is_admin or
  (t.created_by=p.id and (p.permissions->>'salesHistory'='true'
   or (t.kind='sale' and p.permissions->>'sale'='true')
   or (t.kind='system' and (p.permissions->>'system'='true' or p.permissions->>'installations'='true'))))
  or (t.kind='system' and p.permissions->>'installationsAll'='true'))
 and (coalesce(sale_kind,'')='' or t.kind=sale_kind)
 and (coalesce(search_text,'')='' or strpos(lower(coalesce(t.party_name,'')||' '||t.id::text),lower(search_text))>0)
 and (date_from is null or t.created_at >= (date_from::timestamp at time zone 'Asia/Baghdad'))
 and (date_to is null or t.created_at < ((date_to+1)::timestamp at time zone 'Asia/Baghdad'))
 and (coalesce(job_status,'')='' or (t.kind='system' and t.installation_status=job_status))
 ), page_rows as (select * from permitted order by created_at desc,id desc limit 30 offset greatest(coalesce(page_offset,0),0))
 select jsonb_build_object('count',(select count(*) from permitted),'rows',coalesce((
 select jsonb_agg(to_jsonb(t)||jsonb_build_object(
 'creatorName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.created_by),
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'items',coalesce((select jsonb_agg(to_jsonb(i) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) order by t.created_at desc,t.id desc) from page_rows t),'[]'::jsonb)) into result;
 return result;
end $$;
revoke all on function solar_private.sales_history(text,text,date,date,text,integer) from public,anon;
grant execute on function solar_private.sales_history(text,text,date,date,text,integer) to authenticated;
create or replace function public.solar_sales_history(
 search_text text default '', sale_kind text default '', date_from date default null,
 date_to date default null, job_status text default '', page_offset integer default 0
) returns jsonb language sql security invoker set search_path='' as $$
 select solar_private.sales_history(search_text,sale_kind,date_from,date_to,job_status,page_offset)
$$;
revoke all on function public.solar_sales_history(text,text,date,date,text,integer) from public,anon;
grant execute on function public.solar_sales_history(text,text,date,date,text,integer) to authenticated;

create or replace function solar_private.can_close_installation(owner_id uuid) returns boolean
language sql stable security definer set search_path='' as $$
 select exists(select 1 from public.profiles p where p.id=auth.uid() and p.active
 and p.user_type<>'installer' and (p.is_admin or p.permissions->>'installationsAll'='true'
 or (p.permissions->>'installations'='true' and owner_id=p.id)))
$$;
revoke all on function solar_private.can_close_installation(uuid) from public,anon;
grant execute on function solar_private.can_close_installation(uuid) to authenticated;

CREATE OR REPLACE FUNCTION solar_private.installation_action(job_id bigint, expected_revision bigint, action text, payload jsonb DEFAULT '{}'::jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; j public.transactions; amount numeric; e jsonb; report jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 select * into j from public.transactions where id=job_id and kind='system' for update;
 if j.id is null then raise exception 'Job unavailable' using errcode='42501'; end if;
 if p.user_type='installer' then
  if j.installer_id is distinct from p.id or action not in ('start','complete') then raise exception 'Not permitted' using errcode='42501'; end if;
 else
  if not (solar_private.can_close_installation(j.created_by)) or action not in ('close','reopen') then raise exception 'Not permitted' using errcode='42501'; end if;
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
  update public.transactions set installation_status='closed',installation_closed_at=now(),installation_expenses=amount,installation_expense_notes=payload->>'notes',profit=coalesce(total,0)-coalesce(cost,0)-coalesce(expenses,0)-amount,installation_revision=installation_revision+1 where id=j.id;
 elsif action='reopen' then
  if j.installation_status<>'closed' then raise exception 'Only closed files can reopen'; end if;
  update public.transactions set installation_status='completed',installation_closed_at=null,installation_revision=installation_revision+1 where id=j.id;
 else raise exception 'Invalid action'; end if;
end $function$
;
CREATE OR REPLACE FUNCTION solar_private.installation_jobs()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active=true;
 if p.id is null then raise exception 'Active login required' using errcode='42501'; end if;
 if p.user_type<>'installer' and not p.is_admin and not (coalesce(p.permissions->>'installations','false')='true' or coalesce(p.permissions->>'installationsAll','false')='true' or coalesce(p.permissions->>'system','false')='true') then return '[]'::jsonb; end if;
 select coalesce(jsonb_agg(jsonb_build_object(
 'id',t.id,'kind','system','party',t.party_name,'installerId',t.installer_id,
 'installerName',(select coalesce(x.display_name,x.username) from public.profiles x where x.id=t.installer_id),
 'installDate',t.install_date,'installTime',t.install_time,'customerPhone',t.customer_phone,'customerAddress',t.customer_address,
 'installationStatus',t.installation_status,'installationStartedAt',t.installation_started_at,
 'installationCompletedAt',t.installation_completed_at,'installationClosedAt',t.installation_closed_at,
 'installationRevision',t.installation_revision,'installationReport',t.installation_report,
 'canManage',solar_private.can_close_installation(t.created_by),
 'items',coalesce((select jsonb_agg(jsonb_build_object('id',i.id,'name',i.product_name,'brand',i.brand_name,'qty',i.qty) order by i.id) from public.transaction_items i where i.transaction_id=t.id),'[]'::jsonb)
 ) || case when solar_private.can_close_installation(t.created_by) then
 jsonb_build_object('cost',t.cost,'expenses',t.expenses,'total',t.total,'installationExpenses',t.installation_expenses,'installationExpenseNotes',t.installation_expense_notes)
 else '{}'::jsonb end order by t.install_date nulls last,t.install_time nulls last,t.id),'[]'::jsonb) into result
 from public.transactions t where t.kind='system' and t.installation_status<>'none' and
 (case when p.user_type='installer' then t.installer_id=p.id else p.is_admin or coalesce(p.permissions->>'installationsAll','false')='true' or t.created_by=p.id end);
 return result;
end $function$
;
