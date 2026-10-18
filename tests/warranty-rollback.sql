\set ON_ERROR_STOP on
begin;
-- Production does not give anon schema access by default. Exercise both states.
revoke usage on schema solar_private from anon;
set local role anon;
do $$begin
 begin perform public.solar_warranty_verify(gen_random_uuid());raise exception 'missing schema usage accepted';exception when insufficient_privilege then null;end;
end $$;
reset role;
grant usage on schema solar_private to anon;
insert into profiles(id,display_name,is_admin,permissions,user_type) values
('00000000-0000-0000-0000-000000003440','Warranty Admin',true,'{}','admin_staff'),
('00000000-0000-0000-0000-000000003441','Warranty Seller',false,'{"sale":true,"system":true,"salesDeleteOwn":true}','admin_staff'),
('00000000-0000-0000-0000-000000003442','Other Seller',false,'{"sale":true}','admin_staff'),
('00000000-0000-0000-0000-000000003443','Warranty Engineer',false,'{}','installer');
insert into customers(id,name,customer_type,owner_id) values(-344001,'Warranty Customer','wholesale','00000000-0000-0000-0000-000000003441'),(-344002,'System Warranty Customer','system','00000000-0000-0000-0000-000000003441');
insert into products(id,code,name,qty,cost) values(-344001,'WAR-1','Warranty Panel',20,100000),(-344002,'WAR-2','Warranty Battery',20,200000);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003441',true);
do $$declare r jsonb;c jsonb;b jsonb;again jsonb;p jsonb;token uuid;begin
 p:='{"kind":"sale","mode":"credit","party":"Warranty Customer","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"items":[{"id":-344001,"qty":2,"price":150000},{"id":-344002,"qty":1,"price":300000}],"warranty":{"enabled":true,"items":[{"id":-344001,"duration":5,"unit":"years"}],"maintenance":{"duration":6,"unit":"months"},"notes":"شروط صيانة تجريبية"}}';
 r:=public.solar_invoice_save('00000000-0000-0000-0000-000000034401',p);
 if(r->>'profit')::numeric<>200000 or r->>'warrantyToken' is null then raise exception 'invoice/warranty result';end if;
 perform set_config('test.warranty_invoice',r->>'id',true);perform set_config('test.warranty_token',r->>'warrantyToken',true);
 if public.solar_invoice_save('00000000-0000-0000-0000-000000034401',p)<>r then raise exception 'invoice replay';end if;
 c:=public.solar_warranty_verify((r->>'warrantyToken')::uuid);
 if c::text like '%"cost"%' or c::text like '%"profit"%' or c::text like '%cashbox%' then raise exception 'public data leak';end if;
 if not(select (x->'status'->>'active')::boolean from jsonb_array_elements(c->'items')x where(x->>'id')::bigint=-344001) or(select (x->'status'->>'covered')::boolean from jsonb_array_elements(c->'items')x where(x->>'id')::bigint=-344002) or not(c->'maintenanceStatus'->>'active')::boolean then raise exception 'individual coverage';end if;
 begin update transactions set warranty='{"enabled":false}' where id=(r->>'id')::bigint;raise exception 'direct warranty tamper';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),p||'{"warranty":{"enabled":true,"items":[{"id":-344001,"duration":-1,"unit":"years"}]}}');raise exception 'negative warranty allowed';exception when raise_exception then if sqlerrm='negative warranty allowed' then raise;end if;end;
 c:=public.solar_warranty_manage('get',null,jsonb_build_object('id',r->>'id'));
 b:=jsonb_build_object('id',r->>'id','expectedToken',c->>'expectedToken','warranty',jsonb_build_object('enabled',true,'items',jsonb_build_array(jsonb_build_object('id',-344001,'duration',2,'unit','years')),'maintenance',jsonb_build_object('duration',12,'unit','months')));
 again:=public.solar_warranty_manage('save','00000000-0000-0000-0000-000000034402',b);
 if again->>'warrantyToken'<>r->>'warrantyToken' or public.solar_warranty_manage('save','00000000-0000-0000-0000-000000034402',b)<>again then raise exception 'stable QR / replay';end if;
 begin perform public.solar_warranty_manage('save',gen_random_uuid(),b);raise exception 'stale warranty edit';exception when serialization_failure then null;end;
 -- A stale financial edit must not overwrite a separately updated warranty.
 begin perform public.solar_invoice_save(gen_random_uuid(),p||jsonb_build_object('invoiceId',r->'id','expectedRevision',r->'pricingRevision','expectedWarrantyRevision',r->'warrantyRevision'));raise exception 'stale invoice overwrote warranty';exception when serialization_failure then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003442',true);
 begin perform public.solar_warranty_manage('get',null,jsonb_build_object('id',r->>'id'));raise exception 'owner scope leak';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003441',true);
 -- Existing clients preserve guarantee and prune removed materials during a regular sale edit.
 c:=public.solar_warranty_manage('get',null,jsonb_build_object('id',r->>'id'));
 again:=public.solar_invoice_save(gen_random_uuid(),(p-'warranty')||jsonb_build_object('invoiceId',r->'id','expectedRevision',c->'pricingRevision','items','[{"id":-344001,"qty":2,"price":150000}]'::jsonb));
 if again->>'warrantyToken'<>r->>'warrantyToken' or jsonb_array_length(again->'warranty'->'items')<>1 then raise exception 'old client policy preservation';end if;
 c:=public.solar_warranty_manage('get',null,jsonb_build_object('id',r->>'id'));
 perform public.solar_warranty_manage('save',gen_random_uuid(),jsonb_build_object('id',r->>'id','expectedToken',c->>'expectedToken','warranty','{"enabled":false}'::jsonb));
 c:=public.solar_warranty_verify((r->>'warrantyToken')::uuid);if(c->>'enabled')::boolean or(c->'items'->0->'status'->>'active')::boolean then raise exception 'disabled warranty remained active';end if;
 -- A system certificate is posted in the same protected invoice write.
 again:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"System Warranty Customer","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"total":500000,"installerId":"00000000-0000-0000-0000-000000003443","customerAddress":"عنوان اختبار","items":[{"id":-344002,"qty":1,"price":0}],"warranty":{"enabled":true,"items":[{"id":-344002,"duration":10,"unit":"years"}],"maintenance":{"duration":12,"unit":"months"}}}');
 if again->>'warrantyToken' is null then raise exception 'system guarantee missing';end if;
 c:=public.solar_warranty_verify((again->>'warrantyToken')::uuid);if c->>'address'<>'عنوان اختبار' or c->>'installer'<>'Warranty Engineer' then raise exception 'system certificate details';end if;
