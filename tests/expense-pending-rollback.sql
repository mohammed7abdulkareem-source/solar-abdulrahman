\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003740','إدارة المصاريف',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003741','صاحب المنظومات',false,'admin_staff','{"installations":true,"system":true,"systemPayment":true,"cash":true,"cashDeposit":true,"profit":true,"cashTransferSend":true,"cashExpense":true}'),
('00000000-0000-0000-0000-000000003742','صاحب آخر',false,'admin_staff','{"system":true,"profit":true}'),
('00000000-0000-0000-0000-000000003743','بدون صلاحية',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003744','مهندس بصلاحية قديمة',true,'installer','{}'),
('00000000-0000-0000-0000-000000003745','مخزن بصلاحية قديمة',true,'warehouse','{}');
insert into customers(id,name,customer_type,owner_id) values
(-374001,'عميل المنظومات المفتوحة','system','00000000-0000-0000-0000-000000003741'),
(-374002,'عميل المستخدم الآخر','system','00000000-0000-0000-0000-000000003742');
insert into suppliers(id,name) values(-374001,'مورد اختبار المصروف');
insert into products(id,code,name,qty,cost) values(-374001,'PEND-001','مادة كشف المنظومات',1000,1000),(-374002,'EXP-001','مادة مصروف شراء',0,0);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003740',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003741","mode":"deposit","currency":"IQD","amount":1000000,"note":"رصيد فحص"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003740","mode":"deposit","currency":"IQD","amount":1000000,"note":"رصيد إدارة"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003741',true);
do $$declare r jsonb;c jsonb;i integer;begin
 for i in 1..40 loop
  r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-374001,"party":"عميل المنظومات المفتوحة","mode":"credit","warehouseId":1,"total":10000,"installerId":"00000000-0000-0000-0000-000000003744","customerAddress":"عنوان","items":[{"id":-374001,"qty":1,"price":0}]}');
  update transactions set created_at='2026-10-25T12:00Z' where id=(r->>'id')::bigint;
  if i=1 then perform set_config('test.pending.first',r->>'id',true);update transactions set created_at='2026-10-24T20:59:59Z',warehouse_status='ready' where id=(r->>'id')::bigint;end if;
  if i=2 then update transactions set created_at='2026-10-24T21:00Z',cash=true,payment_mode='cash' where id=(r->>'id')::bigint;end if;
 end loop;
 c:=public.solar_system_payment_context(-374001);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-374001,'invoiceId',current_setting('test.pending.first')::bigint,'amount',2000,'mode','payment','expectedToken',c->>'token'));
 c:=public.solar_system_payment_context(-374001);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-374001,'amount',3000,'mode','payment','expectedToken',c->>'token'));
end$$;
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-374666,'system_payment',-374001,'عميل المنظومات المفتوحة',-50000,false,'opening_balance','00000000-0000-0000-0000-000000003741','00000000-0000-0000-0000-000000003741');
-- A payment by another user for the same customer must not leak into this owner's unallocated total.
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-374667,'system_payment',-374001,'عميل المنظومات المفتوحة',750,true,'payment','00000000-0000-0000-0000-000000003742','00000000-0000-0000-0000-000000003742');
set local role authenticated;
do $$declare r jsonb;j jsonb;paid numeric;before_cash numeric;owner_cash numeric;admin_cash numeric;revision bigint;entries integer;begin
 r:=public.solar_pending_systems();
 if(r->'summary'->>'count')::integer<>40 or(r->'summary'->>'collected')::numeric<>12000 or(r->'summary'->>'provisionalProfit')::numeric<>360000 or(r->'summary'->>'unallocatedCollections')::numeric<>3000 then raise exception 'FAIL pending scope/receipts/profit/unallocated %',r->'summary';end if;
 r:=public.solar_pending_systems(null,'2026-10-25','2026-10-25');if(r->'summary'->>'count')::integer<>39 or(r->'summary'->>'collected')::numeric<>10000 then raise exception 'FAIL Baghdad period boundary';end if;
 begin perform public.solar_pending_systems('00000000-0000-0000-0000-000000003742');raise exception 'FAIL cross-user pending';exception when insufficient_privilege then null;end;
 select value into j from jsonb_array_elements(public.solar_installation_jobs()) where(value->>'id')::bigint=current_setting('test.pending.first')::bigint;
 revision:=(j->>'installationRevision')::bigint;before_cash:=solar_private.cash_balance(auth.uid());
 perform public.solar_installation_action((j->>'id')::bigint,revision,'close','{"amount":100}');
 if solar_private.cash_balance(auth.uid())<>before_cash-100 then raise exception 'FAIL first expense';end if;
 select count(*) into entries from solar_cash_entries where job_id=(j->>'id')::bigint;
 begin perform public.solar_installation_action((j->>'id')::bigint,revision,'close','{"amount":100}');raise exception 'FAIL stale double close';exception when sqlstate 'PT409' then null;end;
 perform public.solar_installation_action((j->>'id')::bigint,revision+1,'reopen');
 perform public.solar_installation_action((j->>'id')::bigint,revision+2,'close','{"amount":100}');
 if(select count(*) from solar_cash_entries where job_id=(j->>'id')::bigint)<>entries or solar_private.cash_balance(auth.uid())<>before_cash-100 then raise exception 'FAIL same expense paid twice';end if;
 perform public.solar_installation_action((j->>'id')::bigint,revision+3,'reopen');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003740',true);
 admin_cash:=solar_private.cash_balance(auth.uid());
 perform public.solar_installation_action((j->>'id')::bigint,revision+4,'close','{"amount":150}');
 if solar_private.cash_balance(auth.uid())<>admin_cash-50 then raise exception 'FAIL increase must post only delta';end if;
 perform public.solar_installation_action((j->>'id')::bigint,revision+5,'reopen');
 perform public.solar_installation_action((j->>'id')::bigint,revision+6,'close','{"amount":80}');
 if solar_private.cash_balance(auth.uid())<>admin_cash or solar_private.cash_balance('00000000-0000-0000-0000-000000003741')<>before_cash-80 then raise exception 'FAIL refund to original payers';end if;
 perform public.solar_installation_action((j->>'id')::bigint,revision+7,'reopen');
 perform public.solar_installation_action((j->>'id')::bigint,revision+8,'close','{"amount":0}');
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003741')<>before_cash or(select sum(delta) from solar_cash_entries where job_id=(j->>'id')::bigint)<>0 then raise exception 'FAIL deleting expense must net to zero';end if;
 r:=public.solar_pending_systems('00000000-0000-0000-0000-000000003741');if(r->'summary'->>'count')::integer<>39 or(r->'summary'->>'collected')::numeric<>10000 then raise exception 'FAIL closed invoice remains pending';end if;
 perform public.solar_installation_action((j->>'id')::bigint,revision+9,'reopen');
 select value into j from jsonb_array_elements(public.solar_installation_jobs()) where(value->>'id')::bigint=current_setting('test.pending.first')::bigint;
 if(j->>'installationPaidExpenses')::numeric<>0 or(j->>'installationExpenses')::numeric<>0 then raise exception 'FAIL cancelled expense resurrected';end if;

