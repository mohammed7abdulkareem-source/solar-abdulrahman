\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003620','إدارة التفاصيل',true,'admin_staff','07700003620','{}'),
('00000000-0000-0000-0000-000000003621','صاحب الحركة',false,'admin_staff','07700003621','{"cash":true,"cashExternalProfit":true,"cashDeposit":true,"cashExchange":true,"cashTransferSend":true,"sale":true,"suppliers":true,"supplierPayment":true,"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003622','صاحب القاصة الثانية',false,'admin_staff','07700003622','{"cash":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000003623','مخزن بصلاحية قديمة',true,'warehouse','07700003623','{"cash":true}'),
('00000000-0000-0000-0000-000000003624','مهندس بصلاحية قديمة',true,'installer','07700003624','{"cash":true}');
insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values('https://fcm.googleapis.com/fcm/send/decision-owner','00000000-0000-0000-0000-000000003621','local-test-key','local-test-auth');
insert into products(id,code,name,qty,cost) values(-362001,'CASH-DETAIL','انفيرتر تفاصيل الحركة',10,1000);
insert into customers(id,name,customer_type,owner_id) values(-362001,'زبون تفاصيل الصندوق','wholesale','00000000-0000-0000-0000-000000003621');
insert into suppliers(id,name,account_currency) values(-362001,'مورد تفاصيل الصندوق','IQD');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003620',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_cash_save('00000000-0000-0000-0000-000000036200','{"ownerId":"00000000-0000-0000-0000-000000003621","mode":"deposit","currency":"IQD","amount":2000000,"note":"رصيد اختبار التفاصيل"}');
select public.solar_cash_save('00000000-0000-0000-0000-000000036201','{"ownerId":"00000000-0000-0000-0000-000000003622","mode":"deposit","currency":"IQD","amount":100000,"note":"قاصة مستقلة"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
select public.solar_cash_save('00000000-0000-0000-0000-000000036202','{"ownerId":"00000000-0000-0000-0000-000000003621","mode":"external_profit","currency":"IQD","amount":20000,"note":"ربح خارجي <خاص>"}');
select public.solar_cash_save('00000000-0000-0000-0000-000000036203','{"ownerId":"00000000-0000-0000-0000-000000003621","mode":"buy_usd","currency":"USD","amount":10,"rate":1660,"note":"شراء دولار للتفاصيل"}');
select public.solar_invoice_save('00000000-0000-0000-0000-000000036204','{"kind":"sale","party":"زبون تفاصيل الصندوق","partyId":-362001,"mode":"cash","warehouseId":1,"items":[{"id":-362001,"qty":1,"price":10000}]}');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000036205','00000000-0000-0000-0000-000000003622',3000,0,'','تسليم المكتب');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003622',true);
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000036205','accepted');
reset role;
do $$declare r jsonb;row jsonb;own_id text;other_id text;c jsonb;request jsonb;decision jsonb;payload jsonb;attempt uuid:=gen_random_uuid();cash_before numeric;profit_before numeric;tx_count bigint;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
 c:=public.solar_cash_workspace();
 for row in select value from jsonb_array_elements(c->'rows') loop
  r:=public.solar_cash_movement_detail(row->>'id');
  if r->>'ownerId'<>'00000000-0000-0000-0000-000000003621' or(r->>'after')::numeric-(r->>'before')::numeric<>(r->>'delta')::numeric then raise exception 'movement owner or balances wrong %',r;end if;
  if r->>'kind'='external_profit' then own_id:=r->>'id';if r->>'note'<>'ربح خارجي <خاص>' or r->>'actorName'<>'صاحب الحركة' then raise exception 'external note/actor missing';end if;end if;
  if r->>'kind'='sale' then
   if jsonb_array_length(r->'items')<>1 or r->'items'->0->>'name'<>'انفيرتر تفاصيل الحركة' or(r->'items'->0->>'price')::numeric<>10000 or r->'document'->>'receiptNo' is null then raise exception 'sale item details lost %',r;end if;
   if r->'items'->0 ? 'cost' or r ? 'invoiceAccount' then raise exception 'unnecessary financial details exposed';end if;
  end if;
  if r->>'kind'='transfer_out' and(r->'transfer'->>'recipient'<>'صاحب القاصة الثانية' or r->'transfer'->>'status'<>'accepted') then raise exception 'handover details lost %',r;end if;
  if row->>'request_id'='00000000-0000-0000-0000-000000036203' and r->'exchange'='null'::jsonb then raise exception 'exchange details missing %',r;end if;
 end loop;
 perform set_config('test.cash.ownId',own_id,true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003622',true);
 c:=public.solar_cash_workspace();other_id:=c->'rows'->0->>'id';perform set_config('test.cash.otherId',other_id,true);
 begin perform public.solar_cash_movement_detail(own_id);raise exception 'other user cash detail leaked';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
 c:=public.solar_profit_workspace('overview');profit_before:=(c->>'available')::numeric;cash_before:=solar_private.cash_balance(auth.uid());select count(*) into tx_count from transactions;
 request:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token','note','طلب للمراجعة'));
 begin perform public.solar_profit_workspace('reject',gen_random_uuid(),jsonb_build_object('id',request->>'id','note','غير مسموح'));raise exception 'user rejected own profit request';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003620',true);
 c:=public.solar_profit_workspace('overview');select value into request from jsonb_array_elements(c->'requests') where value->>'id'=request->>'id';
 begin perform public.solar_profit_workspace('reject',gen_random_uuid(),jsonb_build_object('id',request->>'id','expectedToken',request->>'token','note',''));raise exception 'empty rejection reason accepted';exception when raise_exception then if sqlerrm<>'اكتب سبب رفض الطلب' then raise;end if;end;
 payload:=jsonb_build_object('id',request->>'id','expectedToken',request->>'token','note','بانتظار تدقيق التحصيل');
 decision:=public.solar_profit_workspace('reject',attempt,payload);
 if decision->>'status'<>'rejected' or decision->>'decision_note'<>'بانتظار تدقيق التحصيل' then raise exception 'rejection not stored';end if;
 if public.solar_profit_workspace('reject',attempt,payload)<>decision then raise exception 'decision retry duplicated or differed';end if;
 if(select count(*) from transactions)<>tx_count then raise exception 'rejection posted a financial movement';end if;
 if(select count(*) from solar_private.profit_checkpoints where owner_id='00000000-0000-0000-0000-000000003621')<>0 then raise exception 'rejection settled profits';end if;
 if(select count(*) from solar_notifications where user_id='00000000-0000-0000-0000-000000003621' and event='profit_decided' and body='بانتظار تدقيق التحصيل')<>1 then raise exception 'decision notice missing/duplicated';end if;
 if(select count(*) from solar_private.push_deliveries d join solar_notifications n on n.id=d.notification_id where n.event='profit_decided' and n.body='بانتظار تدقيق التحصيل')<>1 then raise exception 'rejection mobile push missing/duplicated';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
 c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>profit_before or solar_private.cash_balance(auth.uid())<>cash_before then raise exception 'rejection changed cash or entitlement';end if;
 perform public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));
