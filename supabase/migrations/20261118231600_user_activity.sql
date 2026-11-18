-- A read-only administrator view. Use stored receipt values and distinguish
-- money collected from customers from money actually received by another cashbox.
create function solar_private.user_activity(payload jsonb)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
 actor_id uuid := auth.uid();
 person public.profiles;
 today date := (statement_timestamp() at time zone 'Asia/Baghdad')::date;
 first_day date; last_day date; start_at timestamptz; end_at timestamptz;
 result jsonb;
begin
 if not exists(select 1 from public.profiles p where p.id=actor_id and p.active and p.is_admin
               and p.user_type not in ('warehouse','installer')) then
  raise exception 'نشاط المستخدمين متاح للأدمن فقط' using errcode='42501';
 end if;
 if jsonb_typeof(payload) is distinct from 'object' or payload-'ownerId'-'from'-'to' <> '{}'::jsonb then
  raise exception 'طلب نشاط المستخدم غير صحيح' using errcode='22023';
 end if;
 if payload->>'ownerId' is null then
  if payload<>'{}'::jsonb then raise exception 'اختر المستخدم' using errcode='22023';end if;
  select jsonb_build_object('asOf',statement_timestamp(),'users',coalesce(jsonb_agg(jsonb_build_object(
   'id',p.id,'name',solar_private.user_name(p.display_name,p.username,p.honorific),
   'username',p.username,'userType',p.user_type,'active',p.active)
   order by p.active desc,solar_private.user_name(p.display_name,p.username,p.honorific),p.id),'[]'::jsonb))
  into result from public.profiles p where p.is_admin is false;
  return result;
 end if;
 select * into person from public.profiles p where p.id=(payload->>'ownerId')::uuid and p.is_admin is false;
 if person.id is null then raise exception 'هذا الحساب غير متاح في نشاط المستخدمين' using errcode='42501';end if;
 if coalesce(payload->>'from','') !~ '^([0-9]{4}-[0-9]{2}-[0-9]{2})?$'
    or coalesce(payload->>'to','') !~ '^([0-9]{4}-[0-9]{2}-[0-9]{2})?$' then
  raise exception 'أدخل فترة صحيحة' using errcode='22023';
 end if;
 first_day:=nullif(payload->>'from','')::date;
 last_day:=coalesce(nullif(payload->>'to','')::date,today);
 if first_day>last_day or last_day>today then raise exception 'اختر فترة صحيحة حتى اليوم' using errcode='22023';end if;
 start_at:=coalesce(first_day::timestamp at time zone 'Asia/Baghdad','-infinity'::timestamptz);
 end_at:=(last_day+1)::timestamp at time zone 'Asia/Baghdad';

 with receipts as materialized (
  select t.id,t.kind,t.party_name,t.receipt_no,t.created_at,t.cash,t.total,t.expenses,t.expenses_on_customer,
    t.source_currency,t.source_subtotal,t.exchange_rate,t.cash_currency,t.cash_amount,t.cash_purpose,
    t.payment_mode,t.installation_status,t.installation_expenses,t.profit_settlement_id,
    coalesce(t.created_by,t.cashbox_user_id)=person.id as authored,
    coalesce(t.cashbox_user_id,t.created_by)=person.id as in_box
  from public.transactions t where t.created_at>=start_at and t.created_at<end_at
    and (t.created_by=person.id or t.cashbox_user_id=person.id)
 ), sales as (
  select * from receipts where authored and kind in ('sale','system')
 ), target_customers as (
  -- Match the account statement's current assigned portfolio, including a
  -- historical receipt linked to a customer record imported at a later date.
  select c.id from public.customers c where c.owner_id=person.id
 ), customer_effects as (
  -- Same resolution rules and account effects as the customer statement, including
  -- payments recorded for this person's customers by another cashier.
  select l.customer_id,sum(case when t.kind in ('customer_payment','system_payment') then -t.total
                                when t.kind='sale' and t.cash then 0 else t.total end) amount
  from solar_private.customer_movement_links() l join target_customers c on c.id=l.customer_id
  join public.transactions t on t.id=l.transaction_id where t.created_at<end_at group by l.customer_id
 ), debts as (
  select coalesce(e.amount,0) amount from target_customers c left join customer_effects e on e.customer_id=c.id
 ), flows(id,at,kind,amount,currency,party,receipt_no) as materialized (
  select 'tx:'||t.id,t.created_at,t.kind,
    case when t.kind='purchase' and t.source_currency='USD' then
     round(coalesce(t.source_subtotal,(t.total-coalesce(t.expenses,0))/t.exchange_rate)+coalesce(t.expenses,0)/t.exchange_rate,2)
    else t.total end,
    case when t.kind='purchase' then t.source_currency else 'IQD' end,t.party_name,t.receipt_no
  from receipts t where t.authored and t.kind in ('sale','system','purchase')
  union all
  select 'tx:'||t.id,t.created_at,t.kind,
    case when t.cash_currency='USD' then t.cash_amount else t.total end,t.cash_currency,t.party_name,t.receipt_no
  from receipts t where t.in_box and t.cash and t.kind in ('customer_payment','system_payment')
   and t.total>0 and (t.cash_currency<>'USD' or t.cash_amount>0)
   and coalesce(t.payment_mode,'') not in ('opening_balance','account_reconciliation')
  union all
  select 'tx:'||t.id,t.created_at,'expense',case when t.cash_currency='USD' then t.cash_amount else t.total end,
    t.cash_currency,null,t.receipt_no
  from receipts t where t.in_box and t.cash and t.cash_purpose='expense' and t.profit_settlement_id is null
  union all
  select 'tx:'||t.id,t.created_at,'profit_expense',t.total,'IQD',null,t.receipt_no
  from receipts t where t.in_box and not t.cash and t.profit_settlement_id is null
    and (t.kind='profit_expense' or t.cash_purpose='expense')
  union all
  select 'entry:'||e.id,e.created_at,'expense',-e.delta,'IQD',null,null
  from public.solar_cash_entries e where e.owner_id=person.id and e.entry_type='handover_expense'
    and e.created_at>=start_at and e.created_at<end_at
  union all
  select 'transfer:'||h.id,h.decided_at,case when h.sender_id=person.id then 'handover_out' else 'handover_in' end,
    h.amount,'IQD',null,null
  from solar_private.cash_transfers h where h.status='accepted' and person.id in(h.sender_id,h.recipient_id)
   and h.decided_at>=start_at and h.decided_at<end_at
  union all
  select 'pending:'||h.id,h.created_at,'pending_handover',h.amount,'IQD',null,null
  from solar_private.cash_transfers h where h.status='pending' and h.sender_id=person.id
    and h.created_at>=start_at and h.created_at<end_at
  union all
  select 'wallet:'||w.id,w.created_at,case when w.entry_type='admin_transfer_out' then 'handover_out' else 'handover_in' end,
   abs(w.delta),w.currency,null,(f.response->>'receiptNo')::bigint
  from solar_private.wallet_fx_entries w
  join solar_private.finance_requests f on f.request_id=w.finance_request_id and f.action='admin_cash_transfer'
  where w.owner_id=person.id and w.entry_type in('admin_transfer_out','admin_transfer_in')
    and w.created_at>=start_at and w.created_at<end_at
 ), totals as (
  select g.name,jsonb_build_object('count',count(f.id),'IQD',coalesce(sum(f.amount) filter(where f.currency='IQD'),0),
     'USD',coalesce(sum(f.amount) filter(where f.currency='USD'),0)) amounts
  from (values ('collections',array['customer_payment','system_payment']),('outgoing',array['handover_out']),
    ('incoming',array['handover_in']),('pendingOutgoing',array['pending_handover']),('expense',array['expense'])) g(name,kinds)
  left join flows f on f.kind=any(g.kinds) group by g.name
 )
 select jsonb_build_object(
  'user',jsonb_build_object('id',person.id,'name',solar_private.user_name(person.display_name,person.username,person.honorific),
      'username',person.username,'userType',person.user_type,'active',person.active),
  'from',first_day,'to',last_day,'asOf',statement_timestamp(),
  'sales',(select jsonb_build_object('count',count(*),'totalIQD',coalesce(sum(total),0),
      'wholesaleCount',count(*) filter(where kind='sale'),'wholesaleIQD',coalesce(sum(total) filter(where kind='sale'),0),
      'systemCount',count(*) filter(where kind='system'),'systemIQD',coalesce(sum(total) filter(where kind='system'),0)) from sales),
  'debts',(select jsonb_build_object('dueIQD',coalesce(sum(greatest(amount,0)),0),'creditIQD',coalesce(sum(greatest(-amount,0)),0),
     'netIQD',coalesce(sum(amount),0),'customerCount',count(*),'debtorCount',count(*) filter(where amount>0)) from debts),
  'profit',jsonb_build_object('remainingIQD',solar_private.retained_profit(person.id),'earnedIQD',(
     select coalesce(sum((v->>'value')::numeric),0) from jsonb_array_elements(solar_private.profit_rows(person.id)) v
     where v->>'kind' not in('external_adjustment','personal_distribution')
      and (v->>'date')::timestamptz>=start_at and (v->>'date')::timestamptz<end_at)),
  'cash',jsonb_build_object('IQD',solar_private.cash_balance(person.id),'USD',(solar_private.usd_wallet(person.id)->>'amount')::numeric),
  'collections',(select amounts from totals where name='collections'),
  'handovers',(select jsonb_object_agg(name,amounts) from totals where name in('outgoing','incoming','pendingOutgoing')),
  'expenses',jsonb_build_object('cash',(select amounts from totals where name='expense'),
     'personalProfitIQD',(select coalesce(sum(amount),0) from flows where kind='profit_expense'),
     'companySaleIQD',(select coalesce(sum(expenses),0) from sales where kind='sale' and expenses_on_customer is false),
     'customerSaleIQD',(select coalesce(sum(expenses),0) from sales where kind='sale' and coalesce(expenses_on_customer,true)),
     'systemInstallationIQD',(select coalesce(sum(installation_expenses),0) from sales where kind='system' and installation_status='closed')),
  'operations',solar_private.user_activity_operations(person.id,first_day,last_day),
  'review',solar_private.user_activity_review(person.id,first_day,last_day),
  'recent',(select coalesce(jsonb_agg(jsonb_build_object('id',r.id,'date',r.at,'kind',r.kind,'amount',r.amount,'currency',r.currency,
     'party',r.party,'receiptNo',r.receipt_no) order by r.at desc,r.id),'[]'::jsonb)
     from(select * from flows where kind<>'pending_handover' order by at desc,id limit 50) r)) into result;
 return result;
end $$;

create function public.solar_user_activity(payload jsonb default '{}'::jsonb)
returns jsonb language sql stable security invoker set search_path='' as $$select solar_private.user_activity(payload)$$;
revoke all on function solar_private.user_activity(jsonb), public.solar_user_activity(jsonb) from public,anon,authenticated;
grant execute on function solar_private.user_activity(jsonb), public.solar_user_activity(jsonb) to authenticated;
notify pgrst,'reload schema';
