\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003870','مدير الكشف',true,'admin_staff','07700003870','{}'),
('00000000-0000-0000-0000-000000003871','صاحب الفاتورة',false,'admin_staff','07700003871','{"sale":true,"system":true,"systemPayment":true,"profit":true}'),
('00000000-0000-0000-0000-000000003872','مستلم الربح',false,'admin_staff','07700003872','{"profit":true}'),
('00000000-0000-0000-0000-000000003873','مستخدم آخر',false,'admin_staff','07700003873','{"profit":true,"system":true}'),
('00000000-0000-0000-0000-000000003874','مهندس',true,'installer','07700003874','{"profit":true}');
insert into brands(id,name)values(-387001,'البراند الحالي');
insert into products(id,code,name,qty,cost,brand_id,category)values(-387001,'PR-1','بطارية تفصيل الربح',100,100,-387001,'بطارية'),(-387002,'PR-2','لوح تفصيل الربح',100,40,-387001,'ألواح');
insert into customers(id,name,phone,customer_type,owner_id)values
(-387001,'زبون جملة الربح','07710000001','wholesale','00000000-0000-0000-0000-000000003871'),
(-387002,'زبون حساب المنظومات','07710000002','system','00000000-0000-0000-0000-000000003871');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003871',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-387001,"party":"زبون جملة الربح","expenses":50,"notes":"ملاحظة خاصة لا تنقل","items":[{"id":-387001,"qty":2,"price":400},{"id":-387002,"qty":1,"price":200}]}');perform set_config('test.sale',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-387002,"party":"زبون حساب المنظومات","installerId":"00000000-0000-0000-0000-000000003874","customerAddress":"عنوان خاص","total":20000000,"items":[{"id":-387001,"qty":2,"price":0}]}');perform set_config('test.system',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-387002,"party":"زبون حساب المنظومات","installerId":"00000000-0000-0000-0000-000000003874","customerAddress":"عنوان خاص","total":10000000,"items":[{"id":-387002,"qty":1,"price":0}]}');perform set_config('test.system2',r->>'id',true);
 r:=public.solar_system_payment_context(-387002);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-387002,'invoiceId',null,'amount',11000000,'mode','payment','notes','دفعة حساب عامة','expectedToken',r->>'token'));
 r:=public.solar_system_payment_context(-387002);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-387002,'invoiceId',current_setting('test.system2')::bigint,'amount',1000000,'mode','payment','notes','ربط قديم اختياري','expectedToken',r->>'token'));
end$$;
reset role;
select set_config('test.books',(select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i),'cash',(select jsonb_agg(to_jsonb(e)order by id)from solar_cash_entries e))::text)),true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_pending_systems();
 if r->>'collectionBasis'<>'customer_account' or(r->'summary'->>'accountCollections')::numeric<>12000000 then raise exception 'Account payments missing %',r;end if;
 if jsonb_array_length(r->'accounts')<>1 or(r->'accounts'->0->>'openCount')::integer<>2 or(r->'accounts'->0->>'balance')::numeric<>18000000 or(r->'accounts'->0->>'receiptCount')::integer<>2 then raise exception 'Customer duplicated / wrong account %',r->'accounts';end if;
 r:=public.solar_profit_detail('tx:'||current_setting('test.sale'));
 if(r->'breakdown'->>'netProfit')::numeric<>760 or(r->'breakdown'->>'materialsCost')::numeric<>240 then raise exception 'Wrong sale profit %',r;end if;
 if jsonb_array_length(r->'breakdown'->'items')<>2 or not exists(select 1 from jsonb_array_elements(r->'breakdown'->'items')i where(i->>'productId')::bigint=-387001 and(i->>'lineProfit')::numeric=600) or r->'breakdown'->'items'->0->>'brand'<>'البراند الحالي' then raise exception 'Materials/brand margin missing %',r;end if;
end$$;
reset role;
do $$begin if(select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from transactions t),'items',(select jsonb_agg(to_jsonb(i)order by id)from transaction_items i),'cash',(select jsonb_agg(to_jsonb(e)order by id)from solar_cash_entries e))::text))<>current_setting('test.books')then raise exception 'Report changed books';end if;end$$;
update transactions set installation_status='closed',installation_expenses=100,profit=total-cost-100 where id=current_setting('test.system')::bigint;
insert into solar_private.invoice_profit_owners(invoice_id,owner_id,updated_by)values
(current_setting('test.sale')::bigint,'00000000-0000-0000-0000-000000003872','00000000-0000-0000-0000-000000003870'),
(current_setting('test.system')::bigint,'00000000-0000-0000-0000-000000003872','00000000-0000-0000-0000-000000003870');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003872',true);
do $$declare r jsonb;begin
 r:=public.solar_profit_detail('tx:'||current_setting('test.sale'));
 if not(r->>'transferred')::boolean or r->'invoice'<>'null'::jsonb or jsonb_array_length(r->'breakdown'->'items')<>2 then raise exception 'Transferred material report absent %',r;end if;
 if r::text like '%invoice_account%' or r::text like '%ملاحظة خاصة%' or r::text like '%07710000001%' then raise exception 'Recipient received private customer account/contact';end if;
 r:=public.solar_profit_detail('tx:'||current_setting('test.system'));
 if(r->'breakdown'->>'netProfit')::numeric<>19999700 or r->'breakdown'->'items'->0->'unitPrice'<>'null'::jsonb or r->'breakdown'->'items'->0->'lineProfit'<>'null'::jsonb then raise exception 'System unit prices invented %',r;end if;
 begin perform public.solar_profit_detail('tx:'||current_setting('test.sale'),'00000000-0000-0000-0000-000000003871');raise exception 'FAIL other account';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003873',true);
do $$begin begin perform public.solar_profit_detail('tx:'||current_setting('test.sale'));raise exception 'FAIL unrelated materials';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003874',true);
do $$begin begin perform public.solar_profit_detail('tx:'||current_setting('test.sale'));raise exception 'FAIL engineer financial details';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS customer-account collections counted once without allocation; current account balances unchanged; material profit details for own and attributed receipts, saved cost, current brand, system totals and recipient privacy
