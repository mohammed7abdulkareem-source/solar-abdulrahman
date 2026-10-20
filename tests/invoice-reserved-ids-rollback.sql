\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003590','إدارة اختبار المشتريات',true,'admin_staff','07700003590','{}'),
('00000000-0000-0000-0000-000000003591','موظف المشتريات',false,'admin_staff','07700003591','{"purchase":true,"sale":true,"system":true}'),
('00000000-0000-0000-0000-000000003592','بلا صلاحية شراء',false,'admin_staff','07700003592','{}'),
('00000000-0000-0000-0000-000000003593','مهندس الاختبار',false,'installer','07700003593','{}');
insert into suppliers(id,name,account_currency) values(-359001,'مورد اختبار الأرقام','IQD');
insert into products(id,code,name,qty,cost) values(-359001,'RESERVED-PURCHASE','بطارية اختبار المشتريات',0,0);
insert into customers(id,name,customer_type,owner_id) values(-359001,'زبون اختبار الأرقام','wholesale','00000000-0000-0000-0000-000000003591');
insert into transactions(id,kind,total,cash,created_by,cashbox_user_id) values(8000000000000000,'cash_income',0,false,'00000000-0000-0000-0000-000000003590','00000000-0000-0000-0000-000000003590');
insert into solar_private.deleted_sales(invoice_id,invoice,items,deleted_by) values(8000000000000001,'{"kind":"sale","receipt_no":99}','[]','00000000-0000-0000-0000-000000003590');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003590',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
set local role authenticated;
do $$declare r jsonb;p jsonb;req uuid:=gen_random_uuid();a jsonb;t public.transactions;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);
 p:='{"kind":"purchase","party":"مورد اختبار الأرقام","partyId":-359001,"mode":"credit","sourceCurrency":"IQD","exchangeRate":1,"marketRate":1660,"accountRevision":0,"expenses":10000,"items":[{"id":-359001,"qty":1,"price":1000000}]}';
 r:=public.solar_invoice_save(req,p);
 if(r->>'id')::bigint<>8000000000000002 or(r->>'total')::numeric<>1010000 then raise exception 'purchase did not skip deleted highest ID: %',r;end if;
 if public.solar_invoice_save(req,p) is distinct from r then raise exception 'purchase replay changed receipt';end if;
 select * into t from transactions where id=(r->>'id')::bigint;
 if t.created_by<>auth.uid() or t.cashbox_user_id<>auth.uid() or t.expenses<>10000 or t.cash then raise exception 'purchase ownership or accounting changed';end if;
 if(select qty from products where id=-359001)<>1 or(select cost from products where id=-359001)<>1010000 then raise exception 'purchase stock/cost duplicated or lost expenses';end if;
 a:=public.solar_fx('account',null,'{"supplierId":-359001}');
 if(a->>'balance')::numeric<>1010000 or(a->>'cashBalance')::numeric<>0 then raise exception 'supplier debt or buyer cash incorrect: %',a;end if;
 -- Editing stays on the same ID and does not add quantities or debt again.
 r:=public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('invoiceId',r->'id','expectedRevision',r->'pricingRevision','notes','مراجعة الوصل'));
 if(r->>'id')::bigint<>8000000000000002 then raise exception 'edit allocated a new invoice';end if;
 perform set_config('test.reserved.purchase',r::text,true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003592',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'unauthorized purchase accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
-- A reset reservation above all current/deleted IDs must also remain unused.
insert into solar_private.reset_record_ids(table_name,record_id) values('transactions',8000000000000010);
set local role authenticated;
do $$declare r jsonb;p jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003591',true);
 p:='{"kind":"purchase","party":"مورد اختبار الأرقام","mode":"credit","sourceCurrency":"USD","exchangeRate":1660,"marketRate":1660,"accountRevision":0,"items":[{"id":-359001,"qty":2,"price":100}]}';
 r:=public.solar_invoice_save(gen_random_uuid(),p);
 if(r->>'id')::bigint<>8000000000000011 or(r->>'total')::numeric<>332000 then raise exception 'USD purchase reused reset reservation: %',r;end if;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"زبون اختبار الأرقام","mode":"credit","items":[{"id":-359001,"qty":1,"price":1500000}]}');
 if(r->>'id')::bigint<>8000000000000012 then raise exception 'wholesale ID allocation failed';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","party":"زبون اختبار الأرقام","mode":"credit","total":1500000,"installerId":"00000000-0000-0000-0000-000000003593","customerAddress":"عنوان الاختبار","items":[{"id":-359001,"qty":1,"price":0}]}');
 if(r->>'id')::bigint<>8000000000000013 then raise exception 'system ID allocation failed';end if;
end$$;
reset role;
do $$begin
 if(select count(*) from transactions where kind='purchase' and created_by='00000000-0000-0000-0000-000000003591')<>2 then raise exception 'purchase retry/edit created another purchase';end if;
 if(select sum(delta) from solar_private.supplier_fx_entries where supplier_id=-359001)<>1342000 then raise exception 'supplier balance changed unexpectedly';end if;
 if(select invoice from solar_private.deleted_sales where invoice_id=8000000000000001)<>'{"kind":"sale","receipt_no":99}'::jsonb then raise exception 'deleted receipt history changed';end if;
 begin insert into transactions(id,kind,total,cash) values(8000000000000001,'cash_income',1,true);raise exception 'deleted invoice resurrected';exception when sqlstate 'PT409' then null;end;
 if has_function_privilege('authenticated','solar_private.next_transaction_id()','execute') then raise exception 'private allocator exposed';end if;
 raise notice 'PASS new purchases skip deleted/reset IDs; IQD expenses, USD conversion, stock, owner, supplier debt, stable retry/edit, sales/system compatibility and deletion guards remain correct';
end$$;
rollback;
