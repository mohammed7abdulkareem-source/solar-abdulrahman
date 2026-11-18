-- Reconcile the expected ledger legs of recorded handovers. Dates refer to
-- the decision for a finished transfer and creation for an open transfer.
create function solar_private.user_activity_review(uid uuid,date_from date,date_to date)
returns jsonb language sql stable set search_path = '' as $$
 with period as (
  select date_from::timestamp at time zone 'Asia/Baghdad' as lo,
    (date_to+1)::timestamp at time zone 'Asia/Baghdad' as hi
 ), requests as (
  select t.id,t.amount,t.expense,t.sender_id,t.recipient_id,t.status,coalesce(t.decided_at,t.created_at) at_time
  from solar_private.cash_transfers t cross join period p
  where uid in (t.sender_id,t.recipient_id)
    and (p.lo is null or coalesce(t.decided_at,t.created_at)>=p.lo)
    and (p.hi is null or coalesce(t.decided_at,t.created_at)<p.hi)
 ), direct as (
  select f.request_id id,(f.response->>'date')::timestamptz at_time,f.response->>'receiptNo' receipt,
    f.response->>'currency' currency,(f.response->>'amount')::numeric amount,
    (f.response->>'senderId')::uuid sender,(f.response->>'recipientId')::uuid recipient
  from solar_private.finance_requests f cross join period p
  where f.action='admin_cash_transfer' and uid::text in (f.response->>'senderId',f.response->>'recipientId')
    and not coalesce((f.response->>'deleted')::boolean,false)
    and (p.lo is null or (f.response->>'date')::timestamptz>=p.lo)
    and (p.hi is null or (f.response->>'date')::timestamptz<p.hi)
 ), expected as (
  select t.id,t.at_time,null::text receipt,'IQD' currency,k.kind,k.owner_id,k.delta,k.n
  from requests t cross join lateral (values
    ('transfer_out',t.sender_id,-t.amount,1),
    ('transfer_in',t.recipient_id,case when t.status='accepted' then t.amount else 0 end,case when t.status='accepted' then 1 else 0 end),
    ('transfer_refund',t.sender_id,case when t.status in ('cancelled','rejected') then t.amount else 0 end,case when t.status in ('cancelled','rejected') then 1 else 0 end),
    ('handover_expense',t.sender_id,-t.expense,case when t.expense<>0 then 1 else 0 end),
    ('transfer_transit',null::uuid,case when t.status='pending' then t.amount else 0 end,case when t.status='pending' then 1 else 2 end)
  ) k(kind,owner_id,delta,n)
  union all
  select d.id,d.at_time,d.receipt,d.currency,k.kind,k.owner_id,k.delta,1
  from direct d cross join lateral (values ('admin_transfer_out',d.sender,-d.amount),('admin_transfer_in',d.recipient,d.amount)) k(kind,owner_id,delta)
 ), posted as (
  select e.transfer_id id,'IQD'::text currency,e.entry_type kind,e.owner_id,sum(e.delta) delta,count(*) n
  from public.solar_cash_entries e join requests t on t.id=e.transfer_id
  group by e.transfer_id,e.entry_type,e.owner_id
  union all
  select w.finance_request_id,w.currency,w.entry_type,w.owner_id,sum(w.delta),count(*)
  from solar_private.wallet_fx_entries w join direct d on d.id=w.finance_request_id
  where w.entry_type in ('admin_transfer_in','admin_transfer_out')
  group by w.finance_request_id,w.currency,w.entry_type,w.owner_id
 ), records as (
  select id,at_time,null::text receipt from requests union all select id,at_time,receipt from direct
 ), keys as (
  select id,currency,kind,owner_id from expected union select id,currency,kind,owner_id from posted
 ), differences as (
  select k.id,k.currency,k.kind,k.owner_id,r.at_time,r.receipt,coalesce(e.delta,0) expected,coalesce(p.delta,0) posted,
   coalesce(e.n,0) expected_count,coalesce(p.n,0) posted_count
  from keys k join records r using(id)
  left join expected e on e.id=k.id and e.kind=k.kind and e.currency=k.currency and e.owner_id is not distinct from k.owner_id
  left join posted p on p.id=k.id and p.kind=k.kind and p.currency=k.currency and p.owner_id is not distinct from k.owner_id
  where coalesce(e.delta,0)<>coalesce(p.delta,0) or coalesce(e.n,0)<>coalesce(p.n,0)
 ), display as (
  select * from differences order by at_time desc,id,kind,currency,owner_id limit 50
 )
 select jsonb_build_object('ownerId',uid,'checkedTransfers',(select count(*) from records),
  'differenceCount',(select count(*) from differences),
  'book',case when exists(select 1 from public.profiles where id=uid and user_type not in ('warehouse','installer')) then
    jsonb_build_object('IQD',solar_private.cash_balance(uid),'USD',(solar_private.usd_wallet(uid)->>'amount')::numeric) end,
  'differences',(select coalesce(jsonb_agg(jsonb_build_object('ref',id,'receiptNo',receipt,'at',at_time,'kind',kind,
    'currency',currency,'expected',expected,'posted',posted,'expectedCount',expected_count,'postedCount',posted_count)
    order by at_time desc,id,kind,currency,owner_id),'[]'::jsonb) from display))
$$;
revoke all on function solar_private.user_activity_review(uuid,date,date) from public,anon,authenticated;
