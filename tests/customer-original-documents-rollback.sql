\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003630','إدارة الوصولات',true,'admin_staff','07700003630','{}'),
('00000000-0000-0000-0000-000000003631','صاحب الوصولات',false,'admin_staff','07700003631','{"customers":true,"customerStatement":true,"sale":true,"system":true,"customerPayment":true,"systemPayment":true}'),
('00000000-0000-0000-0000-000000003632','مستخدم آخر',false,'admin_staff','07700003632','{"customers":true,"customerStatement":true,"sale":true}'),
('00000000-0000-0000-0000-000000003633','مخزن بصلاحية قديمة',true,'warehouse','07700003633','{"customerStatement":true}'),
('00000000-0000-0000-0000-000000003634','مهندس بصلاحية قديمة',true,'installer','07700003634','{"customerStatement":true}');
insert into products(id,code,name,qty,cost) values(-363001,'ORIGINAL-1','انفيرتر الوصل الأصلي',100,1000),(-363002,'ORIGINAL-2','بطارية الوصل الأصلي',100,500);
insert into customers(id,name,phone,customer_type,owner_id) values
(-363001,'زبون الوصولات الأصلية','07800003631','wholesale','00000000-0000-0000-0000-000000003631'),
(-363002,'زبون المنظومات الأصلية','07800003632','system','00000000-0000-0000-0000-000000003631'),
(-363003,'زبون المستخدم الآخر','07800003633','wholesale','00000000-0000-0000-0000-000000003632'),
(-363004,'زبون بلا مسؤول','','wholesale',null);
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values
(-363010,'customer_payment',-363001,'زبون الوصولات الأصلية',-1000,false,'opening_balance',now()-interval '10 days','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631'),
(-363011,'customer_payment',-363001,'زبون الوصولات الأصلية',100,true,'payment',now()-interval '9 days','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003630',true);
select public.solar_exchange_rate_set(1660,(public.solar_exchange_rate_get()->>'revision')::bigint);
set local role authenticated;
do $$declare r jsonb;a jsonb;p jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003631',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"زبون الوصولات الأصلية","partyId":-363001,"mode":"credit","warehouseId":1,"items":[{"id":-363001,"qty":2,"price":1500},{"id":-363002,"qty":3,"price":800}],"warranty":{"enabled":true,"items":[{"id":-363001,"duration":2,"unit":"years"},{"id":-363002,"duration":1,"unit":"years"}],"maintenance":{"duration":6,"unit":"months"},"notes":"شروط الوصل <الأصلية>"}}');
 perform set_config('test.original.sale',r->>'id',true);perform set_config('test.original.snapshot',(r->'invoiceAccount')::text,true);
 a:=public.solar_customer_payment_context(-363001);
 p:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-363001,'amount',600,'mode','payment','notes','تسديد أصلي <موثق>','expectedToken',a->>'token'));
 perform set_config('test.original.payment',p->>'id',true);perform set_config('test.original.paymentSaved',p::text,true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","party":"زبون المنظومات الأصلية","partyId":-363002,"mode":"credit","warehouseId":1,"total":10000,"installerId":"00000000-0000-0000-0000-000000003634","customerAddress":"عنوان المنظومة","items":[{"id":-363001,"qty":1,"price":0},{"id":-363002,"qty":2,"price":0}],"warranty":{"enabled":true,"items":[{"id":-363001,"duration":1,"unit":"years"}],"maintenance":{"duration":3,"unit":"months"}}}');
 perform set_config('test.original.system',r->>'id',true);
 a:=public.solar_system_payment_context(-363002);
 p:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-363002,'invoiceId',r->'id','amount',2000,'mode','payment','notes','تسديد مرتبط بالمنظومة','expectedToken',a->>'token'));
 perform set_config('test.original.systemPayment',p->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003632',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","party":"زبون المستخدم الآخر","partyId":-363003,"mode":"credit","warehouseId":1,"items":[{"id":-363001,"qty":1,"price":2000}]}');
 perform set_config('test.original.other',r->>'id',true);