end $$;
reset role;
do $$declare c jsonb;begin
 if(select count(*) from solar_private.warranty_certificates)<>2 then raise exception 'duplicate certificate';end if;
 if(select qty from products where id=-344001)<>18 or(select qty from products where id=-344002)<>19 then raise exception 'invalid warranty changed stock';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000003441')<>0 then raise exception 'warranty changed cash';end if;
 if has_table_privilege('anon','solar_private.warranty_certificates','select') then raise exception 'certificate table exposed';end if;
 c:=solar_private.warranty_status('2024-01-31','{"duration":1,"unit":"months"}');if c->>'endsExclusive'<>'2024-02-29' then raise exception 'month-end expiry';end if;
 c:=solar_private.warranty_status('2024-02-29','{"duration":1,"unit":"years"}');if c->>'endsExclusive'<>'2025-02-28' or(c->>'active')::boolean then raise exception 'leap-year expiry';end if;
end $$;
set local role anon;
do $$declare c jsonb;begin
 c:=public.solar_warranty_verify(current_setting('test.warranty_token')::uuid);if c->>'customer'<>'Warranty Customer' then raise exception 'anonymous scanner lookup';end if;
 if public.solar_warranty_verify(gen_random_uuid()) is not null then raise exception 'invalid token';end if;
 begin perform public.solar_warranty_manage('get',null,jsonb_build_object('id',current_setting('test.warranty_invoice')));raise exception 'anon edit allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
-- Removing a source invoice revokes its printed QR while retaining an audit copy.
delete from transaction_items where transaction_id=current_setting('test.warranty_invoice')::bigint;
delete from transactions where id=current_setting('test.warranty_invoice')::bigint;
set local role anon;
do $$declare c jsonb;begin c:=public.solar_warranty_verify(current_setting('test.warranty_token')::uuid);if not(c->>'voided')::boolean or(c->>'enabled')::boolean or(c->'items'->0->'status'->>'active')::boolean then raise exception 'deleted guarantee still valid';end if;end $$;
reset role;
do $$begin raise notice 'PASS wholesale/system atomic warranties, retry, optional material/service cover, no financial leakage, private editing/owner scope, stale edit guard, legacy edits, expiry calendar, anonymous scan and deleted invoice revocation';end $$;
rollback;
