-- Run on disposable combined V4.1 browser clone before the category migration.
-- The final output line is the migration baseline consumed by the category test:
-- python /workspace/solar-review/v359/db.py solar_v411_browser tests/version411-browser-fixture.sql | tail -n 1 > /workspace/solar-review/v411/category-before.json
\set ON_ERROR_STOP on
begin;
do $$begin if current_database()<>'solar_v411_browser' then raise exception 'Use solar_v411_browser only';end if;end$$;
insert into brands(id,name)values(-411101,'FULLMAX نوع وبراند');
insert into products(id,code,name,brand_id,category,qty,cost)values
(-411101,'PRIVATE-CODE-V411-BATTERY','بطارية طاقة منزلية طويلة الاسم 5KW',-411101,'بطارية',3,9001),
(-411102,'PRIVATE-CODE-V411-INVERTER','انفيرتر مركزي تجريبي 10KW',-411101,'انفيرتر',3,9002),
(-411103,'PRIVATE-CODE-V411-PANEL','ألواح شمسية عالية الكفاءة 600W',-411101,'ألواح',3,9003);
update solar_private.warehouse_stocks set qty=0 where product_id in(-411101,-411102,-411103);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)select 410001,id,qty from products where id in(-411101,-411102,-411103);
insert into solar_notifications(id,user_id,event,title,body,details,warehouse_id,created_at,read_at)values
('41190000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000410103','purchase_received','إشعار قديم مطابق','رمز قديم: PRIVATE-CODE-V411-BATTERY','{"type":"purchase_received","items":[{"name":"بطارية طاقة منزلية طويلة الاسم 5KW","model":"PRIVATE-CODE-V411-BATTERY","brand":"FULLMAX نوع وبراند","qty":2}]}',410001,now()-interval'2 minutes',null),
('41190000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000410103','purchase_received','إشعار قديم غير مطابق','رمز قديم: UNMATCHED-LEGACY-CODE','{"type":"purchase_received","items":[{"name":"مادة قديمة غير مطابقة للاختبار","model":"UNMATCHED-LEGACY-CODE","brand":"براند قديم","qty":4}]}',410001,now()-interval'1 minute','2026-11-16T12:00:00Z');
commit;
select jsonb_build_object(
 'financial',md5(jsonb_build_array(
  (select jsonb_agg(to_jsonb(t)order by id)from transactions t),
  (select jsonb_agg(to_jsonb(t)order by id)from transaction_items t),
  (select jsonb_agg(to_jsonb(t)order by id)from products t),
  (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t))::text),
 'notices',(select jsonb_agg(to_jsonb(n)order by id)from solar_notifications n where id in('41190000-0000-0000-0000-000000000001','41190000-0000-0000-0000-000000000002')));
