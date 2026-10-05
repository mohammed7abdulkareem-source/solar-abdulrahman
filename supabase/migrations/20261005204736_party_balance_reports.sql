-- Only aggregate account balances cross the transaction owner boundary.
-- A customer's assigned staff member needs the full balance, including payments
-- accepted by an administrator; transaction details remain under existing RLS.
create function solar_private.party_balances(report_kind text, as_of date)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb; permission_key text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 permission_key:=case report_kind when 'customers' then 'customerDebts' when 'suppliers' then 'supplierBalances' end;
 if p.id is null or p.user_type in ('installer','warehouse') or permission_key is null
    or not(p.is_admin or coalesce(p.permissions->>permission_key,'false')='true') then
  raise exception 'Not permitted' using errcode='42501';
 end if;
 if as_of is null or as_of>(now() at time zone 'Asia/Baghdad')::date then raise exception 'Invalid balance date';end if;
 with all_parties as (
  select c.id,c.name,c.phone,c.customer_type,c.owner_id from public.customers c where report_kind='customers'
  union all
  select s.id,s.name,s.phone,null::text,null::uuid from public.suppliers s where report_kind='suppliers'
 ), names as (
  select name,min(id) as id,count(*) as n from all_parties group by name
 ), permitted_parties as (
  select * from all_parties where report_kind='suppliers' or p.is_admin or owner_id=p.id
 ), movements as (
  select t.*,case when t.party_id is not null then t.party_id when names.n=1 then names.id end as resolved_id
  from public.transactions t left join names on names.name=t.party_name
  where ((report_kind='customers' and t.kind in ('sale','system','customer_payment','system_payment'))
     or (report_kind='suppliers' and t.kind in ('purchase','supplier_payment')))
   and t.created_at < ((as_of+1)::timestamp at time zone 'Asia/Baghdad')
   and (report_kind='customers' or p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id)
 ), matched as (
  -- Legacy system invoices always set cash=true even though collections are separate.
  -- Only wholesale cash sales and cash purchases are already settled by that flag.
  select t.*,case when t.kind in ('customer_payment','system_payment','supplier_payment') then -t.total
    when t.kind in ('sale','purchase') and t.cash then 0 else t.total end as effect,
    (t.kind in ('customer_payment','system_payment','supplier_payment') and t.total>0) as payment
  from movements t join permitted_parties c on c.id=t.resolved_id
 ), balances as (
  select resolved_id,sum(effect) as balance,
    (array_agg(total order by created_at desc,id desc) filter(where payment))[1] as last_payment,
    max(created_at) filter(where payment) as last_payment_at
  from matched group by resolved_id
 ), rows as (
  select c.id,c.name,c.phone,c.customer_type,coalesce(b.balance,0) as balance,b.last_payment,b.last_payment_at
  from permitted_parties c left join balances b on b.resolved_id=c.id
  where report_kind='customers' or p.is_admin or b.resolved_id is not null
 ), unresolved as (
  select count(*) as n from movements t
  where not exists(select 1 from all_parties a where a.id=t.resolved_id)
   and (p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id)
   and (t.kind in ('customer_payment','system_payment','supplier_payment') or not t.cash)
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.name,r.id) from rows r),'[]'::jsonb),
  'as_of',as_of,'unresolved',(select n from unresolved),
  'scope',case when p.is_admin then 'جميع المستخدمين'
    when report_kind='customers' then 'عملاؤك المخصصون لك — كامل رصيد العميل'
    else 'أرصدة الموردين ضمن حركات قاصتك المسموحة' end) into result;
 return result;
end $$;
revoke all on function solar_private.party_balances(text,date) from public,anon;
grant execute on function solar_private.party_balances(text,date) to authenticated;

create function public.solar_party_balances(report_kind text,as_of date)
returns jsonb language sql stable security invoker set search_path='' as $$
 select solar_private.party_balances(report_kind,as_of)
$$;
revoke all on function public.solar_party_balances(text,date) from public,anon;
grant execute on function public.solar_party_balances(text,date) to authenticated;
