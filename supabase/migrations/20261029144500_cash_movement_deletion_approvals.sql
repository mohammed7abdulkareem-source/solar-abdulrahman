-- Cash receipts use the existing owner request / administrator decision path.
-- No live financial records are changed by installing this migration.
alter function solar_private.receipt_delete_context(bigint) rename to receipt_delete_context_v387;
revoke all on function solar_private.receipt_delete_context_v387(bigint) from public,anon,authenticated;

create function solar_private.receipt_delete_context(invoice_id bigint) returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;t public.transactions;uid uuid;wallet jsonb;checkpoints jsonb;w solar_private.wallet_fx_entries;
 blocked text;profit_delta numeric;cash_delta numeric;usd jsonb;items jsonb;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية الوصولات' using errcode='42501';end if;
 select * into t from public.transactions where id=invoice_id;
 if t.kind not in('cash_income','cash_expense','profit_distribution') or t.id is null then
  return solar_private.receipt_delete_context_v387(invoice_id);
 end if;
 if not solar_private.cash_allowed('view')then raise exception 'لا تملك صلاحية الصندوق'using errcode='42501';end if;
 uid:=coalesce(t.cashbox_user_id,t.created_by);
 if uid is null or(not p.is_admin and uid<>p.id)then raise exception 'يمكنك طلب حذف وصولاتك فقط' using errcode='42501';end if;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into wallet from solar_private.wallet_fx_entries x where x.transaction_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(x)order by x.id),'[]')into items from public.transaction_items x where x.transaction_id=t.id;
 select coalesce(jsonb_agg(to_jsonb(c)order by c.owner_id,c.source_key),'[]')into checkpoints
 from solar_private.profit_checkpoints c where c.source_key='tx:'||t.id or exists(
  select 1 from solar_private.wallet_fx_entries e where e.transaction_id=t.id and c.source_key='walletfx:'||e.id);
 select -coalesce(sum((x->>'value')::numeric),0)into profit_delta from jsonb_array_elements(solar_private.profit_rows(uid))x
 where x->>'key'='tx:'||t.id or exists(select 1 from solar_private.wallet_fx_entries e where e.transaction_id=t.id and x->>'key'='walletfx:'||e.id);
 cash_delta:=(case when t.kind in('cash_expense','profit_distribution')then 1 else -1 end)*case when t.cash_currency='USD'then t.cash_amount else t.total end;
 if t.profit_settlement_id is not null or t.profit_supplier_settlement_id is not null then
  blocked:='حصة التسوية مرتبطة بربح الفترة ودين المورد؛ عدّل التسوية المعتمدة، ويمكن أن تكون حصة المستخدم صفرًا.';
 elsif not t.cash or jsonb_array_length(items)>0 or exists(select 1 from public.solar_cash_entries where job_id=t.id)
  or exists(select 1 from solar_private.supplier_fx_entries where transaction_id=t.id)
  or exists(select 1 from public.transactions where system_invoice_id=t.id)then
  blocked:='هذه الحركة مرتبطة بعملية أخرى؛ تُصحح من الوصل الأصلي حتى تتحدث جميع الحسابات.';
 elsif exists(select 1 from jsonb_array_elements(checkpoints)x where(x->>'value')::numeric<>0)then
  blocked:='دخلت هذه الحركة في تسوية أرباح معتمدة؛ راجع التسوية قبل حذف مصدرها.';
 elsif t.cash_currency='USD'then
  select * into w from solar_private.wallet_fx_entries where transaction_id=t.id;
  usd:=solar_private.usd_wallet(uid);
  if jsonb_array_length(wallet)<>1 or w.owner_id is distinct from uid or w.currency is distinct from 'USD' or w.delta is distinct from -cash_delta then
   blocked:='قيد الدولار غير متوازن مع الوصل؛ راجع الإدارة قبل الحذف.';
  elsif(usd->>'amount')::numeric-w.delta<0 or(usd->>'book')::numeric-w.book_delta<0
   or((usd->>'amount')::numeric=w.delta and(usd->>'book')::numeric<>w.book_delta)then
   blocked:='حذف هذا الوصل يترك رصيد الدولار أو كلفته غير متوازن؛ راجع الحركات اللاحقة أولًا.';
  end if;
 elsif jsonb_array_length(wallet)>0 then blocked:='للوصل قيد عملة مرتبط؛ راجع الإدارة قبل الحذف.';
 end if;
 return jsonb_build_object('id',t.id,'kind',t.kind,'receiptNo',t.receipt_no,'party',t.party_name,
  'total',case when t.cash_currency='USD'then t.cash_amount else t.total end,'currency',t.cash_currency,
  'ownerId',uid,'ownerName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=uid),
  'invoice',to_jsonb(t),'items',items,'expenseRefunds','[]'::jsonb,'expenseRefund',0,'retainedPayments',0,'blockedReason',blocked,
  'cashEffect',cash_delta,'profitEffectIQD',profit_delta,'cashPurpose',t.cash_purpose,'capitalEffect',t.capital_effect,'note',t.notes,
  'token',md5(to_jsonb(t)::text||wallet::text||items::text||checkpoints::text));
end$$;
revoke all on function solar_private.receipt_delete_context(bigint)from public,anon,authenticated;