end$$;
reset role;
-- A statement-only user can read their existing copies without sale/payment edit rights.
update profiles set permissions='{"customerStatement":true}' where id='00000000-0000-0000-0000-000000003631';
set local role authenticated;
do $$declare r jsonb;s jsonb;p jsonb;b jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003631',true);
 r:=public.solar_customer_movement(-363001,current_setting('test.original.sale')::bigint);s:=r->'invoice';
 if r->>'type'<>'invoice' or jsonb_array_length(s->'items')<>2 or not exists(select 1 from jsonb_array_elements(s->'items') i where i->>'product_name'='انفيرتر الوصل الأصلي' and(i->>'price')::numeric=1500) then raise exception 'invoice item copy missing %',r;end if;
 if s->'invoice_account'<>current_setting('test.original.snapshot')::jsonb or(s->'invoice_account'->>'previousBalance')::numeric<>900 or(s->'invoice_account'->'lastPayment'->>'amount')::numeric<>100 then raise exception 'issued account snapshot replaced';end if;
 if s->>'warranty_token' is null or s->>'warehouse_qr_token' is null or s->'warranty'->>'enabled'<>'true' or s->>'creatorPhone'<>'07700003631' then raise exception 'warranty/QR/author missing';end if;
 if s ? 'cost' or s ? 'profit' or s->'items'->0 ? 'cost' or s->'items'->0 ? 'cost_basis' then raise exception 'internal financial details leaked';end if;
 r:=public.solar_customer_movement(-363001,current_setting('test.original.payment')::bigint);p:=r->'receipt';b:=current_setting('test.original.paymentSaved')::jsonb;
 if p->>'ledgerType'<>'wholesale' or p->>'balanceBasis'<>'issued' or p->'oldBalance'<>b->'oldBalance' or p->'remaining'<>b->'remaining' or p->>'creatorPhone'<>'07700003631' then raise exception 'original payment snapshot lost %',r;end if;
 if p ? 'cashAfter' or p ? 'cashBefore' or p ? 'cashBalance' then raise exception 'cashbox balance leaked to statement-only user';end if;
 r:=public.solar_customer_movement(-363002,current_setting('test.original.system')::bigint);
 if jsonb_array_length(r->'invoice'->'items')<>2 or r->'invoice'->'items'->0 ? 'price' then raise exception 'system original quantity-only copy changed';end if;
 r:=public.solar_customer_movement(-363002,current_setting('test.original.systemPayment')::bigint);
 if(r->'receipt'->'invoice'->>'id')::bigint<>current_setting('test.original.system')::bigint or jsonb_array_length(r->'receipt'->'invoice'->'items')<>2 or(r->'receipt'->>'invoiceBefore')::numeric<>10000 or(r->'receipt'->>'invoiceAfter')::numeric<>8000 then raise exception 'linked payment copy missing %',r;end if;
 r:=public.solar_customer_documents(-363001,null,null,'invoices');if(r->>'count')::integer<>1 then raise exception 'invoice category wrong';end if;
 r:=public.solar_customer_documents(-363001,null,null,'payments');if(r->>'count')::integer<>2 then raise exception 'payment category wrong';end if;
 r:=public.solar_customer_documents(-363001,null,null,'other');if(r->>'count')::integer<>1 then raise exception 'opening mixed with real payments';end if;
 r:=public.solar_customer_documents(-363001,null,null,'all','موثق');if(r->>'count')::integer<>1 then raise exception 'literal notes filter failed';end if;
 begin perform public.solar_customer_movement(-363001,current_setting('test.original.other')::bigint);raise exception 'foreign movement ID accepted';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_documents(-363003);raise exception 'other customer documents leaked';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_documents(-363004);raise exception 'unassigned customer bypassed ownership';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_documents(-363001,current_date,current_date-1);raise exception 'reversed period accepted';exception when invalid_parameter_value then null;end;
