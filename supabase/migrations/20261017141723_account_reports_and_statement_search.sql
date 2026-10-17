-- Read-only account resolution. An explicit, deleted customer ID is never
-- guessed from a reused name. Unlinked names resolve only when unambiguous.
create function solar_private.customer_movement_links()
returns table(transaction_id bigint,customer_id bigint,reason text)
language sql stable set search_path='' as $$
 with names as (
  select solar_private.customer_name_key(c.name) name_key,min(c.id) id,count(*) n
  from public.customers c group by solar_private.customer_name_key(c.name)
 )
 select t.id,case when c.id is not null then c.id when t.party_id is null and n.n=1 then n.id end,
 case when c.id is not null then 'id' when t.party_id is not null then 'missing_customer'
 when n.n=1 then 'name' when n.n>1 then 'ambiguous_name' else 'unknown_name' end
 from public.transactions t left join public.customers c on c.id=t.party_id
 left join names n on n.name_key=solar_private.customer_name_key(t.party_name) and n.name_key<>''
 where t.kind in ('sale','system','customer_payment','system_payment')
$$;
revoke all on function solar_private.customer_movement_links() from public,anon,authenticated;

create or replace function solar_private.customer_ledger(customer_id bigint) returns jsonb
language sql stable set search_path='' as $$
 select coalesce(jsonb_agg(jsonb_build_object('id',t.id,'receiptNo',t.receipt_no,'kind',t.kind,'mode',t.payment_mode,
 'date',t.created_at,'total',t.total,'cash',t.cash,'notes',t.notes,'effect',
 case when t.kind in ('customer_payment','system_payment') then -t.total when t.kind='sale' and t.cash then 0 else t.total end)
 order by t.created_at,t.id),'[]'::jsonb)
 from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id
 where l.customer_id=customer_ledger.customer_id
$$;

create or replace function solar_private.customer_statement(customer_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; c public.customers; rows jsonb; balance numeric;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 select * into c from public.customers where id=customer_id;
 if p.id is null or p.user_type in ('installer','warehouse') or c.id is null or
 not(p.is_admin or (coalesce(c.owner_id=p.id,false) and coalesce(p.permissions->>'customerStatement','false')='true')) then raise exception 'لا تملك صلاحية كشف هذا العميل' using errcode='42501';end if;
 rows:=solar_private.customer_ledger(c.id);
 select coalesce(sum((r->>'effect')::numeric),0) into balance from jsonb_array_elements(rows) r;
 return jsonb_build_object('id',c.id,'rows',rows,'balance',balance,'token',md5(rows::text),'name',c.name,
 'phone',c.phone,'customer_type',c.customer_type,'owner_id',c.owner_id,
 'owner_name',(select coalesce(x.display_name,x.username,'مستخدم') from public.profiles x where x.id=c.owner_id));
end $$;

-- The statement picker has its own authorized, uncapped directory. It does not
-- require permission to create customers or expose account movements.
create function solar_private.statement_customers() returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 if p.id is null or p.user_type in ('installer','warehouse') or not(p.is_admin or coalesce(p.permissions->>'customerStatement','false')='true') then raise exception 'لا تملك صلاحية كشف حساب العميل' using errcode='42501';end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.name,'phone',coalesce(c.phone,''),'customer_type',c.customer_type,
 'active',c.active,'owner_id',c.owner_id,'owner_name',coalesce(x.display_name,x.username,'غير مخصص')) order by c.name,c.id),'[]'::jsonb) into result
 from public.customers c left join public.profiles x on x.id=c.owner_id where p.is_admin or c.owner_id=p.id;
 return result;
end $$;
revoke all on function solar_private.statement_customers() from public,anon;
grant execute on function solar_private.statement_customers() to authenticated;
create function public.solar_statement_customers() returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.statement_customers()$$;
revoke all on function public.solar_statement_customers() from public,anon;
grant execute on function public.solar_statement_customers() to authenticated;

