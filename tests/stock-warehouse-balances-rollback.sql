\set ON_ERROR_STOP on
begin;
create function pg_temp.balance_user(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((416250+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (pg_temp.balance_user(1),'مدير الرصيد',true,true,'admin','{}'),
 (pg_temp.balance_user(2),'مستخدم مخزنين',false,true,'admin_staff','{"stock":true}'),
 (pg_temp.balance_user(3),'مسؤول مخزن واحد',false,true,'warehouse','{}'),
 (pg_temp.balance_user(4),'بائع فقط',false,true,'admin_staff','{"sale":true}'),
 (pg_temp.balance_user(5),'التحصيل فقط',false,true,'admin_staff','{"tahseel":true}'),
 (pg_temp.balance_user(6),'منصّب',false,true,'installer','{"stock":true}'),
 (pg_temp.balance_user(7),'متوقف',false,false,'admin_staff','{"stock":true}');
insert into solar_private.warehouses(id,name,code,active) overriding system value values
 (-416251,'مخزن اختيار التفصيل','BAL-A',true),(-416252,'مخزن متوقف مع رصيد','BAL-B',false),(-416253,'مخزن خارج الصلاحية','BAL-C',true);
insert into solar_private.warehouse_access(user_id,warehouse_ids) values
 (pg_temp.balance_user(2),array[-416251,-416252]::bigint[]),(pg_temp.balance_user(3),array[-416251]::bigint[]);
insert into public.products(id,code,name,qty,cost) values(-416251,'BALANCED-1','مادة الرصيد',0,1000),(-416252,'BALANCED-2','مادة صفرية',0,10);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty,reserved_qty) values
 (-416251,-416251,2.000045,0.125),(-416252,-416251,0,3.25),(-416253,-416251,11,0),
 (-416251,-416252,0,0);
set local role authenticated;
do $checks$
declare result jsonb;legacy jsonb; rows jsonb; item jsonb;x jsonb;actor int;
begin
 for actor in 1..3 loop
  perform set_config('request.jwt.claim.sub',pg_temp.balance_user(actor)::text,true);
  legacy:=public.solar_inventory('stock',null,'{}');
  result:=public.solar_inventory('stock',null,'{"byWarehouse":true}');
  assert result-'warehouseBalances'=legacy and not(legacy?'warehouseBalances');
  rows:=result->'warehouseBalances';
  assert jsonb_typeof(rows)='array';
  assert not exists(select 1 from jsonb_array_elements(rows) r where r-array['warehouseId','productId','qty','reservedQty','bookQty']<>'{}'::jsonb
    or (r->>'bookQty')::numeric<>(r->>'qty')::numeric+(r->>'reservedQty')::numeric
    or (r->>'qty')::numeric=0 and (r->>'reservedQty')::numeric=0);
  select v into item from jsonb_array_elements(result->'products') v where v->>'id'='-416251';
  assert (item->>'qty')::numeric=(select sum((v->>'qty')::numeric) from jsonb_array_elements(rows) v where v->>'productId'='-416251');
  assert (item->>'reservedQty')::numeric=(select sum((v->>'reservedQty')::numeric) from jsonb_array_elements(rows) v where v->>'productId'='-416251');
  assert (item->>'bookQty')::numeric=(select sum((v->>'bookQty')::numeric) from jsonb_array_elements(rows) v where v->>'productId'='-416251');
  assert (select (v->>'qty')::numeric from jsonb_array_elements(rows) v where v->>'productId'='-416251' and v->>'warehouseId'='-416251')=2.000045;
  assert (select count(*) from jsonb_array_elements(rows) v where v->>'productId'='-416251')=4-actor;
  assert not exists(select 1 from jsonb_array_elements(rows) v where v->>'productId'='-416252');
  if actor=3 then assert not(item?|array['cost','bookCost','cost_basis','companyQty']);end if;
  result:=public.solar_inventory('stock',null,'{"warehouseId":-416251,"byWarehouse":true}');
  assert not exists(select 1 from jsonb_array_elements(result->'warehouseBalances') v where v->>'warehouseId'<>'-416251');
  select v into x from jsonb_array_elements(result->'warehouseBalances') v where v->>'productId'='-416251';
  assert (x->>'bookQty')::numeric=2.125045;
  if actor<>1 then
   begin perform public.solar_inventory('stock',null,'{"warehouseId":-416253,"byWarehouse":true}');raise exception 'Foreign location accepted';
   exception when insufficient_privilege then null;end;
  end if;
 end loop;
 perform set_config('request.jwt.claim.sub',pg_temp.balance_user(4)::text,true);
 legacy:=public.solar_inventory('stock',null,'{}');assert not (legacy?'warehouseBalances');
 for actor in 4..7 loop
  perform set_config('request.jwt.claim.sub',pg_temp.balance_user(actor)::text,true);
  begin perform public.solar_inventory('stock',null,'{"byWarehouse":true}');raise exception 'Unauthorized stock breakdown';
  exception when insufficient_privilege then null;end;
 end loop;
end$checks$;
rollback;
\echo PASS opt-in stock report, exact warehouse totals, reserved-only and inactive locations, role scoping and legacy shape.
