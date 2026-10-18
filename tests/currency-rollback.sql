-- Run against the isolated fixture database, never against production.
begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003310','FX Admin',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003311','FX Buyer',false,'{"purchase":true,"sale":true,"system":true,"salesDeleteOwn":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003312','FX Engineer',false,'{"exchangeRateEdit":true}','installer');
insert into public.suppliers(id,name) values(-3310,'FX Supplier');
insert into public.customers(id,name,customer_type,owner_id) values(-3310,'FX Customer','wholesale','00000000-0000-0000-0000-000000003311');
insert into public.products(id,code,name,qty,cost) values(-3310,'FX-3310','FX Panel',10,100000),(-3311,'FX-3311','FX Battery',0,0);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003311',true);
do $$begin
 if (public.solar_exchange_rate_get()->>'rate') is not null then raise exception 'FAIL assumed exchange rate';end if;
 begin perform public.solar_exchange_rate_set(1500,0);raise exception 'FAIL unauthorized rate change';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033101','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1500,"expenses":0,"items":[{"id":-3310,"qty":10,"price":80}]}');raise exception 'FAIL unconfigured USD rate';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003310',true);
select public.solar_exchange_rate_set(1500,0);
do $$begin
 begin perform public.solar_exchange_rate_set(1600,0);raise exception 'FAIL stale settings revision';exception when serialization_failure or sqlstate 'PT409' then null;end;
 begin perform public.solar_exchange_rate_set('NaN'::numeric,1);raise exception 'FAIL nonfinite rate';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003311',true);
do $$declare response jsonb;retry jsonb;begin
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033101','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1500,"expenses":0,"items":[{"id":-3310,"qty":10,"price":80}]}');
 perform set_config('fx.purchase',response->>'id',true);
 retry:=public.solar_invoice_save('00000000-0000-0000-0000-000000033101','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1500,"expenses":0,"items":[{"id":-3310,"qty":10,"price":80}]}');
 if retry is distinct from response then raise exception 'FAIL idempotent response';end if;
 if not exists(select 1 from public.products where id=-3310 and qty=20 and cost=110000) then raise exception 'FAIL weighted USD purchase';end if;
 if not exists(select 1 from public.transaction_items where transaction_id=(response->>'id')::bigint and source_price=80 and price=120000 and landed_cost=120000) then raise exception 'FAIL source and IQD line prices';end if;
 if not exists(select 1 from public.transactions where id=(response->>'id')::bigint and total=1200000 and exchange_rate=1500 and source_subtotal=800) then raise exception 'FAIL converted totals';end if;
 begin update public.products set cost=1 where id=-3310;raise exception 'FAIL direct cost tampering';exception when insufficient_privilege then null;end;
 begin update public.transactions set exchange_rate=1600 where id=(response->>'id')::bigint;raise exception 'FAIL direct rate tampering';exception when insufficient_privilege then null;end;
 begin update public.transaction_items set cost=1 where transaction_id=(response->>'id')::bigint;raise exception 'FAIL direct line tampering';exception when insufficient_privilege then null;end;
end $$;
do $$declare response jsonb;begin
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033102','{"kind":"sale","mode":"credit","party":"FX Customer","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"items":[{"id":-3310,"qty":5,"price":150000,"cost":1}]}');
 perform set_config('fx.sale',response->>'id',true);
 if (response->>'cost')::numeric<>550000 or (response->>'profit')::numeric<>200000 then raise exception 'FAIL server cost snapshot';end if;
 if not exists(select 1 from public.products where id=-3310 and qty=15 and cost=110000) then raise exception 'FAIL sale stock';end if;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033103','{"kind":"sale","mode":"credit","sourceCurrency":"USD","exchangeRate":1500,"expenses":0,"items":[{"id":-3310,"qty":1,"price":100}]}');raise exception 'FAIL USD sale';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003310',true);