create function solar_private.cash_receipt_delete(invoice_id bigint,request_id uuid)returns void
language plpgsql security definer set search_path='' as $$
#variable_conflict use_variable
declare p public.profiles;t public.transactions;c jsonb;entries jsonb;
begin
 select * into p from public.profiles where id=auth.uid()and active and is_admin and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا يمكن حذف الحركة قبل موافقة الإدارة' using errcode='42501';end if;
 perform pg_advisory_xact_lock(7311,1);
 select * into t from public.transactions where id=invoice_id and kind in('cash_income','cash_expense','profit_distribution')for update;
 if t.id is null then raise exception 'الحركة غير متاحة' using errcode='PT409';end if;
 -- Only the reviewed, pending approval can authorize this internal operation.
 if not exists(select 1 from solar_private.receipt_delete_requests r where r.id=request_id and r.invoice_id=t.id and r.status='pending')then
  raise exception 'طلب موافقة الحذف غير متاح' using errcode='42501';end if;
 c:=solar_private.receipt_delete_context(t.id);
 if c->>'blockedReason'is not null then raise exception '%',c->>'blockedReason' using errcode='PT409';end if;
 select coalesce(jsonb_agg(to_jsonb(e)order by e.id),'[]')into entries from solar_private.wallet_fx_entries e where e.transaction_id=t.id;
 insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by)values(t.id,
  to_jsonb(t)||jsonb_build_object('_walletEntriesBeforeDeletion',entries,'_deleteRequestId',request_id),'[]',p.id);
 -- Remove exactly the saved amount and book basis; daily FX never reprices it.
 delete from solar_private.wallet_fx_entries where transaction_id=t.id;
 delete from public.cash_ledger where transaction_id=t.id;
 delete from public.transactions where id=t.id;
 -- Creation retries remain tombstoned rather than recreating a deleted receipt.
 update solar_private.finance_requests f set response=response||jsonb_build_object('deleted',true,'deletedAt',now(),'deleteRequestId',request_id)
 where f.action='cash'and(f.request_id=t.finance_request_id or f.response->>'id'=t.id::text);
 insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)
 values(request_id,p.id,t.id,'cash_delete',jsonb_build_object('invoice',to_jsonb(t),'wallet',entries),null);
end$$;
revoke all on function solar_private.cash_receipt_delete(bigint,uuid)from public,anon,authenticated;

do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('solar_private.receipt_delete_requests(text,uuid,jsonb)'::regprocedure);
 needle:=$needle$  elsif t.kind='system_payment'then delete from public.cash_ledger where transaction_id=t.id;delete from public.transactions where id=t.id;$needle$;
 if strpos(definition,needle)=0 then raise exception 'Deletion approval dispatch contract missing';end if;
 definition:=replace(definition,needle,needle||E'\n  elsif t.kind in(''cash_income'',''cash_expense'',''profit_distribution'')then perform solar_private.cash_receipt_delete(t.id,r.id);');
 needle:=$needle$where(p.is_admin or q.owner_id=p.id)and(coalesce(payload->>'status','')=''or q.status=payload->>'status')$needle$;
 if strpos(definition,needle)=0 then raise exception 'Deletion request list scope contract missing';end if;
 definition:=replace(definition,needle,$replacement$where(p.is_admin or q.owner_id=p.id)and(q.kind not in('cash_income','cash_expense','profit_distribution')or solar_private.cash_allowed('view'))and(coalesce(payload->>'status','')=''or q.status=payload->>'status')$replacement$);
 needle:=$needle$ if action='get'then$needle$;
 if strpos(definition,needle)=0 then raise exception 'Deletion request review contract missing';end if;
 definition:=replace(definition,needle,$replacement$ if r.kind in('cash_income','cash_expense','profit_distribution')and not solar_private.cash_allowed('view')then raise exception 'لا تملك صلاحية الصندوق'using errcode='42501';end if;
 if action='get'then$replacement$);
 execute definition;
 definition:=pg_get_functiondef('solar_private.guard_receipt_delete_approval()'::regprocedure);
 needle:=$needle$'system_payment','supplier_payment')$needle$;
 if strpos(definition,needle)=0 then raise exception 'Deletion admin guard contract missing';end if;
 execute replace(definition,needle,$replacement$'system_payment','supplier_payment','cash_income','cash_expense','profit_distribution')$replacement$);
end$migration$;

-- Only whole receipts are deletable. Installation journals and paired FX /
-- transfer entries must continue through their owning operation.
create function solar_private.cash_movement_delete_context(movement_id text)returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare c jsonb;pending uuid;tid bigint;
begin
 if movement_id~'^tx:-?[0-9]+$'then
  tid:=substr(movement_id,4)::bigint;
  begin c:=solar_private.receipt_delete_context(tid);
  exception when insufficient_privilege then return jsonb_build_object('canRequest',false);end;
  select r.id into pending from solar_private.receipt_delete_requests r where r.invoice_id=tid and r.status='pending';
  return jsonb_build_object('canRequest',true,'invoiceId',tid,'blockedReason',c->>'blockedReason','pendingRequestId',pending);
 end if;
 return jsonb_build_object('canRequest',false,'blockedReason',case
  when movement_id like 'entry:%'then 'قيود التنصيب والتسليم تُلغى من العملية الأصلية حتى تتحدث القاصات والحسابات معًا.'
  else 'هذه الحركة جزء من تحويل أو صرافة أو مطابقة؛ تُصحح من العملية الأصلية مع جميع قيودها.'end);
end$$;
revoke all on function solar_private.cash_movement_delete_context(text)from public,anon,authenticated;
do $migration$
declare definition text;needle text;
begin
 definition:=pg_get_functiondef('solar_private.cash_movement_detail(text)'::regprocedure);
 needle:=$needle$return result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false));$needle$;
 if strpos(definition,needle)=0 then raise exception 'Cash movement details contract missing';end if;
 execute replace(definition,needle,$replacement$return result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false),'deletion',solar_private.cash_movement_delete_context(movement_id));$replacement$);
end$migration$;
notify pgrst,'reload schema';
