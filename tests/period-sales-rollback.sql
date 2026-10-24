\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003710','مدير الفترة',true,'admin_staff','07700003710','{}'),
('00000000-0000-0000-0000-000000003711','بائع الفترة',false,'admin_staff','07700003711','{"sale":true,"system":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000003712','بائع آخر',false,'admin_staff','07700003712','{"sale":true}'),
('00000000-0000-0000-0000-000000003713','سجل فقط',false,'admin_staff','07700003713','{"sale":true,"salesHistory":true}'),
('00000000-0000-0000-0000-000000003714','مهندس الفترة',true,'installer','07700003714','{}'),
('00000000-0000-0000-0000-000000003715','مخزن الفترة',false,'warehouse','07700003715','{}'),
('00000000-0000-0000-0000-000000003716','بدون صلاحية',false,'admin_staff','07700003716','{}');
insert into brands(id,name) values(-371001,'FULLMAX');
insert into products(id,code,name,brand_id,category,qty,cost) values
(-371001,'0002','مادة بنفس الاسم',-371001,'ألواح',1000,10),
(-371002,'0010','مادة بنفس الاسم',-371001,'ألواح',1000,20),
(-371003,'0001','مادة كسرية',-371001,'مستلزمات',1000,30);
insert into customers(id,name,customer_type,owner_id) values
(-371001,'عميل الفترة','wholesale','00000000-0000-0000-0000-000000003711'),
(-371002,'منظومة الفترة','system','00000000-0000-0000-0000-000000003711'),
(-371003,'عميل مستخدم آخر','wholesale','00000000-0000-0000-0000-000000003712'),
(-371004,'عميل السجل فقط','wholesale','00000000-0000-0000-0000-000000003713');
insert into suppliers(id,name) values(-371001,'مورد رصيد لاحق');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003711',true);
do $$declare i integer;r jsonb;begin
 for i in 1..40 loop
  r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":2,"price":100}]}');
  update transactions set created_at='2026-10-24T12:00Z'::timestamptz+i*interval '1 second' where id=(r->>'id')::bigint;
 end loop;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":1,"price":200}]}');
 update transactions set created_at='2026-10-24T20:59:59Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":4,"price":200}]}');
 update transactions set created_at='2026-10-24T21:00:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-371002,"party":"منظومة الفترة","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003714","customerAddress":"عنوان","total":500000,"items":[{"id":-371001,"qty":5,"price":0},{"id":-371002,"qty":1,"price":0}]}');
 update transactions set created_at='2026-10-24T14:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371002,"qty":3,"price":100},{"id":-371003,"qty":1.125,"price":100}]}');
 update transactions set created_at='2026-10-24T15:00Z' where id=(r->>'id')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371001,"party":"عميل الفترة","mode":"credit","warehouseId":1,"items":[{"id":-371003,"qty":0.001,"price":0}]}');
 update transactions set created_at='2026-10-24T15:01Z' where id=(r->>'id')::bigint;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003712',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371003,"party":"عميل مستخدم آخر","mode":"credit","warehouseId":1,"items":[{"id":-371001,"qty":7,"price":999999}]}');
 update transactions set created_at='2026-10-24T16:00Z' where id=(r->>'id')::bigint;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003713',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-371004,"party":"عميل السجل فقط","mode":"credit","warehouseId":1,"items":[{"id":-371002,"qty":2,"price":100}]}');
 update transactions set created_at='2026-10-24T17:00Z' where id=(r->>'id')::bigint;
