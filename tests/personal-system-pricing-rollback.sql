begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412511','مسؤول المنظومة',false,'admin_staff','{"system":true,"installations":true,"tahseel":true,"tahseelFull":true,"profitUsesWholesalePrice":true}','07700000011'),
 ('00000000-0000-0000-0000-000000412512','مهندس',false,'installer','{}','07700000012');
insert into public.products(id,code,name,category,qty,cost) values
 (951825001,'BASIS-SYS','الجهاز','ALL IN ONE',100,385),
 (951825002,'BASIS-PANEL','اللوح','panel',100,127);
insert into solar_private.warehouse_access(user_id,all_warehouses)
 values('00000000-0000-0000-0000-000000412511',true) on conflict(user_id) do update set all_warehouses=true;
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values
 (1,951825001,100),(1,951825002,100) on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
insert into public.customers(id,name,customer_type,owner_id)
 values(951825001,'عميل أساس البيع','system','00000000-0000-0000-0000-000000412511');
insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled)
 values(951825001,430,true),(951825002,710,false);
update solar_private.operation_controls set system_free_pricing=false,system_markup_percent=15 where id;

insert into public.solar_quotes(id,user_id,payload) values
 ('00000000-0000-0000-0000-000000412519','00000000-0000-0000-0000-000000412511',
  '{"markupPercent":"","perPanel":"0","expenses":{"crane":"12","worker":"0","programmer":"0","delivery":"0","electrical":"0","commission":"0"}}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412511',true);
do $$
declare payload jsonb:='{"kind":"system","mode":"credit","party":"عميل أساس البيع","partyId":951825001,"warehouseId":1,
"installerId":"00000000-0000-0000-0000-000000412512","customerAddress":"العراق","items":[{"id":951825001,"qty":1,"price":0}]}';
 answer jsonb; nonce uuid:=gen_random_uuid(); jobs jsonb;
begin
 begin
  perform public.solar_invoice_save(gen_random_uuid(),payload||'{"total":480}');
  raise exception 'accepted a price below the personal system minimum';
 exception when sqlstate 'PT422' then null;end;
 payload:=payload||'{"total":510}';
 answer:=public.solar_invoice_save(nonce,payload);
 assert answer->'cost'='430'::jsonb and answer->'profit'='80'::jsonb,'save did not use configured price';
 assert public.solar_invoice_save(nonce,payload)->'profit'='80'::jsonb,'retry leaked company margin';
 select j into jobs from jsonb_array_elements(public.solar_installation_jobs()) j where j->'id'=answer->'id';
 assert jobs->'cost'='430'::jsonb and jobs->'profit'='80'::jsonb,'wrong installation report';
 perform set_config('test.personal.system',answer->>'id',true);
 payload:=payload||'{"total":100,"items":[{"id":951825002,"qty":1,"price":0}]}';
 begin
  perform public.solar_invoice_save(gen_random_uuid(),payload);
  raise exception 'accepted a price below the private minimum';
 exception when sqlstate 'PT422' then assert sqlerrm !~ '[[:digit:]]','revealed private minimum';end;
 answer:=public.solar_invoice_save(gen_random_uuid(),payload||'{"total":200}');
 assert answer->'cost'='null'::jsonb and answer->'profit'='73'::jsonb,'fallback projected cost or wrong profit';
 select j into jobs from jsonb_array_elements(public.solar_installation_jobs()) j where j->'id'=answer->'id';
 assert jobs->'cost'='null'::jsonb and jobs->'profit'='73'::jsonb,'fallback installation details';
end$$;

do $$
declare form jsonb:='{"systemType":"all_in_one","allInOneQty":"1","allInOnePanelQty":"1","panel":{"id":951825002,"cost":"1"},"allInOne":{"id":951825001,"cost":"1"},"markupPercent":"25"}';
 result jsonb; expenses numeric; defaults jsonb;
begin
 defaults:=public.solar_quote_defaults('get');
 select sum(value::numeric) into expenses from jsonb_each_text(defaults->'expenses');
 expenses:=expenses+(defaults->>'perPanel')::numeric;
 result:=public.solar_limited_quote('preview',form);
 assert result->'errors'='[]'::jsonb and result->'markupPercent'='25'::jsonb,'quote privilege lost';
 assert expenses is not null and (result->>'price')::numeric=round((430+127+expenses)*1.25,2),'quote price used wrong basis';
 result:=public.solar_limited_quote('save',form,gen_random_uuid());
 assert not(result->'payload'->'panel'?'cost') and not(result->'payload'->'allInOne'?'cost'),'mixed draft prices disclosed';
 assert exists(select from jsonb_array_elements(public.solar_limited_quote('list')) d where d->'id'=result->'id'
   and d->'result'->'price'=result->'result'->'price' and not(d->'payload'->'panel'?'cost')),'draft list lost correct price or disclosed cost';
 assert exists(select from jsonb_array_elements(public.solar_limited_quote('list')) d where d->>'id'='00000000-0000-0000-0000-000000412519'
   and jsonb_array_length(d->'result'->'errors')>0
   and (not(d->'payload'?'expenseOverride') or (d->'payload'->'expenseOverride'='true'::jsonb and d->'payload'->'expenses'->>'crane'='12'))),'unfinished old draft broke read or lost its expenses';
 assert not exists(select from public.solar_quotes where user_id=auth.uid()),'raw quote bypass';
end$$;
reset role;
do $$begin
 assert exists(select from public.transactions where id=current_setting('test.personal.system')::bigint and cost=385 and profit=125),'book entries changed';
end$$;
update public.profiles set permissions=permissions-'tahseelFull' where id='00000000-0000-0000-0000-000000412511';
set local role authenticated;
do $$declare q jsonb;begin
 q:=public.solar_limited_quote('preview','{"systemType":"all_in_one","allInOneQty":"1","allInOnePanelQty":"1","panel":{"id":951825002},"allInOne":{"id":951825001},"markupPercent":0}');
 assert q->'errors'='[]'::jsonb and q->'markupPercent'='15'::jsonb,'personal fixed-15 quote allowed a markup override';
end$$;
rollback;
