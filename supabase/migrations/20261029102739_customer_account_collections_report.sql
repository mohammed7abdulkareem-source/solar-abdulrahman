-- Receipt allocation is optional historical metadata. Collections are reported
-- once per customer account, alongside the open invoices' provisional profit.
alter function solar_private.pending_systems(uuid,date,date) rename to pending_systems_v385;
do $$begin execute replace(pg_get_functiondef('solar_private.pending_systems_v385(uuid,date,date)'::regprocedure),'pending_systems.owner_id','pending_systems_v385.owner_id');end$$;
revoke all on function solar_private.pending_systems_v385(uuid,date,date) from public,anon,authenticated;
create function solar_private.pending_systems(owner_id uuid default null,date_from date default null,date_to date default null) returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='10s' as $$
declare p public.profiles;result jsonb;accounts jsonb;
begin
 result:=solar_private.pending_systems_v385(owner_id,date_from,date_to);
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية الكشف' using errcode='42501';end if;
 with customers as materialized(
  select l.customer_id,count(distinct t.id)open_count
  from jsonb_array_elements(result->'rows')r join public.transactions t on t.id=(r->>'id')::bigint
  join solar_private.customer_movement_links()l on l.transaction_id=t.id group by l.customer_id
 ), collections as materialized(
  select l.customer_id,sum(m.book_delta)amount,count(*)receipt_count
  from public.transactions t join solar_private.cash_movements()m on m.id='tx:'||t.id
  join solar_private.customer_movement_links()l on l.transaction_id=t.id join customers c on c.customer_id=l.customer_id
  where t.kind in('sale','system','customer_payment','system_payment') and t.cash and m.book_delta>0
   and(case when p.is_admin then pending_systems.owner_id is null or m.owner_id=pending_systems.owner_id else m.owner_id=p.id end)
  group by l.customer_id
 )
 select coalesce(jsonb_agg(jsonb_build_object('customerId',c.customer_id,'customer',coalesce(u.name,'عميل غير محدد'),'openCount',c.open_count,
  'collected',round(coalesce(r.amount,0),2),'receiptCount',coalesce(r.receipt_count,0),
  'balance',coalesce((select sum((x->>'effect')::numeric)from jsonb_array_elements(solar_private.customer_ledger(c.customer_id))x),0))order by u.name,c.customer_id),'[]')
 into accounts from customers c left join public.customers u on u.id=c.customer_id left join collections r on r.customer_id=c.customer_id;
 return result||jsonb_build_object('collectionBasis','customer_account','accounts',accounts,'summary',(result->'summary')||jsonb_build_object(
  'accountCollections',(select coalesce(sum((x->>'collected')::numeric),0)from jsonb_array_elements(accounts)x),'accountCount',jsonb_array_length(accounts)));
end$$;
revoke all on function solar_private.pending_systems(uuid,date,date) from public,anon;
grant execute on function solar_private.pending_systems(uuid,date,date) to authenticated;
notify pgrst,'reload schema';
