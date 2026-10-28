begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003820','مدير القاصة السالبة',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003821','صاحب القاصة السالبة',false,'admin_staff','{"system":true,"systemPayment":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003822','مستخدم آخر',false,'admin_staff','{"system":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003823','مهندس الاختبار',false,'installer','{"installations":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values(-382001,'عميل القاصة السالبة','system','00000000-0000-0000-0000-000000003821');
insert into products(id,code,name,qty,cost)values(-382001,'NEG-382','مادة اختبار الرصيد',10,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,-382001,10)on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type)values('00000000-0000-0000-0000-000000003821','00000000-0000-0000-0000-000000003820',1000000,'transfer_in');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003821',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-382001,"party":"عميل القاصة السالبة","total":5000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003823","items":[{"id":-382001,"qty":1,"price":0}]}');
 perform set_config('test.negative.first',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-382001,"party":"عميل القاصة السالبة","total":3000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003823","items":[{"id":-382001,"qty":1,"price":0}]}');
 perform set_config('test.negative.second',r->>'id',true);
end$$;
reset role;
update transactions set warehouse_status='ready'where id in(current_setting('test.negative.first')::bigint,current_setting('test.negative.second')::bigint);
-- Exercise the real close, receipt and correction APIs, never a synthetic balance.
set local role authenticated;
do $$declare j transactions;k transactions;revision bigint;entries integer;c jsonb;r jsonb;request uuid;payload jsonb;begin
 select * into j from transactions where id=current_setting('test.negative.first')::bigint;
 assert solar_private.cash_balance(auth.uid())=1000000;
 perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":2000000}');
 assert solar_private.cash_balance(auth.uid())=-1000000,'First payout must overdraw';
 assert(select installation_status from transactions where id=j.id)='closed';
 assert(select profit from transactions where id=j.id)=2900000;
 select count(*)into entries from solar_cash_entries where job_id=j.id;
 begin perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":2000000}');raise exception 'Stale close accepted';exception when sqlstate 'PT409' then null;end;
 assert(select count(*)from solar_cash_entries where job_id=j.id)=entries;
 perform public.solar_installation_action(j.id,j.installation_revision+1,'reopen');
 perform public.solar_installation_action(j.id,j.installation_revision+2,'close','{"amount":2500000}');
 assert solar_private.cash_balance(auth.uid())=-1500000,'Only expense increase is debited';
 perform public.solar_installation_action(j.id,j.installation_revision+3,'reopen');
 perform public.solar_installation_action(j.id,j.installation_revision+4,'close','{"amount":2500000}');
 assert solar_private.cash_balance(auth.uid())=-1500000,'Same approval cannot debit twice';
 select * into k from transactions where id=current_setting('test.negative.second')::bigint;
 perform public.solar_installation_action(k.id,k.installation_revision,'close','{"amount":100000}');
 assert solar_private.cash_balance(auth.uid())=-1600000,'Already negative cashbox can pay another job';
 c:=public.solar_system_payment_context(-382001);request:=gen_random_uuid();
 payload:=jsonb_build_object('customerId',-382001,'invoiceId',j.id,'amount',1000000,'mode','payment','expectedToken',c->>'token');
 r:=public.solar_system_payment_save(request,payload);assert public.solar_system_payment_save(request,payload)=r;
 assert(r->>'cashBefore')::numeric=-1600000 and(r->>'cashAfter')::numeric=-600000;
 assert solar_private.cash_balance(auth.uid())=-600000,'Collection reduces overdraft';
 c:=public.solar_system_payment_context(-382001);
 r:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-382001,'invoiceId',j.id,'amount',1000000,'mode','payment','expectedToken',c->>'token'));
 assert(r->>'cashBefore')::numeric=-600000 and(r->>'cashAfter')::numeric=400000;
 assert solar_private.cash_balance(auth.uid())=400000,'Further collection returns cashbox to positive';
 select * into j from transactions where id=j.id;
 perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
 perform public.solar_installation_action(j.id,j.installation_revision+1,'close','{"amount":2000000}');
 assert solar_private.cash_balance(auth.uid())=900000,'Expense decrease refunds only the difference';
 perform public.solar_installation_action(j.id,j.installation_revision+2,'reopen');
 perform public.solar_installation_action(j.id,j.installation_revision+3,'clear_expenses');
 assert solar_private.cash_balance(auth.uid())=2900000;
 assert(select sum(delta)from solar_cash_entries where job_id=j.id)=0;
 select * into k from transactions where id=k.id;
 perform public.solar_installation_action(k.id,k.installation_revision,'reopen');
 perform public.solar_installation_action(k.id,k.installation_revision+1,'clear_expenses');
 assert solar_private.cash_balance(auth.uid())=3000000,'Cancelling costs preserves original cash plus collections';
 assert(select sum(delta)from solar_cash_entries where job_id in(j.id,k.id))=0;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003822',true);
 select * into j from transactions where id=j.id;
 begin perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":2000000}');raise exception 'Cross-owner approval accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003823',true);
 begin perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":2000000}');raise exception 'Engineer approved costs';exception when insufficient_privilege then null;end;
end$$;
reset role;
set constraints all immediate;
\echo PASS installation overdraft, further negative payout, customer receipts to positive, replay/stale protection, refunds and owner/engineer restrictions
rollback;
