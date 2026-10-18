\set ON_ERROR_STOP on
begin;
\ir fixtures/cash-transfers-bootstrap.sql
insert into profiles(id,display_name,username,is_admin,permissions,active) values
('00000000-0000-0000-0000-000000003390','مدير التسوية','adjust_admin',true,'{}',true),
('00000000-0000-0000-0000-000000003391','موظف التسوية','adjust_staff',false,'{"cash":true,"financeReceive":true}',true),
('00000000-0000-0000-0000-000000003392','قاصة قديمة','adjust_old',false,'{}',false);
insert into suppliers(id,name) values(-339001,'مورد التسوية');
insert into customers(id,name,customer_type,owner_id) values(-339001,'زبون التسوية','wholesale','00000000-0000-0000-0000-000000003391');
insert into transactions(id,kind,total,cash,party_id,party_name,created_by,cashbox_user_id,payment_mode) values
(-339001,'purchase',1000,false,-339001,'مورد التسوية','00000000-0000-0000-0000-000000003390','00000000-0000-0000-0000-000000003390','credit'),
(-339002,'customer_payment',-2000,false,-339001,'زبون التسوية','00000000-0000-0000-0000-000000003390','00000000-0000-0000-0000-000000003390','opening_balance'),
(-339003,'cash_expense',250,true,null,null,'00000000-0000-0000-0000-000000003391','00000000-0000-0000-0000-000000003391','cash'),
(-339004,'cash_income',900,true,null,null,'00000000-0000-0000-0000-000000003392','00000000-0000-0000-0000-000000003392','cash');
create temporary table before_finance as select (select jsonb_agg(to_jsonb(t) order by id) from transactions t) transactions,(select jsonb_agg(to_jsonb(e) order by id) from solar_private.supplier_fx_entries e) supplier_entries,solar_private.retained_profit('00000000-0000-0000-0000-000000003390') profit;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003390',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003390","mode":"deposit","currency":"IQD","amount":8000,"note":"تمويل الاختبار"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003390","mode":"deposit","currency":"USD","amount":100.50,"rate":1500,"note":"تمويل الاختبار"}');
do $$declare admin_id uuid:='00000000-0000-0000-0000-000000003390';staff_id uuid:='00000000-0000-0000-0000-000000003391';c jsonb;r jsonb;b jsonb;rid uuid:=gen_random_uuid();transfer_id uuid:=gen_random_uuid();begin
 c:=public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',admin_id));
 if (c->'rows'->0->>'IQD')::numeric<>8000 or(c->'rows'->0->>'USD')::numeric<>100.5 then raise exception 'snapshot balances';end if;
 b:=jsonb_build_object('ownerId',admin_id,'mode','set','currency','USD','target',120.75,'rate',1600,'note','دولار إضافي','expectedToken',c->>'token');
 r:=public.solar_cash_reconcile('apply',rid,b);
 if(r->'rows'->0->>'afterBook')::numeric<>183150 or(r->'rows'->0->>'afterIQD')::numeric<>8000 then raise exception 'usd book or iqd changed';end if;
 if public.solar_cash_reconcile('apply',rid,b)<>r then raise exception 'retry duplicated';end if;
 begin perform public.solar_cash_reconcile('apply',gen_random_uuid(),b);raise exception 'stale accepted';exception when serialization_failure then null;end;
 c:=public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',admin_id));
 b:=b||jsonb_build_object('expectedToken',c->>'token','target',60.25,'rate',null);
 r:=public.solar_cash_reconcile('apply',gen_random_uuid(),b);
 if(r->'rows'->0->>'afterBook')::numeric<>round(183150*60.25/120.75,2) then raise exception 'proportional usd decrease';end if;
 c:=public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',admin_id));
 r:=public.solar_cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('ownerId',admin_id,'mode','zero','currency','USD','note','تصفير دولار قاصة واحدة','expectedToken',c->>'token'));
 if(r->'rows'->0->>'afterUSD')::numeric<>0 or(r->'rows'->0->>'afterBook')::numeric<>0 or(r->'rows'->0->>'afterIQD')::numeric<>8000 then raise exception 'single currency zero';end if;
 -- Negative legacy cash can be reconciled without treating the correction as income/profit.
 c:=public.solar_cash_reconcile('context',null,jsonb_build_object('ownerId',staff_id));
 r:=public.solar_cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('ownerId',staff_id,'mode','set','currency','IQD','target',100,'note','تصحيح قاصة سالبة','expectedToken',c->>'token'));
 if(r->'rows'->0->>'beforeIQD')::numeric<>-250 or(r->'rows'->0->>'afterIQD')::numeric<>100 then raise exception 'negative correction';end if;
 -- No pending money may reappear after a bulk reset.
 perform public.solar_cash_transfer_send(transfer_id,staff_id,100);
 c:=public.solar_cash_reconcile('context');
 if(c->>'pendingCount')::integer<>1 then raise exception 'missing pending transfer';end if;
 begin perform public.solar_cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('mode','zero','currency','both','note','تصفير الجميع','expectedToken',c->>'token'));raise exception 'pending reset accepted';exception when raise_exception then if sqlerrm='pending reset accepted' then raise;end if;end;
 perform public.solar_cash_transfer_decide(transfer_id,'cancelled');
 c:=public.solar_cash_reconcile('context');
 r:=public.solar_cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('mode','zero','currency','both','note','تصفير جميع القاصات بعد الجرد','expectedToken',c->>'token'));
 if jsonb_array_length(r->'rows')<>3 then raise exception 'inactive cashbox omitted';end if;
 if jsonb_array_length(public.solar_cash_receipt((r->>'requestId')::uuid)->'rows')<>3 then raise exception 'admin receipt';end if;
 perform set_config('request.jwt.claim.sub',staff_id::text,true);
 if jsonb_array_length(public.solar_cash_receipt((r->>'requestId')::uuid)->'rows')<>1 then raise exception 'staff receipt leaks owners';end if;
 begin perform public.solar_cash_reconcile('context');raise exception 'staff read admin snapshot';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_reconcile('apply',gen_random_uuid(),'{}');raise exception 'staff adjusted cash';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$declare snapshot record;begin
 select * into snapshot from before_finance;
 if exists(select 1 from profiles p where p.id::text like '%00339_' and(solar_private.cash_balance(p.id)<>0 or(solar_private.usd_wallet(p.id)->>'amount')::numeric<>0 or(solar_private.usd_wallet(p.id)->>'book')::numeric<>0)) then raise exception 'reset residual';end if;
 if (select jsonb_agg(to_jsonb(t) order by id) from transactions t where id<0) is distinct from snapshot.transactions then raise exception 'original receipts changed';end if;
 if (select jsonb_agg(to_jsonb(e) order by id) from solar_private.supplier_fx_entries e) is distinct from snapshot.supplier_entries then raise exception 'supplier balance changed';end if;
 if solar_private.retained_profit('00000000-0000-0000-0000-000000003390')<>snapshot.profit then raise exception 'profit changed';end if;
 if exists(select 1 from solar_private.wallet_fx_entries where entry_type='cash_reconcile' and gain<>0) then raise exception 'correction gain';end if;
 if has_function_privilege('anon','public.solar_cash_reconcile(text,uuid,jsonb)','EXECUTE') then raise exception 'anon access';end if;
 raise notice 'PASS cash targets, negative legacy cash, USD valuation, retry, stale snapshot, bulk zero, pending transfers, inactive owner, admin-only, receipt scope and unchanged accounts/profit';
end $$;
rollback;