create or replace function solar_private.party_balances(report_kind text,as_of date) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles; result jsonb; permission_key text;
begin
 select * into p from public.profiles where id=auth.uid() and active;
 permission_key:=case report_kind when 'customers' then 'customerDebts' when 'suppliers' then 'supplierBalances' end;
 if p.id is null or p.user_type in ('installer','warehouse') or permission_key is null
 or not(p.is_admin or coalesce(p.permissions->>permission_key,'false')='true') then raise exception 'لا تملك صلاحية هذا التقرير' using errcode='42501';end if;
 if as_of is null or as_of>(now() at time zone 'Asia/Baghdad')::date then raise exception 'اختر تاريخ رصيد صحيحاً';end if;
 with all_parties as (
  select c.id,c.name,c.phone,c.customer_type,c.owner_id from public.customers c where report_kind='customers'
  union all select s.id,s.name,s.phone,null::text,null::uuid from public.suppliers s where report_kind='suppliers'
 ), names as (
  select solar_private.customer_name_key(a.name) name_key,min(a.id) id,count(*) n from all_parties a group by solar_private.customer_name_key(a.name)
 ), permitted_parties as (
  select a.* from all_parties a where report_kind='suppliers' or p.is_admin or a.owner_id=p.id
 ), movements as (
  select t.*,case when report_kind='customers' then l.customer_id when explicit.id is not null then explicit.id when t.party_id is null and n.n=1 then n.id end resolved_id,
  case when report_kind='customers' then l.reason when explicit.id is not null then 'id' when t.party_id is not null then 'missing_supplier' when n.n=1 then 'name' when n.n>1 then 'ambiguous_name' else 'unknown_name' end resolution,
  case when t.kind in ('customer_payment','system_payment','supplier_payment') then -t.total when t.kind in ('sale','purchase') and t.cash then 0 else t.total end effect,
  (t.kind in ('customer_payment','system_payment','supplier_payment') and t.total>0 and coalesce(t.payment_mode,'') not in ('opening_balance','account_reconciliation')) payment
  from public.transactions t left join solar_private.customer_movement_links() l on l.transaction_id=t.id and report_kind='customers'
  left join all_parties explicit on explicit.id=t.party_id
  left join names n on n.name_key=solar_private.customer_name_key(t.party_name) and n.name_key<>''
  where ((report_kind='customers' and t.kind in ('sale','system','customer_payment','system_payment')) or (report_kind='suppliers' and t.kind in ('purchase','supplier_payment')))
  and t.created_at<((as_of+1)::timestamp at time zone 'Asia/Baghdad')
  and (report_kind='customers' or p.is_admin or coalesce(t.cashbox_user_id,t.created_by)=p.id)
 ), balances as (
  select m.resolved_id,sum(m.effect) balance,
  (array_agg(m.total order by m.created_at desc,m.id desc) filter(where m.payment))[1] last_payment,
  max(m.created_at) filter(where m.payment) last_payment_at
  from movements m join permitted_parties c on c.id=m.resolved_id group by m.resolved_id
 ), rows as (
  select c.id,c.name,c.phone,c.customer_type,c.owner_id,coalesce(x.display_name,x.username,'غير مخصص') owner_name,
  coalesce(b.balance,0) balance,b.last_payment,b.last_payment_at
  from permitted_parties c left join balances b on b.resolved_id=c.id left join public.profiles x on x.id=c.owner_id
  where report_kind='customers' or p.is_admin or b.resolved_id is not null
 ), unresolved as (
  select m.id,m.receipt_no,m.party_name name,m.kind,m.payment_mode mode,m.created_at date,m.effect,
  case when m.kind in ('system','system_payment') then 'system' else 'wholesale' end customer_type,
  coalesce(m.cashbox_user_id,m.created_by) owner_id,coalesce(x.display_name,x.username,'غير مخصص') owner_name,
  case when m.payment_mode='opening_balance' and m.resolution in ('missing_customer','missing_supplier') then 'deleted_opening' else m.resolution end reason
  from movements m left join public.profiles x on x.id=coalesce(m.cashbox_user_id,m.created_by)
  where m.resolved_id is null and m.effect<>0 and (p.is_admin or coalesce(m.cashbox_user_id,m.created_by)=p.id)
 ), owners as (
  select distinct r.owner_id id,r.owner_name name from rows r where report_kind='customers'
  union select distinct u.owner_id,u.owner_name from unresolved u where report_kind='customers'
 )
 select jsonb_build_object('rows',coalesce((select jsonb_agg(to_jsonb(r) order by r.name,r.id) from rows r),'[]'::jsonb),
 'as_of',as_of,'unresolved',(select count(*) from unresolved),'unresolved_rows',coalesce((select jsonb_agg(to_jsonb(u) order by u.date,u.id) from unresolved u),'[]'::jsonb),
 'owners',coalesce((select jsonb_agg(to_jsonb(o) order by o.name,o.id) from owners o),'[]'::jsonb),
 'scope',case when p.is_admin then 'جميع المستخدمين' when report_kind='customers' then 'زبائنك المخصصون لك — كامل رصيد الزبون' else 'أرصدة الموردين ضمن حركات قاصتك المسموحة' end) into result;
 return result;
end $$;

-- A rename must retain uniquely matched legacy movements using the same
-- resolution rule as statements, debtor reports and opening-balance editing.
do $$declare definition text; before_text text; after_text text;begin
 select pg_get_functiondef('solar_private.customer_save(text,uuid,jsonb)'::regprocedure) into definition;
 before_text:='(t.party_id=c.id or(t.party_id is null and t.party_name=c.name and(select count(*) from public.customers x where x.name=c.name)=1))';
 after_text:='t.id in(select l.transaction_id from solar_private.customer_movement_links() l where l.customer_id=c.id)';
 if strpos(definition,before_text)=0 then raise exception 'Customer save definition changed; review rename integration';end if;
 execute replace(definition,before_text,after_text);
end $$;
