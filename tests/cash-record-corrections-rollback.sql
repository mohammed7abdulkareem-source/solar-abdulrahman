\set ON_ERROR_STOP on
begin;
create function pg_temp.test_transfer_movement(req uuid,uid uuid)returns text language sql security definer as $$select 'fx:'||id from solar_private.wallet_fx_entries where finance_request_id=req and owner_id=uid$$;
create function pg_temp.test_wallet(uid uuid)returns jsonb language sql security definer as $$select solar_private.usd_wallet(uid)$$;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003890','مدير التصحيح',true,'admin_staff','07700003890','{}'),
('00000000-0000-0000-0000-000000003891','صاحب النقد',false,'admin_staff','07700003891','{"cash":true,"cashDeposit":true,"cashExpense":true,"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003892','مستلم التسليم',false,'admin_staff','07700003892','{"cash":true,"profit":true,"profitSettlement":true}'),
('00000000-0000-0000-0000-000000003893','مهندس',true,'installer','07700003893','{}'),
('00000000-0000-0000-0000-000000003894','مخزن',true,'warehouse','07700003894','{}');
insert into suppliers(id,name,account_currency)values(-389001,'مورد التصحيح','IQD'),(-389002,'مورد دولار التصحيح','USD');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)values(-389001,'sale',2000000,2000000,2000000,true,false,'credit','00000000-0000-0000-0000-000000003892','00000000-0000-0000-0000-000000003892');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003890',true);
do $$declare r jsonb;begin
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003890","mode":"deposit","currency":"IQD","amount":1000000,"note":"رصيد المدير"}');
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003891","mode":"deposit","currency":"IQD","amount":5000,"note":"إيداع أولي"}');perform set_config('test.deposit',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003891","mode":"expense","currency":"IQD","amount":1000,"note":"أجور أولية"}');perform set_config('test.expense',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003891","mode":"deposit","currency":"USD","amount":100,"rate":1500,"note":"إيداع دولار"}');perform set_config('test.usd',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003891","mode":"expense","currency":"USD","amount":50,"rate":1500,"note":"أجور دولار"}');perform set_config('test.usdexpense',r->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003891',true);
do $$declare c jsonb;r jsonb;b jsonb;nonce uuid:=gen_random_uuid();begin
 c:=public.solar_cash_record('get','tx:'||current_setting('test.deposit'));
 b:=jsonb_build_object('amount',7000,'rate',1,'note','الإيداع الصحيح','expectedToken',c->>'token');
 r:=public.solar_cash_record('update','tx:'||current_setting('test.deposit'),nonce,b);
 if public.solar_cash_record('update','tx:'||current_setting('test.deposit'),nonce,b)<>r then raise exception 'Cash retry duplicated';end if;
 begin perform public.solar_cash_record('update','tx:'||current_setting('test.deposit'),gen_random_uuid(),b);raise exception 'FAIL stale deposit';exception when sqlstate 'PT409'then null;end;
 c:=public.solar_cash_record('get','tx:'||current_setting('test.expense'));
 perform public.solar_cash_record('update','tx:'||current_setting('test.expense'),gen_random_uuid(),jsonb_build_object('amount',8000,'rate',1,'note','أجور مصححة','expectedToken',c->>'token'));
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003891')<>-1000 then raise exception 'IQD correction or overdraft incorrect';end if;
 c:=public.solar_cash_record('get','tx:'||current_setting('test.usd'));
 perform public.solar_cash_record('update','tx:'||current_setting('test.usd'),gen_random_uuid(),jsonb_build_object('amount',120,'rate',1500,'note','إيداع دولار مصحح','expectedToken',c->>'token'));
 c:=public.solar_cash_record('get','tx:'||current_setting('test.usd'));
 begin perform public.solar_cash_record('update','tx:'||current_setting('test.usd'),gen_random_uuid(),jsonb_build_object('amount',120,'rate',1600,'note','صرف غير مخول','expectedToken',c->>'token'));raise exception 'FAIL rate permission';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_record('update','tx:'||current_setting('test.usd'),gen_random_uuid(),jsonb_build_object('amount',20,'rate',1500,'note','دولار غير كاف','expectedToken',c->>'token'));raise exception 'FAIL dollar negative';exception when sqlstate 'P0002'then null;end;
 c:=public.solar_cash_record('get','tx:'||current_setting('test.usdexpense'));
 perform public.solar_cash_record('update','tx:'||current_setting('test.usdexpense'),gen_random_uuid(),jsonb_build_object('amount',60,'rate',1500,'note','أجور دولار مصححة','expectedToken',c->>'token'));
 if(pg_temp.test_wallet('00000000-0000-0000-0000-000000003891')->>'amount')::numeric<>60 or(pg_temp.test_wallet('00000000-0000-0000-0000-000000003891')->>'book')::numeric<>90000 then raise exception 'USD correction basis incorrect';end if;
 begin perform public.solar_cash_record('transfer',null,gen_random_uuid(),'{"senderId":"00000000-0000-0000-0000-000000003891","recipientId":"00000000-0000-0000-0000-000000003892","amount":100,"currency":"IQD","note":"غير مخول"}');raise exception 'FAIL staff direct handover';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003890',true);
do $$declare r jsonb;c jsonb;nonce uuid:=gen_random_uuid();b jsonb;movement text;begin
 b:='{"senderId":"00000000-0000-0000-0000-000000003890","recipientId":"00000000-0000-0000-0000-000000003892","amount":500000,"currency":"IQD","note":"تسليم للمستخدم"}';
 r:=public.solar_cash_record('transfer',null,nonce,b);perform set_config('test.transfer',nonce::text,true);
 if public.solar_cash_record('transfer',null,nonce,b)<>r then raise exception 'Transfer replay changed';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003890')<>500000 or solar_private.cash_balance('00000000-0000-0000-0000-000000003892')<>500000 then raise exception 'Transfer not balanced';end if;
 movement:=pg_temp.test_transfer_movement(nonce,'00000000-0000-0000-0000-000000003890');perform set_config('test.transferMovement',movement,true);
 c:=public.solar_cash_record('get',movement);
 perform public.solar_cash_record('update',movement,gen_random_uuid(),jsonb_build_object('amount',300000,'note','التسليم المصحح','expectedToken',c->>'token'));
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003890')<>700000 or solar_private.cash_balance('00000000-0000-0000-0000-000000003892')<>300000 then raise exception 'Transfer correction not balanced';end if;
 r:=public.solar_cash_record('transfer',null,gen_random_uuid(),'{"senderId":"00000000-0000-0000-0000-000000003891","recipientId":"00000000-0000-0000-0000-000000003892","amount":10,"currency":"USD","note":"تسليم دولار"}');
 movement:=pg_temp.test_transfer_movement((r->>'transferId')::uuid,'00000000-0000-0000-0000-000000003891');
 c:=public.solar_cash_record('get',movement);perform public.solar_cash_record('update',movement,gen_random_uuid(),jsonb_build_object('amount',5,'note','تصحيح تسليم دولار','expectedToken',c->>'token'));
 if(pg_temp.test_wallet('00000000-0000-0000-0000-000000003891')->>'amount')::numeric<>55 or(pg_temp.test_wallet('00000000-0000-0000-0000-000000003892')->>'amount')::numeric<>5 then raise exception 'USD transfer amount incorrect';end if;
 if(pg_temp.test_wallet('00000000-0000-0000-0000-000000003891')->>'book')::numeric+(pg_temp.test_wallet('00000000-0000-0000-0000-000000003892')->>'book')::numeric<>90000 then raise exception 'USD transfer created or lost basis';end if;
end$$;
-- Approve and then revise the allocation, not the already-reviewed profit.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003892',true);
do $$declare c jsonb;r jsonb;d jsonb;s jsonb;begin
 c:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));perform set_config('test.settlement',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003890',true);
 c:=public.solar_profit_workspace('overview');select value into d from jsonb_array_elements(c->'requests')where value->>'id'=current_setting('test.settlement');select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-389001;
 r:=public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',d->>'id','expectedToken',d->>'token','share',500000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-389001,'supplierToken',s->>'token','supplierRate',s->'rate'));
 perform set_config('test.settlementCash',r->'receipt'->>'id',true);
end$$;
do $$declare c jsonb;r jsonb;s jsonb;b jsonb;nonce uuid:=gen_random_uuid();begin
 c:=public.solar_cash_record('get','profit:'||current_setting('test.settlement'));select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-389001;
 b:=jsonb_build_object('amount',750000,'note','الحصة المصححة','supplierId',-389001,'supplierToken',s->>'token','expectedToken',c->>'token');
 r:=public.solar_cash_record('update','profit:'||current_setting('test.settlement'),nonce,b);
 if public.solar_cash_record('update','profit:'||current_setting('test.settlement'),nonce,b)<>r then raise exception 'Settlement edit retry duplicated';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003892')<>-450000 then raise exception 'Settlement cash share difference incorrect';end if;
 select value into s from jsonb_array_elements((public.solar_profit_workspace('overview')->'suppliers'))where(value->>'id')::bigint=-389001;
 if(s->>'balance')::numeric<>1250000 then raise exception 'Supplier remainder was counted twice %',s;end if;
 c:=public.solar_cash_record('get','profit:'||current_setting('test.settlement'));
 perform public.solar_cash_record('update','profit:'||current_setting('test.settlement'),gen_random_uuid(),jsonb_build_object('amount',2000000,'note','كل الربح للمستخدم','expectedToken',c->>'token'));
 select value into s from jsonb_array_elements((public.solar_profit_workspace('overview')->'suppliers'))where(value->>'id')::bigint=-389001;
 if(s->>'balance')::numeric<>0 then raise exception 'Zero supplier allocation not reversed';end if;
 c:=public.solar_cash_record('get','profit:'||current_setting('test.settlement'));select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-389002;
 perform public.solar_cash_record('update','profit:'||current_setting('test.settlement'),gen_random_uuid(),jsonb_build_object('amount',1000000,'note','إعادة توزيع على مورد دولار','supplierId',-389002,'supplierToken',s->>'token','expectedToken',c->>'token'));
end$$;
-- A failure after reversing the supplier must roll back every financial leg.
reset role;
create function pg_temp.record_fingerprint()returns text language sql as $$select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'supplier',(select jsonb_agg(to_jsonb(e)order by id)from solar_private.supplier_fx_entries e),'wallet',(select jsonb_agg(to_jsonb(e)order by id)from solar_private.wallet_fx_entries e),'requests',(select jsonb_agg(to_jsonb(e)order by request_id)from solar_private.finance_requests e),'fxRequests',(select jsonb_agg(to_jsonb(e)order by request_id)from solar_private.fx_requests e),'checkpoints',(select jsonb_agg(to_jsonb(e)order by source_key)from solar_private.profit_checkpoints e))::text)$$;
create function pg_temp.fail_record_update()returns trigger language plpgsql as $$begin if old.profit_settlement_id is not null and new.total<>old.total then raise exception 'forced_record_failure';end if;return new;end$$;
create trigger test_record_failure before update on transactions for each row execute function pg_temp.fail_record_update();
select set_config('test.fingerprint',pg_temp.record_fingerprint(),true);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003890',true);
do $$declare c jsonb;s jsonb;begin
 c:=public.solar_cash_record('get','profit:'||current_setting('test.settlement'));select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-389002;
 begin perform public.solar_cash_record('update','profit:'||current_setting('test.settlement'),gen_random_uuid(),jsonb_build_object('amount',900000,'note','فشل متعمد بعد عكس المورد','supplierId',-389002,'supplierToken',s->>'token','expectedToken',c->>'token'));raise exception 'FAIL partial allocation';exception when raise_exception then if sqlerrm<>'forced_record_failure'then raise;end if;end;
