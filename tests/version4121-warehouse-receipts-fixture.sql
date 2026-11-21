-- Isolated QA dataset with operational states and identifiable financial data.
\set ON_ERROR_STOP on
begin;
do $$begin
 if current_database()<>'solar_v4121_warehouse_docs_browser' then raise exception 'Requires the isolated warehouse receipt database'; end if;
end$$;
insert into profiles(id,username,display_name,is_admin,active,user_type,permissions,phone)
 values('00000000-0000-0000-0000-000000412101','v4121warehouse','أمين مخزن تجريبي',false,true,'warehouse','{}','07700000001');
insert into solar_private.warehouse_access(user_id,warehouse_ids)
 values('00000000-0000-0000-0000-000000412101',array[1]::bigint[]);
insert into products(id,code,name,category,qty,cost) values
 (-412101,'SLIP-QA-A','لوح وثائق المخزن','ألواح',200,197531),
 (-412102,'SLIP-QA-B','بطارية وثائق المخزن','بطاريات',200,196421);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)
 select 1,id,qty from products where id in(-412101,-412102)
 on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into customers(id,name,phone,customer_type,owner_id)
 select -412100-i,'عميل الاختبار المخزني '||i,'0770000000'||i,'wholesale','00000000-0000-0000-0000-000000400101'::uuid from generate_series(1,3) i;
do $$
declare worker uuid:='00000000-0000-0000-0000-000000412101';admin_id uuid:='00000000-0000-0000-0000-000000400101';
 saved jsonb; r jsonb; lines jsonb;
begin
 for i in 1..3 loop
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  saved:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object(
   'kind','sale','warehouseId',1,'mode','credit','partyId',-412100-i,'party','عميل الاختبار المخزني '||i,
   'notes','PRIVATE-COMMERCIAL-NOTE','items',jsonb_build_array(jsonb_build_object('id',-412101,'qty',i+1,'price',987654))));
  if i>1 then
   perform set_config('request.jwt.claim.sub',worker::text,true);
   r:=public.solar_warehouse_orders('@id:'||(saved->>'id'),'')->'rows'->0;
   if i=2 then perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','ready');
   else
    select jsonb_agg(jsonb_build_object('lineId',x->'lineId','productId',x->'productId','qty',x->'qty')) into lines from jsonb_array_elements(r->'items') x;
    perform public.solar_warehouse_action((r->>'id')::bigint,r->>'token','save',lines||'[{"productId":-412102,"qty":1}]'::jsonb,'إضافة بطارية للتجهيز');
   end if;
  end if;
 end loop;
end$$;
-- Create, prepare, cancel or reverse through the supported inventory workflow.
do $$
declare admin_id uuid:='00000000-0000-0000-0000-000000400101';worker uuid:='00000000-0000-0000-0000-000000412101';
 id_for_request uuid; source_id bigint; target_id bigint; quantity numeric; item_revision bigint;
begin
 for n in 11..15 loop
  id_for_request:=('00000000-0000-0000-0000-0000004121'||lpad(n::text,2,'0'))::uuid;
  source_id:=case when n=15 then 2 else 1 end;target_id:=case when n=15 then 1 else 2 end;
  quantity:=case when n=15 then 1 else 4 end;
  select revision into item_revision from solar_private.warehouse_stocks where warehouse_id=source_id and product_id=-412101;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.solar_inventory('transfer',id_for_request,jsonb_build_object('fromId',source_id,'toId',target_id,
    'items',jsonb_build_array(jsonb_build_object('productId',-412101,'qty',quantity,'revision',item_revision)),'note','تعليمات مناولة تجريبية'));
  if n in(12,14) then
   perform set_config('request.jwt.claim.sub',worker::text,true);
   perform public.solar_inventory('prepare_transfer',gen_random_uuid(),jsonb_build_object('id',id_for_request,'expectedRevision',0));
  end if;
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  if n=13 then perform public.solar_inventory('cancel_transfer',gen_random_uuid(),jsonb_build_object('id',id_for_request,'expectedRevision',0));end if;
  if n=14 then perform public.solar_inventory('reverse_transfer',gen_random_uuid(),jsonb_build_object('id',id_for_request,'expectedRevision',1));end if;
 end loop;
end$$;
commit;