end$$;
reset role;
-- A handed-over expense refund is a positive ledger movement, not another debit.
do $$declare transfer uuid:=gen_random_uuid();before_profit numeric;after_profit numeric;v numeric;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003741',true);
 before_profit:=solar_private.retained_profit(auth.uid());
 perform public.solar_cash_transfer_send(transfer,'00000000-0000-0000-0000-000000003740',100,100,'مصروف الفحص','تسليم الفحص');
 insert into solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id,notes) values(auth.uid(),50,'handover_expense',transfer,auth.uid(),'استرجاع نصف المصروف');
 after_profit:=solar_private.retained_profit(auth.uid());
 if after_profit<>before_profit-50 then raise exception 'FAIL refund absolute double expense';end if;
 select sum((x->>'value')::numeric) into v from jsonb_array_elements(solar_private.profit_rows(auth.uid()))x where x->>'kind'='handover_expense';
 if v<>-50 then raise exception 'FAIL profit ledger refund sign';end if;
end$$;
-- Additional purchase expenses are replaced on edit and reversed on deletion.
do $$declare r jsonb;p jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003740',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","partyId":-374001,"party":"مورد اختبار المصروف","mode":"credit","sourceCurrency":"IQD","warehouseId":1,"expenses":20,"items":[{"id":-374002,"qty":10,"price":100}]}');
 if(select cost from products where id=-374002)<>102 then raise exception 'FAIL purchase expense once';end if;
 p:=jsonb_build_object('kind','purchase','invoiceId',r->'id','expectedRevision',r->'pricingRevision','partyId',-374001,'party','مورد اختبار المصروف','mode','credit','sourceCurrency','IQD','warehouseId',1,'expenses',30,'items','[{"id":-374002,"qty":10,"price":100}]'::jsonb);
 r:=public.solar_invoice_save(gen_random_uuid(),p);
 if(select cost from products where id=-374002)<>103 then raise exception 'FAIL edited purchase expense accumulated';end if;
 p:=p||jsonb_build_object('expectedRevision',r->'pricingRevision','expenses',0);r:=public.solar_invoice_save(gen_random_uuid(),p);
 if(select cost from products where id=-374002)<>100 then raise exception 'FAIL removed purchase expense remains';end if;
 perform public.solar_purchase_delete((r->>'id')::bigint,(r->>'pricingRevision')::bigint);
 if(select qty from products where id=-374002)<>0 then raise exception 'FAIL deleted purchase stock';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003743',true);
do $$begin begin perform public.solar_pending_systems();raise exception 'FAIL no-permission profile';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003744',true);
do $$declare j jsonb;begin
 begin perform public.solar_pending_systems();raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;
 j:=public.solar_installation_jobs();if j::text ~ '"installationPaidExpenses"' then raise exception 'FAIL engineer cash expense leak';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003745',true);
do $$begin begin perform public.solar_pending_systems();raise exception 'FAIL warehouse stale admin';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS pending actual collections and provisional profit, unallocated receipt isolation, all rows and Baghdad dates, expense close/reclose/increase/refund/delete-to-zero, original payers, operating refund sign, purchase expense edits/deletion, scope and roles
rollback;
