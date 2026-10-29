-- Editing is scoped to the owning cashbox and its operation permission.
-- Settlement allocations remain admin-only and keep the reviewed profit fixed.
create function solar_private.cash_record_context(movement_id text,full_details boolean default true)returns jsonb
language plpgsql stable security definer set search_path='' as $$
declare p public.profiles;t public.transactions;w solar_private.wallet_fx_entries;fr solar_private.finance_requests;r solar_private.profit_settlements;
 uid uuid;mode text;permission text;linked public.transactions;rows jsonb;wallet jsonb;result jsonb;token text;
begin
 select * into p from public.profiles where id=auth.uid() and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية القاصة'using errcode='42501';end if;
 if movement_id is null then
  if not p.is_admin then raise exception 'التسليم المباشر للإدارة فقط'using errcode='42501';end if;
  return jsonb_build_object('type','transfer','canEdit',true,'owners',(select coalesce(jsonb_agg(jsonb_build_object('id',o.id,'name',solar_private.user_name(o.display_name,o.username,o.honorific),'IQD',solar_private.cash_balance(o.id),'USD',(solar_private.usd_wallet(o.id)->>'amount')::numeric)order by o.display_name),'[]')from public.profiles o where o.active and o.user_type not in('installer','warehouse')));
 end if;
 if movement_id~'^tx:-?[0-9]+$'then
  select * into t from public.transactions where id=substr(movement_id,4)::bigint;
  uid:=coalesce(t.cashbox_user_id,t.created_by);
  if t.id is null or(not p.is_admin and uid is distinct from p.id)then raise exception 'الحركة غير متاحة ضمن صلاحياتك'using errcode='42501';end if;
  if t.profit_settlement_id is not null then select * into r from solar_private.profit_settlements where id=t.profit_settlement_id;end if;
 elsif movement_id~'^profit:[a-f0-9-]{36}$'then
  if not p.is_admin then raise exception 'تعديل التسوية المعتمدة للإدارة فقط'using errcode='42501';end if;
  select * into r from solar_private.profit_settlements where id=substr(movement_id,8)::uuid;
  if r.id is null then raise exception 'التسوية غير متاحة'using errcode='42501';end if;
  select * into t from public.transactions where profit_settlement_id=r.id;
 elsif movement_id~'^fx:[0-9]+$'then
  select * into w from solar_private.wallet_fx_entries where id=substr(movement_id,4)::bigint;
  if w.id is null or(not p.is_admin and w.owner_id<>p.id)then raise exception 'الحركة غير متاحة ضمن صلاحياتك'using errcode='42501';end if;
  select * into fr from solar_private.finance_requests where request_id=w.finance_request_id and action='admin_cash_transfer';
  if fr.request_id is null then return jsonb_build_object('canEdit',false);end if;
  result:=fr.response||jsonb_build_object('type','transfer','canEdit',p.is_admin);
  if not full_details or not p.is_admin then return jsonb_build_object('type','transfer','canEdit',p.is_admin);end if;
  select coalesce(jsonb_agg(to_jsonb(e)order by id),'[]')into rows from solar_private.wallet_fx_entries e where e.finance_request_id=fr.request_id;
  return result||jsonb_build_object('movementId',movement_id,'senderBalance',case when w.currency='USD'then(solar_private.usd_wallet((fr.response->>'senderId')::uuid)->>'amount')::numeric else solar_private.cash_balance((fr.response->>'senderId')::uuid)end,'recipientBalance',case when w.currency='USD'then(solar_private.usd_wallet((fr.response->>'recipientId')::uuid)->>'amount')::numeric else solar_private.cash_balance((fr.response->>'recipientId')::uuid)end,'token',md5(to_jsonb(fr)::text||rows::text));
 else return jsonb_build_object('canEdit',false);end if;
 if r.id is not null then
  if not p.is_admin or r.status<>'approved' or r.settlement_model<>'owner_debit_supplier_charge' or t.id is null then return jsonb_build_object('type','settlement','canEdit',false);end if;
  if not full_details then return jsonb_build_object('type','settlement','canEdit',true);end if;
  select * into linked from public.transactions where id=(r.supplier_receipt->>'id')::bigint and supplier_payment_voided_at is null;
  rows:=solar_private.profit_supplier_accounts();
  return jsonb_build_object('type','settlement','canEdit',true,'movementId','profit:'||r.id,'id',r.id,'ownerId',r.owner_id,
   'ownerName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=r.owner_id),
   'profit',r.profit,'amount',r.share,'note',coalesce(r.decision_note,''),'currency','IQD','supplierId',r.supplier_id,'supplierRate',r.supplier_rate,
   'supplierAmountIQD',r.supplier_amount_iqd,'supplierAmount',r.supplier_amount,'supplierCurrency',r.supplier_currency,'suppliers',rows,'cashBalance',solar_private.cash_balance(r.owner_id),
   'token',md5(to_jsonb(r)::text||to_jsonb(t)::text||coalesce(to_jsonb(linked)::text,'')||rows::text||solar_private.cash_balance(r.owner_id)::text));
 end if;
 if not t.cash or t.kind not in('cash_income','cash_expense','profit_distribution') or exists(select 1 from public.transaction_items where transaction_id=t.id)then return jsonb_build_object('canEdit',false);end if;
 mode:=case when t.kind='profit_distribution'then'distribution'when t.cash_purpose='external_profit'then'external_profit'when t.capital_effect and t.kind='cash_expense'then'capital_withdraw'when t.capital_effect then'capital_deposit'when t.kind='cash_expense'then'expense'else'deposit'end;
 permission:=case mode when'deposit'then'cashDeposit'when'expense'then'cashExpense'when'external_profit'then'cashExternalProfit'when'distribution'then'adminOnly'else'cashAdminTools'end;
 result:=jsonb_build_object('type','cash','canEdit',solar_private.cash_allowed(permission));
 if not full_details or not(result->>'canEdit')::boolean then return result;end if;
 select * into w from solar_private.wallet_fx_entries where transaction_id=t.id;
 if t.cash_currency='USD'and w.id is null then return jsonb_build_object('canEdit',false);end if;
 wallet:=solar_private.usd_wallet(uid);
 return result||jsonb_build_object('movementId',movement_id,'id',t.id,'receiptNo',t.receipt_no,'ownerId',uid,
  'ownerName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=uid),'mode',mode,
  'currency',t.cash_currency,'amount',case when t.cash_currency='USD'then t.cash_amount else t.total end,'rate',case when t.cash_currency='USD'then t.market_rate else 1 end,
  'note',coalesce(t.notes,''),'canRate',p.is_admin or p.permissions->>'exchangeRateEdit'='true','cashBalance',solar_private.cash_balance(uid),'usdBalance',(wallet->>'amount')::numeric,
  'token',md5(to_jsonb(t)::text||coalesce(to_jsonb(w)::text,'')||wallet::text||solar_private.cash_balance(uid)::text));
