-- Read-only presentation of existing movements and reconciliation snapshots.
-- No posting function or historical financial record is changed.
create function solar_private.cash_reconciliation_info(request uuid,owner uuid) returns jsonb
language sql stable set search_path='' as $$
 select jsonb_build_object('id',f.request_id,'receiptNo',f.response->'receiptNo','date',f.response->'date',
  'mode',case when f.payload->>'mode'='zero' or (f.payload->>'target')::numeric=0 then 'zero' else 'set' end,
  'currency',f.payload->>'currency','actorName',f.response->>'actorName','note',f.response->>'note')||r.value
 from solar_private.finance_requests f cross join lateral jsonb_array_elements(f.response->'rows') r(value)
 where f.request_id=request and f.action='cash_reconcile' and r.value->>'ownerId'=owner::text limit 1
$$;
revoke all on function solar_private.cash_reconciliation_info(uuid,uuid) from public,anon,authenticated;

do $$declare def text;old text:=$old$jsonb_build_object('ownerName',coalesce(o.display_name,o.username,'قيد التسليم'))$old$;begin
 def:=pg_get_functiondef('solar_private.cash_workspace(jsonb)'::regprocedure);
 if strpos(def,old)=0 then raise exception 'cash workspace row metadata anchor missing';end if;
 def:=replace(def,old,$new$jsonb_build_object('ownerName',coalesce(o.display_name,o.username,'قيد التسليم'),'reconciliation',case when x.kind='cash_reconcile' then solar_private.cash_reconciliation_info(x.request_id,x.owner_id) end)$new$);
 execute def;
end$$;

create function solar_private.cash_movement_detail(movement_id text) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;m record;t public.transactions;entry public.solar_cash_entries;
 handover solar_private.cash_transfers;fr solar_private.finance_requests;actor uuid;actor_name text;actor_phone text;
 balance_after numeric;document jsonb;items jsonb:='[]';transfer_info jsonb;exchange_info jsonb;reconciliation jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('warehouse','installer');
 if p.id is null or not solar_private.cash_allowed('view') then raise exception 'لا تملك صلاحية الصندوق' using errcode='42501';end if;
 if movement_id is null or length(movement_id)>100 then raise exception 'الحركة غير متاحة' using errcode='42501';end if;
 select x.*,coalesce(o.display_name,o.username,'قيد التسليم') owner_name into m
 from solar_private.cash_movements() x left join public.profiles o on o.id=x.owner_id
 where x.id=movement_id and(p.is_admin or x.owner_id=p.id);
 if not found then raise exception 'الحركة غير متاحة ضمن صلاحياتك' using errcode='42501';end if;
 select coalesce(sum(x.delta),0) into balance_after from solar_private.cash_movements() x
 where x.owner_id is not distinct from m.owner_id and x.currency=m.currency and(x.created_at,x.id)<=(m.created_at,m.id);
 if m.request_id is not null then select * into fr from solar_private.finance_requests f where f.request_id=m.request_id;actor:=fr.actor_id;end if;
 if m.id like 'tx:%' then
  select * into t from public.transactions where id=split_part(m.id,':',2)::bigint;actor:=t.created_by;
  document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'paymentMode',t.payment_mode,'warehouse',t.warehouse_name);
  select coalesce(jsonb_agg(jsonb_build_object('name',i.product_name,'brand',i.brand_name,'category',i.category,
   'qty',i.qty,'price',i.price,'total',round(i.qty*i.price,2)) order by i.id),'[]') into items from public.transaction_items i where i.transaction_id=t.id;
 elsif m.id like 'entry:%' then
  select * into entry from public.solar_cash_entries where id=split_part(m.id,':',2)::uuid;actor:=entry.actor_id;
  if entry.transfer_id is not null then
   select * into handover from solar_private.cash_transfers where id=entry.transfer_id;
   transfer_info:=jsonb_build_object('sender',(select coalesce(display_name,username) from public.profiles where id=handover.sender_id),
    'recipient',(select coalesce(display_name,username) from public.profiles where id=handover.recipient_id),'amount',handover.amount,
    'expense',handover.expense,'expenseNote',handover.expense_note,'note',handover.notes,'status',handover.status,'decidedAt',handover.decided_at,
    'decidedBy',(select coalesce(display_name,username) from public.profiles where id=handover.decided_by));
  elsif entry.job_id is not null then
   select * into t from public.transactions where id=entry.job_id;
   document:=jsonb_build_object('kind',t.kind,'receiptNo',t.receipt_no,'warehouse',t.warehouse_name);
  end if;
 end if;
 select coalesce(display_name,username),phone into actor_name,actor_phone from public.profiles where id=actor;
 if m.kind='cash_reconcile' then
  reconciliation:=solar_private.cash_reconciliation_info(m.request_id,m.owner_id);
  -- The saved reconciliation is authoritative even for legacy rows sharing a timestamp.
  if reconciliation is not null then balance_after:=(reconciliation->>('after'||m.currency))::numeric;end if;
 end if;
 if fr.payload->>'mode' in('buy_usd','sell_usd') and fr.response->>'ownerId'=m.owner_id::text then
  exchange_info:=jsonb_build_object('mode',fr.payload->>'mode','amount',fr.response->'amount','rate',fr.response->'rate',
   'beforeIQD',fr.response->'beforeIQD','afterIQD',fr.response->'afterIQD','beforeUSD',fr.response->'beforeUSD','afterUSD',fr.response->'afterUSD');
 end if;
 return jsonb_build_object('id',m.id,'ownerId',m.owner_id,'ownerName',m.owner_name,'currency',m.currency,'kind',m.kind,
  'date',m.created_at,'receiptNo',m.receipt_no,'delta',m.delta,'amount',abs(m.delta),'before',balance_after-m.delta,'after',balance_after,
  'party',m.party,'note',m.note,'sourceCurrency',m.source_currency,'sourceAmount',m.source_amount,'rate',m.rate,
  'actorName',actor_name,'actorPhone',actor_phone,'document',document,'items',items,'transfer',transfer_info,
  'reconciliation',reconciliation,'exchange',exchange_info);
end$$;
create function public.solar_cash_movement_detail(movement_id text) returns jsonb
 language sql stable security invoker set search_path='' as $$select solar_private.cash_movement_detail(movement_id)$$;
revoke all on function solar_private.cash_movement_detail(text),public.solar_cash_movement_detail(text) from public,anon;
grant execute on function solar_private.cash_movement_detail(text),public.solar_cash_movement_detail(text) to authenticated;
