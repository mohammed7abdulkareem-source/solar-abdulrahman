-- Disposable local database on V4.1 + atomic configuration, BEFORE category migration.
-- psql -f this file applies the category migration inside a transaction and rolls back.
\set ON_ERROR_STOP on
\o /dev/null
begin;
load 'safeupdate';
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)
values('00000000-0000-0000-0000-000000411101','Category Notice Test',true,'admin_staff','07700411101',true,'{}');
insert into public.brands(id,name)values(-411101,'CATEGORY BRAND');
insert into public.products(id,name,code,brand_id,category,qty,cost)values
(-411101,'15KW','CATEGORY-0003',-411101,'بطارية',0,0),
(-411102,'8KW','CATEGORY-0004',-411101,'انفيرتر',0,0),
(-411103,'600W','CATEGORY-0005',-411101,'',0,0),
(-411104,'Ambiguous material','CATEGORY-AMBIGUOUS',-411101,'ألواح',0,0);
-- Some legacy schemas do not have the production code UNIQUE index. Exercise
-- the explicit ambiguity guard where duplicate codes are physically possible.
insert into public.products(id,name,code,brand_id,category,qty,cost)values
(-411105,'Ambiguous material','CATEGORY-AMBIGUOUS',-411101,'بطارية',0,0)on conflict do nothing;
insert into public.solar_notifications(user_id,event,title,body,details,warehouse_id,read_at,created_at)values
('00000000-0000-0000-0000-000000411101','purchase_received','Original heading','Original body',
'{"type":"purchase_received","items":[{"name":"15KW","model":"CATEGORY-0003","brand":"CATEGORY BRAND","qty":2.5},{"name":"15KW renamed","model":"CATEGORY-0003","brand":"CATEGORY BRAND","qty":1},{"name":"15KW","model":"CATEGORY-0003","brand":"OTHER BRAND","qty":3},{"name":"8KW","model":"UNMATCHED-0004","brand":"CATEGORY BRAND","qty":4},{"name":"600W","model":"CATEGORY-0005","brand":"CATEGORY BRAND","qty":5},{"name":"Ambiguous material","model":"CATEGORY-AMBIGUOUS","brand":"CATEGORY BRAND","qty":6}]}',1,'2026-11-01 09:00Z','2026-10-31 09:00Z'),
('00000000-0000-0000-0000-000000411101','wholesale_prices_updated','Original prices heading','Original prices body',
'{"type":"wholesale_prices_updated","currency":"IQD","items":[{"name":"8KW","model":"CATEGORY-0004","brand":"CATEGORY BRAND","minPrice":123456.78,"enabled":true},{"name":"600W","model":"CATEGORY-0005","brand":"CATEGORY BRAND","minPrice":null,"enabled":false}]}',null,null,'2026-10-31 09:00Z');
create temporary table before_notices as select id,to_jsonb(n)as row from public.solar_notifications n;
create temporary table before_financial as
select 'transactions'::text as name,md5(coalesce(string_agg(to_jsonb(t)::text,','order by id),''))as digest from public.transactions t
union all select 'transaction_items',md5(coalesce(string_agg(to_jsonb(t)::text,','order by id),''))from public.transaction_items t;
create temporary table before_deliveries as select * from solar_private.push_deliveries;
\ir ../supabase/migrations/20261116191044_material_notification_categories_v411.sql

do $$declare n public.solar_notifications;old_row jsonb;normalized jsonb;begin
 assert(select count(*)from public.solar_notifications)=(select count(*)from before_notices),'Category migration created/deleted notices';
 for n in select * from public.solar_notifications loop
  select row into old_row from before_notices where id=n.id;
  assert to_jsonb(n)-'details'=old_row-'details','Changed notice recipient, timestamp, read state, title, body or scope';
  normalized:=to_jsonb(n)->'details';
  if normalized is distinct from old_row->'details'then
   assert n.event in('purchase_received','wholesale_prices_updated'),'Changed unrelated notification';
   select jsonb_set(normalized,'{items}',jsonb_agg(x.item-'category'order by x.ordinality))into normalized
    from jsonb_array_elements(normalized->'items')with ordinality as x(item,ordinality);
   assert normalized=old_row->'details','Modified historical fields other than additive category';
  end if;
 end loop;
 select * into n from public.solar_notifications where user_id='00000000-0000-0000-0000-000000411101'and event='purchase_received';
 assert n.details->'items'->0->>'category'='بطارية','Exact code/name/brand match did not add category';
 for i in 1..4 loop assert not(n.details->'items'->i?'category'),'Guessed category for mismatched/unknown/empty source';end loop;
 assert jsonb_array_length(n.details->'items')=6,'Ambiguous join multiplied a historical item';
 if(select count(*)from public.products where code='CATEGORY-AMBIGUOUS')>1 then
  assert not(n.details->'items'->5?'category'),'Guessed category for ambiguous identity';
 end if;
 select * into n from public.solar_notifications where user_id='00000000-0000-0000-0000-000000411101'and event='wholesale_prices_updated';
 assert n.details->'items'->0->>'category'='انفيرتر','Price notice category missing';
 assert n.details->'items'->0->>'model'='CATEGORY-0004','Legacy reference unexpectedly changed';
 assert not(n.details->'items'->1?'category'),'Empty source category invented';
 assert not exists((select * from solar_private.push_deliveries except select * from before_deliveries)union all(select * from before_deliveries except select * from solar_private.push_deliveries)),'Category migration changed queued deliveries';
 assert(select digest from before_financial where name='transactions')=(select md5(coalesce(string_agg(to_jsonb(t)::text,','order by id),''))from public.transactions t),'Financial header changed';
 assert(select digest from before_financial where name='transaction_items')=(select md5(coalesce(string_agg(to_jsonb(t)::text,','order by id),''))from public.transaction_items t),'Financial line changed';
 -- The new shape is accepted; forbidden financial fields remain rejected.
 update public.solar_notifications set details='{"type":"wholesale_prices_updated","currency":"IQD","items":[{"name":"15KW","category":"بطارية","brand":"CATEGORY BRAND","minPrice":250000,"enabled":true}]}'where id=n.id;
 begin
  update public.solar_notifications set details=jsonb_set(details,'{items,0,cost}','100')where id=n.id;
  raise exception 'Financial field passed whitelist';
 exception when check_violation then null;end;
 assert not has_column_privilege('authenticated','public.solar_notifications','details','UPDATE'),'Details update privilege changed';
 assert not has_function_privilege('authenticated','solar_private.notify_wholesale_prices(bigint[])','EXECUTE'),'Price emitter exposed';
 assert not has_function_privilege('authenticated','solar_private.publish_purchase_notice(bigint,boolean)','EXECUTE'),'Purchase emitter exposed';
end$$;
set constraints all immediate;
rollback;
\echo PASS categories: exact legacy identity only; preserved entire noncategory payload/read state/recipients/timestamps/push queue/financial history; safeupdate enabled; new shape and private emitter permissions.