end$$;
update profiles set permissions='{"salesHistory":true}' where id='00000000-0000-0000-0000-000000003713';
-- A fixture transfer keeps company quantity unchanged and creates a stock scope difference.
select solar_private.change_warehouse_stock(1,-371001,-25);
select solar_private.change_warehouse_stock((select id from solar_private.warehouses where not is_primary order by id limit 1),-371001,25);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003711',true);
do $$declare r jsonb;a jsonb;begin
 r:=public.solar_sales_period('','','2026-10-24','2026-10-24','');
 if(r->'summary'->>'invoiceCount')::integer<>44 or(r->'summary'->>'materialCount')::integer<>3 or(r->'summary'->>'quantitySold')::numeric<>91.126 then raise exception 'FAIL all pages, distinct products or exact fractional quantities %',r;end if;
 if(r->'summary'->>'invoiceCount')::integer<>(public.solar_sales_history('','','2026-10-24','2026-10-24','',0)->>'count')::integer then raise exception 'FAIL report vs archive scope';end if;
 if r::text~'"(cost|cost_basis|price|profit|amount|total)"' then raise exception 'FAIL report monetary data';end if;
 if r->'rows'->0->>'code'<>'0001' or r->'rows'->1->>'code'<>'0002' or r->'rows'->2->>'code'<>'0010' then raise exception 'FAIL numeric code order';end if;
 select value into a from jsonb_array_elements(r->'rows') where(value->>'productId')::bigint=-371001;
 if(a->>'quantitySold')::numeric<>86 or(a->>'remainingQty')::numeric<>878 then raise exception 'FAIL current allowed warehouse stock %',a;end if;
 r:=public.solar_sales_period('','sale','2026-10-24','2026-10-24','');
 if(r->'summary'->>'quantitySold')::numeric<>85.126 then raise exception 'FAIL wholesale filter';end if;
 r:=public.solar_sales_period('','system','2026-10-24','2026-10-24','pending');
 if(r->'summary'->>'invoiceCount')::integer<>1 or(r->'summary'->>'quantitySold')::numeric<>6 then raise exception 'FAIL system/status quantities';end if;
 r:=public.solar_sales_period('','','2026-10-25','2026-10-25','');
 if(r->'summary'->>'invoiceCount')::integer<>1 or(r->'summary'->>'quantitySold')::numeric<>4 then raise exception 'FAIL Baghdad midnight boundary';end if;
 r:=public.solar_sales_period('مستخدم آخر','','2026-10-24','2026-10-24','');
 if(r->'summary'->>'invoiceCount')::integer<>0 then raise exception 'FAIL other user search revealed materials';end if;
 begin perform public.solar_sales_period('','','2026-10-25','2026-10-24','');raise exception 'FAIL reversed range';exception when invalid_parameter_value then null;end;
 begin perform public.solar_sales_period('','purchase');raise exception 'FAIL invalid kind';exception when invalid_parameter_value then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003713',true);
do $$declare r jsonb;begin
 r:=public.solar_sales_period('','','2026-10-24','2026-10-24','');
 if(r->'summary'->>'quantitySold')::numeric<>2 or(r->>'canViewRemaining')::boolean or r->'rows'->0->'remainingQty'<>'null'::jsonb then raise exception 'FAIL history-only remaining privacy';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003710',true);
do $$declare r jsonb;a jsonb;begin
 r:=public.solar_sales_period('','','2026-10-24','2026-10-24','');
 if(r->'summary'->>'quantitySold')::numeric<>100.126 or(r->'summary'->>'invoiceCount')::integer<>46 then raise exception 'FAIL admin quantities';end if;
 select value into a from jsonb_array_elements(r->'rows') where(value->>'productId')::bigint=-371001;
 if(a->>'remainingQty')::numeric<>903 then raise exception 'FAIL admin current company stock';end if;
 -- A purchase outside the sales period changes current remaining, never period sales.
 perform public.solar_invoice_save(gen_random_uuid(),'{"kind":"purchase","partyId":-371001,"party":"مورد رصيد لاحق","mode":"credit","warehouseId":1,"sourceCurrency":"IQD","items":[{"id":-371001,"qty":17,"price":10}]}');
 r:=public.solar_sales_period('','','2026-10-24','2026-10-24','');
 select value into a from jsonb_array_elements(r->'rows') where(value->>'productId')::bigint=-371001;
 if(a->>'remainingQty')::numeric<>920 or(a->>'quantitySold')::numeric<>93 then raise exception 'FAIL current remaining vs period sales separation';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003714',true);
do $$begin begin perform public.solar_sales_period();raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003715',true);
do $$begin begin perform public.solar_sales_period();raise exception 'FAIL warehouse';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003716',true);
do $$begin begin perform public.solar_sales_period();raise exception 'FAIL unauthorized';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS full-period quantities, exact fractions, Baghdad dates, archive-matched ownership, kind/status filters, scoped current remaining, no monetary fields
rollback;