end$$;
reset role;
-- Later changes never replace the invoice issue-time account or the saved payment balance.
update products set name='اسم المادة الجديد' where id=-363001;
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_at,created_by,cashbox_user_id) values
(-363012,'customer_payment',-363001,'زبون الوصولات الأصلية',20,true,'payment','2026-10-20T20:59:59Z','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631'),
(-363013,'customer_payment',-363001,'زبون الوصولات الأصلية',21,true,'payment','2026-10-20T21:00:00Z','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631'),
(-363014,'customer_payment',-363001,'زبون الوصولات الأصلية',22,true,'payment','2026-10-21T20:59:59Z','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631'),
(-363015,'customer_payment',-363001,'زبون الوصولات الأصلية',23,true,'payment','2026-10-21T21:00:00Z','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631');
do $$declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003631',true);
 r:=public.solar_customer_movement(-363001,current_setting('test.original.sale')::bigint);
 if r->'invoice'->'invoice_account'<>current_setting('test.original.snapshot')::jsonb or not exists(select 1 from jsonb_array_elements(r->'invoice'->'items') i where i->>'product_name'='انفيرتر الوصل الأصلي') then raise exception 'historical invoice changed';end if;
 r:=public.solar_customer_movement(-363001,current_setting('test.original.payment')::bigint);
 if r->'receipt'->'remaining'<>(current_setting('test.original.paymentSaved')::jsonb)->'remaining' then raise exception 'future activity changed saved payment copy';end if;
 r:=public.solar_customer_documents(-363001,'2026-10-21','2026-10-21','payments');
 if exists(select 1 from jsonb_array_elements(r->'rows') x where x->'movement'->>'id' in('-363012','-363015')) or(select count(*) from jsonb_array_elements(r->'rows') x where x->'movement'->>'id' in('-363013','-363014'))<>2 then raise exception 'Baghdad date edges wrong';end if;
end$$;
-- Reassigning a customer does not disclose another user's existing invoices.
update customers set owner_id='00000000-0000-0000-0000-000000003631' where id=-363003;
do $$declare r jsonb;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003631',true);
 begin perform public.solar_customer_movement(-363003,current_setting('test.original.other')::bigint);raise exception 'reassigned customer leaked previous author copy';exception when insufficient_privilege then null;end;
 r:=public.solar_customer_documents(-363003);if(r->>'count')::integer<>0 then raise exception 'batch leaked previous author copy';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003630',true);
 r:=public.solar_customer_movement(-363003,current_setting('test.original.other')::bigint);if r->>'type'<>'invoice' then raise exception 'admin original copy missing';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003631',true);
end$$;
-- A period export is complete beyond the first 30 displayed movements.
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)
 select -363100-i,'sale',-363001,'زبون الوصولات الأصلية',10,false,'credit','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631' from generate_series(1,35)i;
do $$declare r jsonb;begin
 r:=public.solar_customer_documents(-363001,null,null,'invoices');if(r->>'count')::integer<>36 then raise exception 'export truncated at displayed page';end if;
end$$;
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)
 select -363200-i,'sale',-363001,'زبون الوصولات الأصلية',10,false,'credit','00000000-0000-0000-0000-000000003631','00000000-0000-0000-0000-000000003631' from generate_series(1,70)i;
do $$begin
 begin perform public.solar_customer_documents(-363001,null,null,'invoices');raise exception 'oversized export silently truncated';exception when invalid_parameter_value then null;end;
end$$;
update profiles set permissions='{}' where id='00000000-0000-0000-0000-000000003631';
set local role authenticated;
do $$begin
 begin perform public.solar_customer_movement(-363001,current_setting('test.original.sale')::bigint);raise exception 'revoked statement still worked';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003633',true);
 begin perform public.solar_customer_movement(-363001,current_setting('test.original.sale')::bigint);raise exception 'warehouse stale admin flag leaked';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003634',true);
 begin perform public.solar_customer_movement(-363001,current_setting('test.original.sale')::bigint);raise exception 'installer stale admin flag leaked';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_customer_documents(bigint,date,date,text,text)','execute') or has_function_privilege('authenticated','solar_private.customer_invoice_document(public.transactions)','execute') then raise exception 'anonymous RPC/private formatter exposed';end if;
 raise notice 'PASS original invoice items, price/quantity, warranty/QR, fixed account and payment snapshots, linked system receipts, statement-only permission, ownership and live revocation, literal filters, Baghdad dates and complete bounded exports';
end$$;
rollback;
