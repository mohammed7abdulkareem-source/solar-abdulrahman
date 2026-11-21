-- Run on an isolated fixture database. All customers, receipts and writes roll back.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000417701','Test admin',true,'admin_staff',true,'{}'),
 ('00000000-0000-0000-0000-000000417702','Test owner',false,'admin_staff',true,'{"customers":true,"customerStatement":true}'),
 ('00000000-0000-0000-0000-000000417703','Test reader',false,'admin_staff',true,'{"customerStatement":true,"customerCreate":true}'),
 ('00000000-0000-0000-0000-000000417704','Test other owner',false,'admin_staff',true,'{"customers":true}');

insert into public.customers(id,name,phone,customer_type,owner_id) values
 (-417701,'أحمد اختبار كشف','07700417701','wholesale','00000000-0000-0000-0000-000000417702'),
 (-417702,'عميل آخر للاختبار','','wholesale','00000000-0000-0000-0000-000000417703'),
 (-417703,'حساب اداري غير مسند','','system',null);
-- Simulate a customer imported before stored phone normalization was introduced.
alter table public.customers disable trigger solar_customer_guard;
update public.customers set phone=null where id=-417703;
insert into public.customers(id,name,customer_type,owner_id) values
 (-417704,'أحمد مكرر قديم','wholesale',null),(-417705,'احمد  مكرر قديم','wholesale',null);
alter table public.customers enable trigger solar_customer_guard;
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values
 (-417701,'customer_payment',-417701,'أحمد اختبار كشف',-500,false,'opening_balance','00000000-0000-0000-0000-000000417701','00000000-0000-0000-0000-000000417701'),
 (-417702,'sale',-417701,'أحمد اختبار كشف',600,false,'credit','00000000-0000-0000-0000-000000417702','00000000-0000-0000-0000-000000417702'),
 (-417703,'customer_payment',null,'احمد   اختبار كشف',100,true,'payment','00000000-0000-0000-0000-000000417702','00000000-0000-0000-0000-000000417702'),
 (-417704,'customer_payment',null,'اسم قديم غير معروف',30,true,'payment','00000000-0000-0000-0000-000000417701','00000000-0000-0000-0000-000000417701');
insert into public.transactions(id,kind,party_name,total,cash,payment_mode,created_by)
 values(-417705,'customer_payment','أحمد مكرر قديم',50,true,'payment','00000000-0000-0000-0000-000000417701');
create temp table rename_receipts_before as select id,to_jsonb(t) receipt from public.transactions t where t.id between -417704 and -417701;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417702',true);
do $$
declare snapshot jsonb:=public.solar_customer_get(-417701); request jsonb;
 changed jsonb; saved jsonb; req uuid:='00000000-0000-0000-0000-001777417701';
begin
 assert (snapshot->>'balance')::numeric=1000 and (snapshot->>'openingBalance')::numeric=500;
 request:=jsonb_build_object('id',-417701,'name',' كريم    اختبار كشف ','token',snapshot->>'token');
 -- Even a hand-built request with other financial/identity fields cannot modify them.
 request:=request||'{"openingBalance":0,"ownerId":null,"phone":"bad","customerType":"system"}';
 saved:=public.solar_customer_save('rename',req,request);
 assert saved='{"id":-417701,"name":"كريم اختبار كشف"}','Unexpected outward rename projection';
 assert public.solar_customer_save('rename',req,request)=saved,'Retry returned different result';
 changed:=public.solar_customer_get(-417701);
 assert changed->>'ownerId'=snapshot->>'ownerId' and changed->>'customerType'=snapshot->>'customerType' and changed->>'phone'=snapshot->>'phone';
 assert changed->'rows'=snapshot->'rows' and changed->'balance'=snapshot->'balance' and changed->'openingBalance'=snapshot->'openingBalance','Lost a linked or protected movement';
 assert changed->>'token'<>snapshot->>'token','Token did not change';
 begin perform public.solar_customer_save('rename',gen_random_uuid(),request);raise exception 'Stale rename succeeded';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_customer_save('rename',req,request||'{"name":"اختبار جديد"}');raise exception 'Saved a conflicting retry';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_customer_save('rename',gen_random_uuid(),request||jsonb_build_object('token',changed->>'token','name','عميل آخر للاختبار'));raise exception 'Duplicate accepted';exception when unique_violation then null;end;
 begin perform public.solar_customer_save('rename',gen_random_uuid(),request||jsonb_build_object('token',changed->>'token','name','اسم قديم غير معروف'));raise exception 'Orphan claimed';exception when raise_exception then if sqlerrm='Orphan claimed' then raise;end if;end;
 begin perform public.solar_customer_save('rename',gen_random_uuid(),request||jsonb_build_object('token',changed->>'token','name',null));raise exception 'Empty name accepted';exception when raise_exception then if sqlerrm='Empty name accepted' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417703',true);
do $$begin
 begin perform public.solar_customer_save('rename',gen_random_uuid(),jsonb_build_object('id',-417702,'name','تعديل ممنوع','token',public.solar_customer_get(-417702)->>'token'));raise exception 'Create-only user renamed a customer';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417704',true);
do $$begin
 begin perform public.solar_customer_save('rename',gen_random_uuid(),'{"id":-417701,"name":"تعديل ممنوع","token":"test"}');raise exception 'Foreign customer renamed';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417701',true);
do $$declare current_customer jsonb:=public.solar_customer_get(-417703);begin
 perform public.solar_customer_save('rename',gen_random_uuid(),jsonb_build_object('id',-417703,'name','تعديل حساب الادارة','token',current_customer->>'token'));
 assert (public.solar_customer_get(-417703)->>'ownerId') is null,'Admin rename assigned an owner';
 begin
  perform public.solar_customer_save('rename',gen_random_uuid(),jsonb_build_object('id',-417704,'name','اسم مستقل جديد','token',public.solar_customer_get(-417704)->>'token'));
  raise exception 'Reassigned an ambiguous receipt to the other customer';
 exception when raise_exception then if sqlerrm='Reassigned an ambiguous receipt to the other customer' then raise;end if;end;
end $$;
reset role;
do $$begin
 assert (select phone is null from public.customers where id=-417703),'Name edit normalized an unrelated legacy phone';
 assert (select count(*) from solar_private.customer_changes where action='rename' and customer_id=-417701)=1,'A retry wrote another audit row';
 assert exists(select 1 from solar_private.customer_changes where customer_id=-417701 and before_opening=500 and after_opening=500);
 assert (select party_id from public.transactions where id=-417703)=-417701,'Legacy receipt not pinned';
 assert not exists(select 1 from public.transactions t join rename_receipts_before b using(id)
  where (case when t.id=-417703 then to_jsonb(t)-'party_id'-'pricing_revision' else to_jsonb(t) end) is distinct from
        (case when t.id=-417703 then b.receipt-'party_id'-'pricing_revision' else b.receipt end)),'Historical receipt changed';
end $$;
set constraints all immediate;
rollback;