end$$;
reset role;
do $$begin if pg_temp.record_fingerprint()<>current_setting('test.fingerprint')then raise exception 'Partial supplier/cash correction survived failure';end if;end$$;
drop trigger test_record_failure on transactions;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003892',true);
do $$declare c jsonb;begin
 c:=public.solar_cash_record('get','tx:'||current_setting('test.settlementCash'));if(c->>'canEdit')::boolean then raise exception 'Staff can edit an approved settlement';end if;
 c:=public.solar_profit_workspace('overview');if(c->>'available')::numeric<>0 then raise exception 'Profit checkpoints changed after allocation correction';end if;
 begin perform public.solar_cash_record('get','tx:'||current_setting('test.deposit'));raise exception 'FAIL other cashbox';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003893',true);
do $$begin begin perform public.solar_cash_record('get');raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003894',true);
do $$begin begin perform public.solar_cash_record('get');raise exception 'FAIL warehouse stale admin';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin if has_function_privilege('anon','public.solar_cash_record(text,text,uuid,jsonb)','EXECUTE')then raise exception 'Anonymous cash edit';end if;end$$;
set constraints all immediate;
rollback;
\echo PASS cash edits and linked settlement corrections, exact delta, IQD overdraft, frozen USD basis, immediate balanced handover, role scoping, replay and stale-token protection