end$$;
-- Existing reset receipts provide markers, including per-owner snapshots of a bulk reset.
do $$declare c jsonb;r jsonb;row jsonb;first_id uuid:=gen_random_uuid();second_id uuid:=gen_random_uuid();begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003620',true);
 c:=public.solar_cash_reconcile('context');
 perform public.solar_cash_reconcile('apply',first_id,jsonb_build_object('mode','zero','currency','both','target',0,'note','تصفير نهاية الفترة الأولى','expectedToken',c->>'token'));
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003621","mode":"deposit","currency":"IQD","amount":5000,"note":"فترة ثانية"}');
 c:=public.solar_cash_reconcile('context',null,'{"ownerId":"00000000-0000-0000-0000-000000003621"}');
 perform public.solar_cash_reconcile('apply',second_id,jsonb_build_object('ownerId','00000000-0000-0000-0000-000000003621','mode','set','currency','IQD','target',0,'note','تصفير نهاية الفترة الثانية','expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
 c:=public.solar_cash_workspace();
 if(select count(distinct x->'reconciliation'->>'id') from jsonb_array_elements(c->'rows') x where x->'reconciliation'->>'mode'='zero')<>2 then raise exception 'reset markers missing';end if;
 for row in select value from jsonb_array_elements(c->'rows') where value->>'kind'='cash_reconcile' loop
  if row->'reconciliation'->>'ownerId'<>auth.uid()::text or row->'reconciliation'->>'mode'<>'zero' then raise exception 'bulk reset leaked another cashbox';end if;
  r:=public.solar_cash_movement_detail(row->>'id');
  if r->'reconciliation'<>row->'reconciliation' then raise exception 'detail and marker snapshots differ';end if;
  if(r->>'after')::numeric<>(r->'reconciliation'->>('after'||(r->>'currency')))::numeric then raise exception 'detail ignored recorded reset balance';end if;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003623',true);
 begin perform public.solar_cash_movement_detail(current_setting('test.cash.ownId'));raise exception 'warehouse old admin flag leaked cash';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003624',true);
 begin perform public.solar_cash_movement_detail(current_setting('test.cash.ownId'));raise exception 'installer old admin flag leaked cash';exception when insufficient_privilege then null;end;
end$$;
update profiles set permissions='{}' where id='00000000-0000-0000-0000-000000003621';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003621',true);
do $$begin
 begin perform public.solar_cash_movement_detail(current_setting('test.cash.ownId'));raise exception 'revoked view still read details';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_cash_movement_detail(text)','execute') or has_function_privilege('authenticated','solar_private.cash_reconciliation_info(uuid,uuid)','execute') then raise exception 'private detail helper or anonymous RPC exposed';end if;
 raise notice 'PASS every cash source, own-only details, transfer actors, items without cost, exchange, repeated/bulk reset snapshots, live role revocation, reject without share/supplier, notification replay and unchanged profit/cash on rejection';
end$$;
rollback;
