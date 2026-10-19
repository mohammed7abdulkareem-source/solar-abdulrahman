\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003580','مدير التوزيع','allocation_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003581','مستحق الأرباح','allocation_owner',false,'admin_staff','{"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003582','صاحب طلب الدولار','allocation_usd',false,'admin_staff','{"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003583','مستخدم آخر','allocation_other',false,'admin_staff','{"profit":true}');
insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values('https://fcm.googleapis.com/fcm/send/allocation-admin','00000000-0000-0000-0000-000000003580','local-test-key','local-test-auth'),('https://fcm.googleapis.com/fcm/send/allocation-owner','00000000-0000-0000-0000-000000003581','local-test-key','local-test-auth');
insert into suppliers(id,name,account_currency) values(-358001,'مورد التوزيع دينار','IQD'),(-358002,'مورد التوزيع دولار','USD');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id) values
(-358001,'sale',2000000,2000000,2000000,true,false,'credit','00000000-0000-0000-0000-000000003581','00000000-0000-0000-0000-000000003581'),
(-358002,'sale',2000000,2000000,2000000,true,false,'credit','00000000-0000-0000-0000-000000003582','00000000-0000-0000-0000-000000003582');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003580',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_fx('payment',gen_random_uuid(),'{"paymentId":-358003,"supplierId":-358001,"amount":2000000,"currency":"IQD","rate":1660,"accountRevision":0,"mode":"charge_old_balance","note":"رصيد المورد السابق"}');
set local role authenticated;
do $$declare c jsonb;r jsonb;request uuid:=gen_random_uuid();decision uuid:=gen_random_uuid();b jsonb;d jsonb;s jsonb;result jsonb;entry bigint;capital_before numeric;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003581',true);
 c:=public.solar_profit_workspace('overview');
 if(c->>'available')::numeric<>2000000 then raise exception 'period profit';end if;
 if c->'suppliers'<>'[]'::jsonb then raise exception 'supplier data leaked to user';end if;
 r:=public.solar_profit_workspace('request',request,jsonb_build_object('expectedToken',c->>'token'));
 perform set_config('test.allocation.request',request::text,true);
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',request));raise exception 'staff approval accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003580',true);
 c:=public.solar_profit_workspace('overview');select value into d from jsonb_array_elements(c->'requests') where value->>'id'=request::text;
 select value into s from jsonb_array_elements(c->'suppliers') where(value->>'id')::bigint=-358001;
 b:=jsonb_build_object('id',request,'expectedToken',d->>'token','share',500000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-358001,'supplierToken',s->>'token','supplierRate',s->'rate');
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b||'{"cashOwnerId":"00000000-0000-0000-0000-000000003580"}');raise exception 'wrong cash owner accepted';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),b||'{"supplierToken":"stale"}');raise exception 'stale supplier accepted';exception when sqlstate 'PT409' then null;end;
 capital_before:=(public.solar_capital_snapshot()->>'net')::numeric;
 result:=public.solar_profit_workspace('approve',decision,b);
 if capital_before-(public.solar_capital_snapshot()->>'net')::numeric<>2000000 then raise exception 'capital excess did not drop by the whole profit split';end if;
 if(result->'receipt'->>'beforeIQD')::numeric<>0 or(result->'receipt'->>'afterIQD')::numeric<>-500000 then raise exception 'entitlement did not debit zero cashbox %',result;end if;
 if(result->>'supplier_amount_iqd')::numeric<>1500000 or(result->'supplier_receipt'->>'beforeBalance')::numeric<>2000000 or(result->'supplier_receipt'->>'afterBalance')::numeric<>3500000 then raise exception 'wrong supplier increase %',result;end if;
 if public.solar_profit_workspace('approve',decision,b)<>result then raise exception 'approval replay changed response';end if;
 entry:=(result->'supplier_receipt'->>'id')::bigint;
 begin perform public.solar_supplier_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',entry));raise exception 'linked supplier charge deleted';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('payment',gen_random_uuid(),jsonb_build_object('paymentId',entry,'supplierId',-358001,'amount',1,'currency','IQD','rate',1660,'mode','charge_other','accountRevision',0,'note','tamper'));raise exception 'linked charge overwritten';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003581',true);
 c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>0 then raise exception 'period did not close';end if;
 select value into d from jsonb_array_elements(c->'requests') where value->>'id'=request::text;
 if d->'supplier_receipt'?'afterBalance' or d->'supplier_receipt'?'beforeBalance' then raise exception 'company supplier balances leaked to staff settlement';end if;
 begin perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003581","mode":"expense","currency":"IQD","amount":1,"note":"ordinary expense"}');raise exception 'ordinary expense permission changed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003583',true);
 c:=public.solar_profit_workspace('overview');if c->'requests'<>'[]'::jsonb then raise exception 'other user settlement leak';end if;
end$$;
reset role;
do $$begin
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003581')<>-500000 then raise exception 'cash debit';end if;
 if solar_private.retained_profit('00000000-0000-0000-0000-000000003581')<>0 then raise exception 'supplier allocation remained withdrawable twice';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003580')<>0 then raise exception 'admin cash changed';end if;
 if(select count(*) from transactions where profit_settlement_id=current_setting('test.allocation.request')::uuid)<>1 or(select count(*) from transactions where profit_supplier_settlement_id=current_setting('test.allocation.request')::uuid)<>1 then raise exception 'posting duplicated';end if;
 if exists(select 1 from transactions where profit_supplier_settlement_id=current_setting('test.allocation.request')::uuid and(cash or total<>-1500000 or cash_amount<>0)) then raise exception 'supplier charge incorrectly paid';end if;
 if(select sum(book_delta) from solar_private.supplier_fx_entries where supplier_id=-358001)<>3500000 then raise exception 'base supplier value incorrect';end if;
 if(select count(*) from solar_private.push_deliveries d join solar_notifications n on n.id=d.notification_id where n.user_id in('00000000-0000-0000-0000-000000003580','00000000-0000-0000-0000-000000003581') and n.event in('profit_requested','profit_decided'))<>2 then raise exception 'mobile push outbox missing or duplicated';end if;
 if not exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000003580' and event='profit_requested' and body like '%مستحق الأرباح%') then raise exception 'admin request notification missing';end if;
 if not exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000003581' and event='profit_decided' and body like '%-500000%') then raise exception 'owner decision missing';end if;
end$$;
-- Currency of the supplier account is respected while its IQD book value is exact.
set local role authenticated;
do $$declare c jsonb;r jsonb;d jsonb;s jsonb;b jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003582',true);c:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003580',true);c:=public.solar_profit_workspace('overview');select value into d from jsonb_array_elements(c->'requests') where value->>'id'=r->>'id';select value into s from jsonb_array_elements(c->'suppliers') where(value->>'id')::bigint=-358002;
 b:=jsonb_build_object('id',r->>'id','expectedToken',d->>'token','share',500000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-358002,'supplierToken',s->>'token','supplierRate',s->'rate');
 r:=public.solar_profit_workspace('approve',gen_random_uuid(),b);
 if r->>'supplier_currency'<>'USD' or(r->>'supplier_amount')::numeric<>round(1500000/(s->>'rate')::numeric,2) then raise exception 'USD allocation wrong %',r;end if;
end$$;
reset role;
do $$begin if(select sum(book_delta) from solar_private.supplier_fx_entries where supplier_id=-358002)<>1500000 then raise exception 'USD book value wrong';end if;raise notice 'PASS zero-cash request, negative entitlement debit, supplier debt increase without cash, exact IQD book value and USD conversion, atomic replay, protected linked charges, scopes and notifications';end$$;
rollback;
