-- Isolated fixtures; all financial writes are rolled back.
\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003750','إدارة اختبار القاصة',true,'admin_staff','07701234567','{}'),
('00000000-0000-0000-0000-000000003751','مشتري القاصة السالبة',false,'admin_staff','07701234567','{"purchase":true,"sale":true,"system":true,"systemPayment":true,"cash":true,"cashExpense":true,"supplierPayment":true}'),
('00000000-0000-0000-0000-000000003752','مشتري آخر',false,'admin_staff','07701234567','{"purchase":true}'),
('00000000-0000-0000-0000-000000003753','بدون شراء',false,'admin_staff','07701234567','{}'),
('00000000-0000-0000-0000-000000003754','مهندس الاختبار',true,'installer','07701234567','{}'),
('00000000-0000-0000-0000-000000003755','مخزن الاختبار',true,'warehouse','07701234567','{}');
insert into suppliers(id,name)values(-375001,'مورد شراء القاصة السالبة');
insert into customers(id,name,customer_type,owner_id)values(-375001,'زبون منظومة القاصة السالبة','system','00000000-0000-0000-0000-000000003751');
insert into products(id,code,name,qty,cost)values(-375001,'OVER-001','بطارية شراء القاصة السالبة',0,0),(-375002,'OVER-002','مادة فحص الدولار',0,0);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003750',true);
select public.solar_exchange_rate_set(1500,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003751","mode":"deposit","currency":"IQD","amount":1000000,"note":"رصيد مليون قبل الشراء"}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003751',true);
do $$declare req uuid:=gen_random_uuid();p jsonb;r jsonb;again jsonb;invoice_id bigint;wallet jsonb;begin
 p:='{"kind":"purchase","mode":"cash","party":"مورد شراء القاصة السالبة","partyId":-375001,"sourceCurrency":"IQD","exchangeRate":1,"marketRate":1500,"accountRevision":0,"cashCurrency":"IQD","warehouseId":1,"items":[{"id":-375001,"qty":2,"price":1000000}]}';
 r:=public.solar_invoice_save(req,p);invoice_id:=(r->>'id')::bigint;
 if solar_private.cash_balance(auth.uid())<>-1000000 or(select qty from products where id=-375001)<>2 or(select cost from products where id=-375001)<>1000000 then raise exception 'FAIL million cash minus two million purchase';end if;
 again:=public.solar_invoice_save(req,p);
 if again<>r or solar_private.cash_balance(auth.uid())<>-1000000 then raise exception 'FAIL duplicate purchase retry';end if;
 perform set_config('overdraft.purchase',invoice_id::text,true);
 -- An administrator editing the purchase still charges its original cashbox owner.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003750',true);
 p:=p||jsonb_build_object('invoiceId',invoice_id,'expectedRevision',r->'pricingRevision','items','[{"id":-375001,"qty":2,"price":1200000}]'::jsonb);
 r:=public.solar_invoice_save(gen_random_uuid(),p);
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003751')<>-1400000 or solar_private.cash_balance(auth.uid())<>0 then raise exception 'FAIL overdraft purchase edit cash owner';end if;
 p:=p||jsonb_build_object('expectedRevision',r->'pricingRevision','items','[{"id":-375001,"qty":2,"price":1000000}]'::jsonb);r:=public.solar_invoice_save(gen_random_uuid(),p);
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003751')<>-1000000 then raise exception 'FAIL replacement purchase amount compounded';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003752',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('expectedRevision',r->'pricingRevision'));raise exception 'FAIL foreign cashbox overdraft';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003751',true);
 wallet:=jsonb_build_array(public.solar_cash_workspace('{}')->'summary'->'USD',public.solar_cash_workspace('{}')->'summary'->'usdBook');
 p:='{"kind":"purchase","mode":"cash","party":"مورد شراء القاصة السالبة","partyId":-375001,"sourceCurrency":"USD","exchangeRate":1500,"marketRate":1500,"accountRevision":0,"cashCurrency":"IQD","warehouseId":1,"items":[{"id":-375002,"qty":1,"price":100}]}';
 r:=public.solar_invoice_save(gen_random_uuid(),p);
 if solar_private.cash_balance(auth.uid())<>-1150000 or jsonb_build_array(public.solar_cash_workspace('{}')->'summary'->'USD',public.solar_cash_workspace('{}')->'summary'->'usdBook')<>wallet then raise exception 'FAIL USD-priced purchase paid in IQD';end if;
 perform public.solar_purchase_delete((r->>'id')::bigint,(r->>'pricingRevision')::bigint);
 if solar_private.cash_balance(auth.uid())<>-1000000 or(select qty from products where id=-375002)<>0 then raise exception 'FAIL overdraft deletion reverses cash and stock';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),p||'{"cashCurrency":"USD"}'::jsonb);raise exception 'FAIL empty USD wallet overspend';exception when sqlstate 'P0002' then null;end;
 r:=public.solar_invoice_save(gen_random_uuid(),p||'{"mode":"credit"}'::jsonb);
 if solar_private.cash_balance(auth.uid())<>-1000000 then raise exception 'FAIL credit purchase changed cash';end if;
 perform public.solar_purchase_delete((r->>'id')::bigint,(r->>'pricingRevision')::bigint);
 begin perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003751","mode":"expense","currency":"IQD","amount":1,"note":"مصروف مستقل"}');raise exception 'FAIL purchase exception enabled unrelated spending';exception when sqlstate 'P0002' then null;end;
 begin perform public.solar_fx('payment',gen_random_uuid(),'{"supplierId":-375001,"paymentId":-375900,"amount":1,"currency":"IQD","cashCurrency":"IQD","rate":1500,"accountRevision":0,"mode":"cash","note":"تسديد مورد مستقل"}');raise exception 'FAIL independent supplier payment overspend';exception when sqlstate 'P0002' then null;end;
 if(public.solar_fx('account',null,'{"supplierId":-375001}')->>'balance')::numeric<>0 then raise exception 'FAIL paid purchase became supplier debt';end if;
 -- No cash is received merely by issuing a credit system invoice.
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"زبون منظومة القاصة السالبة","partyId":-375001,"warehouseId":1,"total":2500000,"installerId":"00000000-0000-0000-0000-000000003754","customerAddress":"عنوان الفحص","items":[{"id":-375001,"qty":1,"price":0}]}');
 if solar_private.cash_balance(auth.uid())<>-1000000 then raise exception 'FAIL credit system prematurely credited cash';end if;
 p:=jsonb_build_object('customerId',-375001,'invoiceId',r->'id','amount',1500000,'mode','payment','expectedToken',public.solar_system_payment_context(-375001)->>'token');req:=gen_random_uuid();
 r:=public.solar_system_payment_save(req,p);
 if(r->>'cashBefore')::numeric<>-1000000 or(r->>'cashAfter')::numeric<>500000 or solar_private.cash_balance(auth.uid())<>500000 then raise exception 'FAIL receipt did not repay overdraft %',r;end if;
 again:=public.solar_system_payment_save(req,p);
 if again<>r or solar_private.cash_balance(auth.uid())<>500000 then raise exception 'FAIL receipt retry double credit';end if;
 if(public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000003751"}')->'summary'->>'IQD')::numeric<>500000 then raise exception 'FAIL signed cash UI projection';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003753',true);
do $$begin begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"cash","party":"مورد شراء القاصة السالبة","items":[{"id":-375002,"qty":1,"price":100}]}');raise exception 'FAIL missing purchase permission';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003754',true);
do $$begin begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"cash","party":"مورد شراء القاصة السالبة","items":[{"id":-375002,"qty":1,"price":100}]}');raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003755',true);
do $$begin begin perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","mode":"cash","party":"مورد شراء القاصة السالبة","items":[{"id":-375002,"qty":1,"price":100}]}');raise exception 'FAIL warehouse stale admin';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS IQD purchase overdraft, exact retry, edit differences and owner, deletion reversal, USD-priced IQD purchase, credit separation, unchanged USD/expense/supplier-payment rules, system collection -1m to +500k, scoped purchase permissions
rollback;