end$$;
revoke all on function solar_private.cash_record_context(text,boolean)from public,anon,authenticated;

create function solar_private.cash_record(action text,movement_id text default null,request_id uuid default null,payload jsonb default '{}')returns jsonb
language plpgsql security definer set search_path=''set lock_timeout='5s'as $$
#variable_conflict use_variable
declare p public.profiles;ctx jsonb;prior solar_private.finance_requests;t public.transactions;w solar_private.wallet_fx_entries;r solar_private.profit_settlements;original jsonb;
 amount numeric;rate numeric;book numeric;gain numeric;sign numeric;uid uuid;recipient uuid;wallet jsonb;other_wallet jsonb;result jsonb;before_iqd numeric;before_usd numeric;before_other_iqd numeric;before_other_usd numeric;
 supplier public.suppliers;destination jsonb;addition jsonb;charge_changed boolean;old_charge public.transactions;old_context jsonb;remaining numeric;old_supplier_receipt jsonb;number bigint;note text;old_rows jsonb;new_rows jsonb;transfer_id uuid;
begin
 select * into p from public.profiles where id=auth.uid()and active and user_type not in('installer','warehouse');
 if p.id is null then raise exception 'لا تملك صلاحية القاصة'using errcode='42501';end if;
 if action not in('get','update','transfer')or action is null or jsonb_typeof(payload)is distinct from'object'then raise exception 'طلب غير صحيح'using errcode='22023';end if;
 if action='get'then return solar_private.cash_record_context(movement_id);end if;
 if request_id is null then raise exception 'رقم طلب الحفظ مطلوب'using errcode='22023';end if;
 perform pg_advisory_xact_lock(7311,1);
 if action='transfer'then
  if not p.is_admin then raise exception 'التسليم المباشر للإدارة فقط'using errcode='42501';end if;
 else
  ctx:=solar_private.cash_record_context(movement_id);
  if not coalesce((ctx->>'canEdit')::boolean,false)then raise exception 'عدّل هذه الحركة من قسمها المختص أو راجع الإدارة'using errcode='42501';end if;
 end if;
 select * into prior from solar_private.finance_requests where finance_requests.request_id=cash_record.request_id;
 if prior.request_id is not null then
  if prior.actor_id<>p.id or prior.action<>(case when action='transfer'then'admin_cash_transfer'else'cash_record_update'end) or prior.payload<>(payload||jsonb_build_object('_movementId',movement_id))then raise exception 'طلب مكرر ببيانات مختلفة'using errcode='PT409';end if;
  return prior.response;
 end if;
 amount:=(payload->>'amount')::numeric;note:=trim(coalesce(payload->>'note',''));
 if amount is null or amount::text in('NaN','Infinity','-Infinity')or amount<=0 or amount>1e12 or round(amount,2)<>amount or note=''or length(note)>2000 then raise exception 'أدخل مبلغًا موجبًا وبيانًا للحركة لا يتجاوز 2000 حرف'using errcode='22023';end if;
 if action='update'and payload->>'expectedToken'is distinct from ctx->>'token'then raise exception 'تغيّرت الحركة أو الأرصدة؛ حمّل آخر نسخة قبل التعديل'using errcode='PT409';end if;
 if action='transfer'then
  uid:=(payload->>'senderId')::uuid;recipient:=(payload->>'recipientId')::uuid;
  if uid is null or recipient is null or uid=recipient or(select count(*)from public.profiles where id in(uid,recipient)and active and user_type not in('installer','warehouse'))<>2 then raise exception 'اختر قاصتين مختلفتين لمستخدمين إداريين فعالين'using errcode='42501';end if;
  if payload->>'currency'not in('IQD','USD')or payload->>'currency'is null then raise exception 'اختر عملة صحيحة'using errcode='22023';end if;
  wallet:=solar_private.usd_wallet(uid);other_wallet:=solar_private.usd_wallet(recipient);
  before_iqd:=solar_private.cash_balance(uid);before_usd:=(wallet->>'amount')::numeric;before_other_iqd:=solar_private.cash_balance(recipient);before_other_usd:=(other_wallet->>'amount')::numeric;
  if payload->>'currency'='USD'then
   if amount>before_usd then raise exception 'رصيد الدولار لا يكفي للتسليم'using errcode='P0002';end if;
   book:=case when amount=before_usd then(wallet->>'book')::numeric else round(amount*(wallet->>'book')::numeric/nullif(before_usd,0),2)end;
   rate:=book/amount;
  else book:=amount;rate:=1;end if;
  insert into solar_private.receipt_counters(kind,last_number)values('cash_direct_transfer',1)on conflict(kind)do update set last_number=solar_private.receipt_counters.last_number+1 returning last_number into number;
  result:=jsonb_build_object('type','transfer','transferId',request_id,'receiptNo',number,'date',now(),'senderId',uid,'recipientId',recipient,'amount',amount,'currency',payload->>'currency','note',note,
   'senderName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=uid),'recipientName',(select solar_private.user_name(display_name,username,honorific)from public.profiles where id=recipient),
   'actorName',solar_private.user_name(p.display_name,p.username,p.honorific),'beforeIQD',before_iqd,'beforeUSD',before_usd,'beforeRecipientIQD',before_other_iqd,'beforeRecipientUSD',before_other_usd);
  insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,p.id,'admin_cash_transfer',payload||jsonb_build_object('_movementId',movement_id),result);
  insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note,finance_request_id)values
   (uid,payload->>'currency',-amount,-book,rate,0,'admin_transfer_out',note,request_id),
   (recipient,payload->>'currency',amount,book,rate,0,'admin_transfer_in',note,request_id);
  result:=result||jsonb_build_object('afterIQD',solar_private.cash_balance(uid),'afterUSD',(solar_private.usd_wallet(uid)->>'amount')::numeric,'afterRecipientIQD',solar_private.cash_balance(recipient),'afterRecipientUSD',(solar_private.usd_wallet(recipient)->>'amount')::numeric);
  update solar_private.finance_requests set response=result where finance_requests.request_id=cash_record.request_id;

  return result;
 end if;
 original:=ctx;
 if ctx->>'type'='cash'then
  select * into t from public.transactions where id=(ctx->>'id')::bigint for update;
  uid:=coalesce(t.cashbox_user_id,t.created_by);sign:=case when t.kind in('cash_expense','profit_distribution')then -1 else 1 end;
  rate:=case when t.cash_currency='USD'then solar_private.fx_rate((payload->>'rate')::numeric,t.market_rate)else 1 end;
  if t.cash_currency='USD'and rate is distinct from t.market_rate and not(p.is_admin or p.permissions->>'exchangeRateEdit'='true')then raise exception 'تعديل الصرف يحتاج صلاحية'using errcode='42501';end if;
  if t.kind='profit_distribution'and amount>greatest(0,solar_private.retained_profit(uid)+t.total)then raise exception 'المبلغ يتجاوز الأرباح المتاحة';end if;
  select * into w from solar_private.wallet_fx_entries where transaction_id=t.id for update;
  if t.cash_currency='USD'then
   book:=case when sign>0 then round(amount*rate,2)else round(abs(w.book_delta)*amount/nullif(abs(w.delta),0),2)end;
   wallet:=solar_private.usd_wallet(uid);
   if(wallet->>'amount')::numeric-w.delta+sign*amount<0 or(wallet->>'book')::numeric-w.book_delta+sign*book<0 then raise exception 'التعديل يجعل رصيد الدولار أو كلفته سالبًا؛ راجع حركات الدولار اللاحقة'using errcode='P0002';end if;
   gain:=case when sign<0 and t.cash_purpose='expense'then round(amount*rate,2)-book else 0 end;
   update solar_private.wallet_fx_entries set delta=sign*amount,book_delta=sign*book,rate=rate,gain=gain,note=note where id=w.id;
  end if;
  update public.transactions set total=round(amount*rate,2),cash_amount=amount,source_subtotal=amount,exchange_rate=rate,market_rate=rate,notes=note where id=t.id;
  select to_jsonb(x)into result from public.transactions x where id=t.id;
  insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)values(request_id,p.id,t.id,'cash_record_update',to_jsonb(t),result);
  if t.finance_request_id is not null then
   new_rows:=solar_private.cash_movement_detail_v386('tx:'||t.id);
   update solar_private.finance_requests set response=response||jsonb_build_object('amount',amount,'note',note,'rate',rate,'profitAmountIQD',case when t.cash_purpose='external_profit'then round(amount*rate,2)else null end)||case when t.cash_currency='USD'then jsonb_build_object('beforeUSD',new_rows->'before','afterUSD',new_rows->'after')else jsonb_build_object('beforeIQD',new_rows->'before','afterIQD',new_rows->'after')end
   where finance_requests.request_id=t.finance_request_id and finance_requests.action='cash';
  end if;
 elsif ctx->>'type'='transfer'then
  transfer_id:=(ctx->>'transferId')::uuid;
  select * into prior from solar_private.finance_requests where finance_requests.request_id=transfer_id and finance_requests.action='admin_cash_transfer'for update;
  uid:=(ctx->>'senderId')::uuid;recipient:=(ctx->>'recipientId')::uuid;
  select coalesce(jsonb_agg(to_jsonb(e)order by id),'[]')into old_rows from solar_private.wallet_fx_entries e where e.finance_request_id=transfer_id;
  select * into w from solar_private.wallet_fx_entries where finance_request_id=transfer_id and entry_type='admin_transfer_out'for update;
  book:=round(abs(w.book_delta)*amount/nullif(abs(w.delta),0),2);
  if w.currency='USD'then
   wallet:=solar_private.usd_wallet(uid);other_wallet:=solar_private.usd_wallet(recipient);
   if(wallet->>'amount')::numeric+abs(w.delta)-amount<0 or(wallet->>'book')::numeric+abs(w.book_delta)-book<0 or(other_wallet->>'amount')::numeric-abs(w.delta)+amount<0 or(other_wallet->>'book')::numeric-abs(w.book_delta)+book<0 then raise exception 'التعديل لا يكفيه رصيد الدولار لدى إحدى القاصتين'using errcode='P0002';end if;
  end if;
  update solar_private.wallet_fx_entries set delta=case when entry_type='admin_transfer_out'then -amount else amount end,book_delta=case when entry_type='admin_transfer_out'then -book else book end,note=note where finance_request_id=transfer_id;
  select solar_private.cash_movement_detail_v386('fx:'||e.id)into new_rows from solar_private.wallet_fx_entries e where e.finance_request_id=transfer_id and e.owner_id=uid;
  select solar_private.cash_movement_detail_v386('fx:'||e.id)into destination from solar_private.wallet_fx_entries e where e.finance_request_id=transfer_id and e.owner_id=recipient;
  result:=prior.response||jsonb_build_object('amount',amount,'note',note)||case when w.currency='USD'then jsonb_build_object('beforeUSD',new_rows->'before','afterUSD',new_rows->'after','beforeRecipientUSD',destination->'before','afterRecipientUSD',destination->'after')else jsonb_build_object('beforeIQD',new_rows->'before','afterIQD',new_rows->'after','beforeRecipientIQD',destination->'before','afterRecipientIQD',destination->'after')end;
  update solar_private.finance_requests set response=result where finance_requests.request_id=transfer_id;
  select coalesce(jsonb_agg(to_jsonb(e)order by id),'[]')into new_rows from solar_private.wallet_fx_entries e where e.finance_request_id=transfer_id;
  original:=original||jsonb_build_object('entries',old_rows);result:=result||jsonb_build_object('entries',new_rows);
 elsif ctx->>'type'='settlement'then
  select * into r from solar_private.profit_settlements where id=(ctx->>'id')::uuid for update;
  if round(amount)<>amount or amount>r.profit then raise exception 'حصة المستخدم بالدينار الصحيح ولا تتجاوز ربح التسوية'using errcode='22023';end if;
  select * into t from public.transactions where profit_settlement_id=r.id for update;
  remaining:=r.profit-amount;old_supplier_receipt:=r.supplier_receipt;
  if remaining>0 then
   select * into supplier from public.suppliers where id=(payload->>'supplierId')::bigint and active for update;
   select value into destination from jsonb_array_elements(solar_private.profit_supplier_accounts())where(value->>'id')::bigint=supplier.id;
   if supplier.id is null or payload->>'supplierToken'is distinct from destination->>'token'then raise exception 'تغيّر حساب المورد؛ حدّث المعاينة واختر المورد'using errcode='PT409';end if;
   rate:=case when supplier.id=r.supplier_id and supplier.account_currency=r.supplier_currency then r.supplier_rate else(destination->>'rate')::numeric end;
   if supplier.account_currency='USD'and round(remaining/rate,2)<=0 then raise exception 'المبلغ أصغر من سنت؛ راجع حصة المستخدم';end if;
  end if;
  select * into old_charge from public.transactions where id=(old_supplier_receipt->>'id')::bigint and supplier_payment_voided_at is null;
  charge_changed:=remaining is distinct from coalesce(r.supplier_amount_iqd,0)or(remaining>0 and(supplier.id is distinct from r.supplier_id or supplier.account_currency is distinct from r.supplier_currency));
  if charge_changed and old_charge.id is not null then
   -- The approved allocation owns its supplier correction. Independent edits
   -- stay blocked; the existing reversal engine keeps the supplier ledger exact.
   perform set_config('solar.fx_context',jsonb_build_object('marketRate',old_charge.market_rate,'accountRevision',old_charge.account_revision,'cashCurrency',old_charge.cash_currency)::text,true);
   update public.transactions set profit_supplier_settlement_id=null,profit_supplier_owner_id=null where id=old_charge.id;
   perform set_config('solar.fx_context','',true);
   old_context:=solar_private.supplier_payment_manage('get',null,jsonb_build_object('id',old_charge.id));
   perform solar_private.supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',old_charge.id,'expectedToken',old_context->>'token','notes','تصحيح توزيع تسوية الأرباح'));
  end if;
  if charge_changed and remaining>0 then
   addition:=solar_private.fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',solar_private.next_transaction_id(),'supplierId',supplier.id,'amount',remaining,'currency','IQD','rate',rate,'accountRevision',supplier.currency_revision,'mode','charge_other','note','بقية أرباح '||(ctx->>'ownerName')||' بعد تعديل التسوية'));
   perform set_config('solar.fx_context',jsonb_build_object('marketRate',rate,'accountRevision',supplier.currency_revision,'cashCurrency','IQD')::text,true);
   update public.transactions set profit_supplier_settlement_id=r.id,profit_supplier_owner_id=r.owner_id where id=(addition->>'id')::bigint;
   perform set_config('solar.fx_context','',true);
  end if;
  update public.transactions set total=amount,cash_amount=amount,source_subtotal=amount,notes='حصة أرباح '||(ctx->>'ownerName')||' · '||note where id=t.id;
  result:=solar_private.cash_movement_detail('tx:'||t.id);
  update solar_private.profit_settlements set share=amount,decision_note=note,receipt=r.receipt||jsonb_build_object('amount',amount,'beforeIQD',result->'before','afterIQD',result->'after'),
   supplier_id=case when remaining>0 then supplier.id end,supplier_amount_iqd=remaining,supplier_currency=case when remaining>0 then supplier.account_currency end,supplier_amount=case when not charge_changed then r.supplier_amount when remaining>0 then abs((addition->>'accountAmount')::numeric)else 0 end,supplier_rate=coalesce(rate,1),
   supplier_receipt=case when not charge_changed then r.supplier_receipt when remaining>0 then jsonb_build_object('id',addition->'id','receiptNo',addition->'receiptNo','name',supplier.name,'currency',supplier.account_currency,'amount',abs((addition->>'accountAmount')::numeric),'beforeBalance',(addition->'accountContext'->>'balance')::numeric-abs((addition->>'accountAmount')::numeric),'afterBalance',(addition->'accountContext'->>'balance')::numeric,'amountIQD',remaining,'rate',rate)end where id=r.id returning to_jsonb(profit_settlements.*)into result;
  update solar_private.finance_requests set response=result where finance_requests.action='profit_approve'and finance_requests.payload->>'id'=r.id::text;
  insert into solar_private.receipt_change_audit(request_id,actor_id,transaction_id,action,before_row,after_row)values(request_id,p.id,t.id,'profit_allocation_update',jsonb_build_object('settlement',to_jsonb(r),'expense',to_jsonb(t),'supplier',to_jsonb(old_charge)),result);
  perform solar_private.profit_notice(r.owner_id,'profit_decided','تم تعديل تسوية أرباحك','حصة المستخدم بعد التعديل: '||amount::text||' د.ع · '||note);
 else raise exception 'هذه الحركة غير قابلة للتعديل من القاصة'using errcode='42501';end if;
 result:=jsonb_build_object('saved',true,'type',ctx->>'type','before',original,'after',result);
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)values(request_id,p.id,'cash_record_update',payload||jsonb_build_object('_movementId',movement_id),result);
 return result;
