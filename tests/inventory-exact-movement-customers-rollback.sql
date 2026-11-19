-- Synthetic historical rows in a disposable database. All changes roll back.
\set ON_ERROR_STOP on
begin;
create function pg_temp.uid(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((419700+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,user_type,is_admin,active,permissions) values
 (pg_temp.uid(1),'مدير الحركة','admin_staff',true,true,'{}'),
 (pg_temp.uid(2),'صاحب الحركات','admin_staff',false,true,'{"stockMovement":true}'),
 (pg_temp.uid(3),'مستخدم آخر','admin_staff',false,true,'{"stockMovement":true}'),
 (pg_temp.uid(4),'مخزن الحركة','warehouse',false,true,'{}'),
 (pg_temp.uid(5),'مستخدم التحصيل','admin_staff',false,true,'{"tahseel":true}');
insert into public.products(id,code,name,qty,cost) values
 (-419701,'M419701','مادة 15KW',0,19),(-419702,'M419702','مادة 15KW',0,23);
-- Current writes refuse duplicate names. These two accounts predate that safeguard.
alter table public.customers disable trigger solar_customer_guard;
insert into public.customers(id,name,customer_type,owner_id) values
 (-419701,'حساب مكرر 4197','wholesale',pg_temp.uid(2)),(-419702,'حساب مكرر 4197','system',pg_temp.uid(3)),
 (-419703,'عميل قديم فريد 4197','wholesale',pg_temp.uid(2)),(-419704,'اسم خاص محدّث 4197','wholesale',pg_temp.uid(3)),
 (-419705,'حساب خارج المادة 4197','wholesale',pg_temp.uid(3));
alter table public.customers enable trigger solar_customer_guard;
-- Seed immutable historic product lines directly; warehouse accounting stays enabled.
insert into public.transactions(id,kind,warehouse_id,party_name,created_by,cashbox_user_id,total,cash,created_at)
select -4197100-n,'purchase',n,'مورد',pg_temp.uid(1),pg_temp.uid(1),1000,false,'2024-02-26T09:00Z'::timestamptz from generate_series(1,2) n;
insert into public.transaction_items(id,transaction_id,product_id,product_name,qty,price,cost)
select -4197200-n*10-p,-4197100-n,-419700-p,'مادة 15KW',200,19,19 from generate_series(1,2) n cross join generate_series(1,2) p;
insert into public.transactions(id,kind,warehouse_id,party_id,party_name,created_by,cashbox_user_id,total,cash,created_at)
select -4197300-n,kind,w,party,name,pg_temp.uid(owner),pg_temp.uid(owner),15,false,at::timestamptz from(values
 (1,'sale',1,-419701,'اسم قديم على الوصل',2,'2024-02-27T20:59:59Z'),
 (2,'system',1,-419702,'حساب مكرر 4197',3,'2024-02-27T21:00:00Z'),
 (3,'sale',1,null,'حساب مكرر 4197',2,'2024-02-28T09:00Z'),
 (4,'sale',1,null,'عميل قديم فريد 4197',2,'2024-02-28T10:00Z'),
 (5,'sale',1,-419799,'عميل قديم فريد 4197',2,'2024-02-28T11:00Z'),
 (6,'sale',1,null,'اسم غير معروف 4197',2,'2024-02-28T12:00Z'),
 (7,'sale',1,-419704,'الاسم الظاهر على الوصولات فقط',2,'2024-02-28T13:00Z'),
 (8,'sale',1,-419705,'حساب خارج المادة 4197',3,'2024-02-28T14:00Z'),
 (9,'sale',2,-419701,'مخزن ثان',3,'2024-02-28T15:00Z')
) t(n,kind,w,party,name,owner,at);
insert into public.transaction_items(id,transaction_id,product_id,product_name,qty,price,cost)
select -4197400-n,-4197300-n,case when n=8 then -419702 else -419701 end,'مادة 15KW',1,15,7 from generate_series(1,9) n;
set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.uid(1)::text,true);
do $test$
declare
 args jsonb:='{"productId":-419701}'; list jsonb; exact jsonb; original jsonb; base jsonb; item jsonb;
begin
 assert not has_function_privilege('authenticated','solar_private.inventory_customer_movements(text,jsonb)','execute');
 assert not has_function_privilege('anon','solar_private.inventory_customer_movements(text,jsonb)','execute');
 original:=public.solar_inventory('movements',null,args);
 list:=public.solar_inventory('movement_customers',null,args);
 assert jsonb_array_length(list)=4 and (select count(*)=2 from jsonb_array_elements(list) s where s->>'name'='حساب مكرر 4197');
 assert not exists(select from jsonb_array_elements(list) s where s-'key'-'name'-'hint'<>'{}'::jsonb or s->>'key'='customer:-419705');
 for item in select value from jsonb_array_elements(list) loop
  exact:=public.solar_inventory('movements',null,args||jsonb_build_object('customerKey',item->>'key'));
  assert jsonb_array_length(exact)>0;
  select jsonb_agg(r order by seq) into base from jsonb_array_elements(original) with ordinality x(r,seq)
   where exists(select from jsonb_array_elements(exact) e where e-'customerKey'=r);
  assert base=(select jsonb_agg(r-'customerKey' order by seq) from jsonb_array_elements(exact) with ordinality x(r,seq));
  assert not exists(select from jsonb_array_elements(exact) e where e->>'customerKey'<>item->>'key');
 end loop;
 exact:=public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419703"}');
 assert jsonb_array_length(exact)=1 and exact#>>'{0,id}'='line:-4197404'; -- unique legacy name only
 exact:=public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419701","warehouseId":1}');
 assert jsonb_array_length(exact)=1 and exact#>>'{0,id}'='line:-4197401'; -- ambiguous name excluded
 exact:=public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419702","from":"2024-02-28","to":"2024-02-28"}');
 assert jsonb_array_length(exact)=1 and exact#>>'{0,id}'='line:-4197402';
 assert public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419701","warehouseId":1,"from":"2024-02-28"}')='[]'::jsonb;
 assert public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419705"}')='[]'::jsonb;
 assert public.solar_inventory('movements',null,args)=original;
 begin perform public.solar_inventory('movements',null,args||'{"customerKey":""}');raise exception 'empty exact key accepted';exception when invalid_parameter_value then null;end;
 begin perform public.solar_inventory('movement_customers',null,'{}');raise exception 'missing material accepted';exception when invalid_parameter_value then null;end;
 perform set_config('request.jwt.claim.sub',pg_temp.uid(2)::text,true);
 list:=public.solar_inventory('movement_customers',null,args);
 assert jsonb_array_length(list)=3 and not list::text like '%اسم خاص محدّث%';
 assert exists(select from jsonb_array_elements(list) s where s->>'name'='الاسم الظاهر على الوصولات فقط');
 assert public.solar_inventory('movements',null,args||'{"customerKey":"customer:-419702"}')='[]'::jsonb;
 perform set_config('request.jwt.claim.sub',pg_temp.uid(4)::text,true);
 list:=public.solar_inventory('movement_customers',null,args||'{"warehouseId":1}');
 assert jsonb_array_length(list)=4 and not list::text like '%اسم خاص محدّث%';
 begin perform public.solar_inventory('movement_customers',null,args||'{"warehouseId":2}');raise exception 'forbidden warehouse accepted';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',pg_temp.uid(5)::text,true);
 begin perform public.solar_inventory('movement_customers',null,args);raise exception 'quote user accepted';exception when insufficient_privilege then null;end;
 raise notice 'PASS exact movement identities, dates, warehouses, ownership, legacy linkage, private labels, preserved order/balances, ACL';
end $test$;
rollback;
