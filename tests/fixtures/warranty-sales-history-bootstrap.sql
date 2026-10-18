-- Isolated fixture: customer-copy archive RPC; production has a newer guarded implementation.
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

