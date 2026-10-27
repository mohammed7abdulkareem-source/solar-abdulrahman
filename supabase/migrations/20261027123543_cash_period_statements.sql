-- One read snapshot of the current cash ledger. No cached receipt balances,
-- posting changes, row caps or per-movement API requests.
create function solar_private.cash_statement(owner_id uuid,date_from date,date_to date,currency_filter text default 'all') returns jsonb
language plpgsql stable security definer set search_path='' set statement_timeout='15s' as $$
declare p public.profiles;uid uuid;start_at timestamptz;end_at timestamptz;result jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null or not coalesce(solar_private.cash_allowed('view'),false) then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 uid:=cash_statement.owner_id;
 if not p.is_admin then
  if uid is not null and uid<>p.id then raise exception 'يمكنك مشاهدة كشف قاصتك فقط' using errcode='42501';end if;
  uid:=p.id;
 end if;
 if uid is not null and not exists(select 1 from public.profiles o where o.id=uid and o.user_type not in('installer','warehouse')) then raise exception 'القاصة غير متاحة' using errcode='22023';end if;
 if date_from is null or date_to is null or date_from>date_to or not isfinite(date_from) or not isfinite(date_to) or currency_filter is null or currency_filter not in('all','IQD','USD') then raise exception 'اختر فترة وعملة صحيحة للكشف' using errcode='22023';end if;
 start_at:=date_from::timestamp at time zone 'Asia/Baghdad';end_at:=(date_to+1)::timestamp at time zone 'Asia/Baghdad';
 with movements as materialized(
  select m.* from solar_private.cash_movements() m where (uid is null or m.owner_id=uid) and(currency_filter='all' or m.currency=currency_filter) and m.created_at<end_at
 ), owners as(
  select o.id from public.profiles o where (uid is null or o.id=uid) and o.user_type not in('installer','warehouse') and(o.active or exists(select 1 from movements m where m.owner_id=o.id))
  union select m.owner_id from movements m
 ), currencies as(select c from (values('IQD'),('USD')) v(c) where currency_filter='all' or c=currency_filter),
 ranked as materialized(
  select m.*,sum(m.delta) over(partition by m.owner_id,m.currency order by m.created_at,m.id rows unbounded preceding) balance from movements m
 ), period_rows as materialized(
  select m.*,coalesce(a.display_name,a.username,'غير محدد') actor_name,t.warehouse_name,
   coalesce(t.payment_mode,j.payment_mode) payment_mode,
   case when e.job_id is not null then j.receipt_no end job_receipt,
   coalesce(sender.display_name,sender.username) sender_name,coalesce(recipient.display_name,recipient.username) recipient_name,
   h.amount transfer_amount,h.expense transfer_expense,h.expense_note,h.notes transfer_note,h.status transfer_status,
   case when m.kind='cash_reconcile' then solar_private.cash_reconciliation_info(m.request_id,m.owner_id) end reconciliation
  from ranked m
  left join public.transactions t on m.id='tx:'||t.id
  left join public.solar_cash_entries e on m.id='entry:'||e.id
  left join public.transactions j on j.id=e.job_id
  left join solar_private.finance_requests f on f.request_id=m.request_id
  left join public.profiles a on a.id=coalesce(t.created_by,e.actor_id,f.actor_id)
  left join solar_private.cash_transfers h on h.id=e.transfer_id
  left join public.profiles sender on sender.id=h.sender_id
  left join public.profiles recipient on recipient.id=h.recipient_id
  where m.created_at>=start_at
 ), ledgers as(
  select o.id,c.c currency,coalesce(pf.display_name,pf.username,'قيد التسليم') owner_name,
   coalesce(sum(m.delta) filter(where m.created_at<start_at),0) opening,
   coalesce(sum(m.delta) filter(where m.created_at>=start_at and m.delta>0),0) incoming,
   coalesce(sum(-m.delta) filter(where m.created_at>=start_at and m.delta<0),0) outgoing,
   coalesce(sum(m.delta),0) closing,
   (select coalesce(jsonb_agg(to_jsonb(r) order by r.created_at,r.id),'[]') from period_rows r where r.owner_id is not distinct from o.id and r.currency=c.c) rows
  from owners o cross join currencies c left join public.profiles pf on pf.id=o.id
  left join movements m on m.owner_id is not distinct from o.id and m.currency=c.c
  group by o.id,c.c,pf.display_name,pf.username
 )
 select jsonb_build_object('asOf',statement_timestamp(),'from',date_from,'to',date_to,'ownerId',uid,
  'ownerName',case when uid is null then 'جميع القاصات' else(select coalesce(display_name,username,'مستخدم') from public.profiles where id=uid) end,
  'count',(select count(*) from period_rows),
  'ledgers',coalesce(jsonb_agg(jsonb_build_object('ownerId',id,'ownerName',owner_name,'currency',currency,'opening',opening,'incoming',incoming,'outgoing',outgoing,'closing',closing,'rows',rows) order by owner_name,id,currency),'[]'))
 into result from ledgers;
 return result;
end$$;
create function public.solar_cash_statement(owner_id uuid,date_from date,date_to date,currency_filter text default 'all') returns jsonb
language sql stable security invoker set search_path='' as $$select solar_private.cash_statement(owner_id,date_from,date_to,currency_filter)$$;
revoke all on function solar_private.cash_statement(uuid,date,date,text),public.solar_cash_statement(uuid,date,date,text) from public,anon;
grant execute on function solar_private.cash_statement(uuid,date,date,text),public.solar_cash_statement(uuid,date,date,text) to authenticated;
notify pgrst,'reload schema';