select public.solar_exchange_rate_set(1600,1);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003311',true);
do $$declare response jsonb;begin
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033104','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"items":[{"id":-3310,"qty":5,"price":150000}]}');
 if not exists(select 1 from public.products where id=-3310 and qty=20 and cost=120000) then raise exception 'FAIL mixed currency weighted average';end if;
 if not exists(select 1 from public.transactions where id=current_setting('fx.sale')::bigint and cost=550000 and profit=200000) then raise exception 'FAIL historic sale changed';end if;
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033105',jsonb_build_object('invoiceId',current_setting('fx.sale')::bigint,'expectedRevision',0,'kind','sale','mode','credit','party','FX Customer','sourceCurrency','IQD','exchangeRate',1,'expenses',0,'items',jsonb_build_array(jsonb_build_object('id',-3310,'qty',5,'price',160000))));
 if (response->>'cost')::numeric<>550000 or (response->>'profit')::numeric<>250000 then raise exception 'FAIL edit revalued historic cost';end if;
 begin perform public.solar_purchase_delete(current_setting('fx.purchase')::bigint,0);raise exception 'FAIL deletion after subsequent movement';exception when serialization_failure or sqlstate 'PT409' then null;end;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033106',jsonb_build_object('invoiceId',current_setting('fx.sale')::bigint,'expectedRevision',0,'kind','sale','mode','credit','sourceCurrency','IQD','expenses',0,'items',jsonb_build_array(jsonb_build_object('id',-3310,'qty',5,'price',150000))));raise exception 'FAIL stale invoice revision';exception when serialization_failure or sqlstate 'PT409' then null;end;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033107','{"kind":"sale","mode":"credit","party":"FX Customer","sourceCurrency":"IQD","exchangeRate":1,"expenses":0,"items":[{"id":-3310,"qty":100,"price":150000}]}');raise exception 'FAIL overselling';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 if not exists(select 1 from public.products where id=-3310 and qty=20 and cost=120000) then raise exception 'FAIL rejected operation changed stock';end if;
end $$;
-- The same request UUID cannot be reused for altered financial input.
do $$begin
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033101','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1600,"expenses":0,"items":[{"id":-3310,"qty":10,"price":80}]}');raise exception 'FAIL changed request replay';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save('00000000-0000-0000-0000-000000033110','{"kind":"purchase","mode":"cash","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1600,"expenses":0,"items":[{"id":-3311,"qty":1,"price":100}]}');raise exception 'FAIL insufficient cash';exception when sqlstate 'P0002' then null;end;
end $$;
-- An independent purchase can be edited/deleted before subsequent stock moves.
do $$declare response jsonb;pid bigint;begin
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033108','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1600,"expenses":20000,"items":[{"id":-3311,"qty":2,"price":100}]}');pid:=(response->>'id')::bigint;
 if not exists(select 1 from public.products where id=-3311 and qty=2 and cost=170000) then raise exception 'FAIL landed expenses';end if;
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033109',jsonb_build_object('invoiceId',pid,'expectedRevision',0,'kind','purchase','mode','credit','party','FX Supplier','sourceCurrency','USD','exchangeRate',1600,'expenses',20000,'items',jsonb_build_array(jsonb_build_object('id',-3311,'qty',4,'price',100))));
 if not exists(select 1 from public.products where id=-3311 and qty=4 and cost=165000) then raise exception 'FAIL purchase edit restores original basis';end if;
 perform public.solar_purchase_delete(pid,(response->>'pricingRevision')::bigint);
 if not exists(select 1 from public.products where id=-3311 and qty=0 and cost=0) then raise exception 'FAIL purchase deletion restore';end if;
end $$;
do $$declare token text;begin
 token:=solar_private.sale_delete_data(current_setting('fx.sale')::bigint)->>'token';
 perform public.solar_sale_delete(current_setting('fx.sale')::bigint,token);
 if not exists(select 1 from public.products where id=-3310 and qty=25 and cost=118000) then raise exception 'FAIL historical cost restored into weighted stock';end if;
end $$;
-- System sales also receive a server snapshot; later USD purchases cannot
-- change installation cost/profit. Cash remains receipt-driven for systems.
do $$declare response jsonb;sid bigint;begin
 response:=public.solar_invoice_save('00000000-0000-0000-0000-000000033111','{"kind":"system","mode":"credit","party":"FX Customer","sourceCurrency":"IQD","exchangeRate":1,"total":200000,"expenses":10000,"installerId":"00000000-0000-0000-0000-000000003312","customerAddress":"Test address","items":[{"id":-3310,"qty":1,"price":0,"cost":1}]}');sid:=(response->>'id')::bigint;
 if (response->>'cost')::numeric<>118000 or (response->>'profit')::numeric<>72000 then raise exception 'FAIL system cost snapshot';end if;
 perform public.solar_invoice_save('00000000-0000-0000-0000-000000033112','{"kind":"purchase","mode":"credit","party":"FX Supplier","sourceCurrency":"USD","exchangeRate":1600,"expenses":0,"items":[{"id":-3310,"qty":1,"price":100}]}');
 if not exists(select 1 from public.transactions where id=sid and cost=118000 and profit=72000) then raise exception 'FAIL system was repriced';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003312',true);
do $$begin
 begin perform public.solar_exchange_rate_set(1700,2);raise exception 'FAIL engineer rate permission';exception when insufficient_privilege then null;end;
 begin perform public.solar_exchange_rate_get();raise exception 'FAIL engineer financial access';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