end$$;
create function public.solar_cash_record(action text,movement_id text default null,request_id uuid default null,payload jsonb default '{}')returns jsonb
language sql security invoker set search_path=''as $$select solar_private.cash_record(action,movement_id,request_id,payload)$$;
revoke all on function solar_private.cash_record(text,text,uuid,jsonb),public.solar_cash_record(text,text,uuid,jsonb)from public,anon;
grant execute on function solar_private.cash_record(text,text,uuid,jsonb),public.solar_cash_record(text,text,uuid,jsonb)to authenticated;

-- Cash details advertise editing only when the server's exact scope allows it.
alter function solar_private.cash_movement_detail(text)rename to cash_movement_detail_v386;
revoke all on function solar_private.cash_movement_detail_v386(text)from public,anon,authenticated;
create function solar_private.cash_movement_detail(movement_id text)returns jsonb language plpgsql stable security definer set search_path=''as $$
declare result jsonb;e solar_private.wallet_fx_entries;fr solar_private.finance_requests;
begin
 result:=solar_private.cash_movement_detail_v386(movement_id);
 if movement_id~'^fx:[0-9]+$'then
  select * into e from solar_private.wallet_fx_entries where id=substr(movement_id,4)::bigint;
  select * into fr from solar_private.finance_requests where request_id=e.finance_request_id and action='admin_cash_transfer';
  if fr.request_id is not null then result:=result||jsonb_build_object('transfer',jsonb_build_object('sender',fr.response->>'senderName','recipient',fr.response->>'recipientName','amount',fr.response->'amount','currency',e.currency,'status','accepted','note',fr.response->>'note','decidedBy',fr.response->>'actorName','decidedAt',fr.created_at));end if;
 end if;
 return result||jsonb_build_object('edit',solar_private.cash_record_context(movement_id,false));
end$$;
revoke all on function solar_private.cash_movement_detail(text)from public,anon;
grant execute on function solar_private.cash_movement_detail(text)to authenticated;

-- The source/destination name is part of every on-screen and exported ledger.
do $$declare definition text;needle text;begin
 definition:=pg_get_functiondef('solar_private.cash_movements()'::regprocedure);
 needle:=$n$e.entry_type,'',e.note,$n$;
 if strpos(definition,needle)=0 then raise exception 'Cash wallet party projection contract missing';end if;
 execute replace(definition,needle,$n$e.entry_type,case when fr.action='admin_cash_transfer' then case when e.entry_type='admin_transfer_out' then 'إلى '||coalesce(fr.response->>'recipientName','') else 'من '||coalesce(fr.response->>'senderName','') end else '' end,e.note,$n$);
end$$;
notify pgrst,'reload schema';
