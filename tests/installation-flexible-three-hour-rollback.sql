begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003850','مدير الموعد المرن',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003851','صاحب الموعد المرن',false,'admin_staff','{"system":true,"salesHistory":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003852','صاحب آخر',false,'admin_staff','{"system":true,"installations":true}','07701234567'),
('00000000-0000-0000-0000-000000003853','مهندس الموعد المرن',false,'installer','{"installations":true}','07701234567'),
('00000000-0000-0000-0000-000000003854','مهندس آخر',true,'installer','{"installations":true}','07701234567'),
('00000000-0000-0000-0000-000000003855','مسؤول مخزن',true,'warehouse','{"system":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values
(-385001,'عميل العمل اليومي','system','00000000-0000-0000-0000-000000003851'),
(-385002,'زبون سري للمستخدم الآخر','system','00000000-0000-0000-0000-000000003852');
insert into products(id,code,name,qty,cost)values(-385001,'FLEX-385','مادة العمل اليومي',100,1000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,-385001,100)on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003851',true);
create function pg_temp.flex_invoice(day date,at_time text)returns jsonb language plpgsql as $$begin
 return public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','mode','credit','partyId',-385001,'party','عميل العمل اليومي','total',100000,'customerAddress','بغداد','installerId','00000000-0000-0000-0000-000000003853','installDate',coalesce(day::text,''),'installTime',coalesce(at_time,''),'items','[{"id":-385001,"qty":1,"price":0}]'::jsonb));
end$$;
set local role authenticated;
do $$declare r jsonb;today date:=(now()at time zone 'Asia/Baghdad')::date;begin
 r:=pg_temp.flex_invoice(null,null);perform set_config('test.flex.unscheduled',r->>'id',true);
 r:=pg_temp.flex_invoice(today-1,'10:00');perform set_config('test.flex.overdue',r->>'id',true);
 r:=pg_temp.flex_invoice(today,'10:00');perform set_config('test.flex.booked',r->>'id',true);
 r:=pg_temp.flex_invoice(today,'13:00');
 begin perform pg_temp.flex_invoice(today,'12:59');raise exception 'Overlap accepted';exception when sqlstate 'PT409'then null;end;
 r:=pg_temp.flex_invoice(today,'22:00');
 begin perform pg_temp.flex_invoice(today+1,'00:59');raise exception 'Midnight overlap accepted';exception when sqlstate 'PT409'then null;end;
 r:=pg_temp.flex_invoice(today+1,'01:00');
 r:=pg_temp.flex_invoice(today,'18:00');perform set_config('test.flex.clear',r->>'id',true);
 r:=pg_temp.flex_invoice(null,null);perform set_config('test.flex.completed',r->>'id',true);
 r:=pg_temp.flex_invoice(null,null);perform set_config('test.flex.closed',r->>'id',true);
 begin perform pg_temp.flex_invoice(today,'');raise exception 'Partial appointment accepted';exception when sqlstate '22023'or raise_exception then if sqlerrm='Partial appointment accepted'then raise;end if;end;
end$$;
reset role;
update transactions set installation_status='completed'where id=current_setting('test.flex.completed')::bigint;
update transactions set installation_status='closed'where id=current_setting('test.flex.closed')::bigint;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003852',true);
set local role authenticated;
select public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-385002,"party":"زبون سري للمستخدم الآخر","total":100000,"customerAddress":"عنوان سري","installerId":"00000000-0000-0000-0000-000000003853","items":[{"id":-385001,"qty":1,"price":0}]}');
reset role;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003851',true);
-- Browser fixtures commit the setup above; all SQL checks below are rolled back.
set local role authenticated;
do $$declare j transactions;r jsonb;d jsonb;today date:=(now()at time zone 'Asia/Baghdad')::date;b numeric;begin
 select * into j from transactions where id=current_setting('test.flex.clear')::bigint;b:=solar_private.cash_balance(auth.uid());
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','mode','credit','invoiceId',j.id,'expectedRevision',j.pricing_revision,'expectedInstallationRevision',j.installation_revision,'partyId',-385001,'party','عميل العمل اليومي','total',j.total,'customerAddress','بغداد','installerId',j.installer_id,'installDate','','installTime','','items','[{"id":-385001,"qty":1,"price":0}]'::jsonb));
 select * into j from transactions where id=j.id;
 assert j.install_date is null and j.install_time is null;
 assert j.total=100000 and j.cost=1000 and j.profit=99000;
 assert solar_private.cash_balance(auth.uid())=b;
 perform pg_temp.flex_invoice(today,'18:00');
 d:=public.solar_installation_schedule(today,today+3);
 assert(d->>'durationHours')::integer=3;
 assert not exists(select 1 from jsonb_array_elements(d->'slots')s where extract(epoch from((s->>'end')::timestamptz-(s->>'start')::timestamptz))<>10800);
 assert exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'id'=current_setting('test.flex.unscheduled')and x->>'installDate'is null);
 assert exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'id'=current_setting('test.flex.overdue')and(x->>'installDate')::date=today-1);
 assert exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'id'=current_setting('test.flex.clear'));
 assert not exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'id'in(current_setting('test.flex.completed'),current_setting('test.flex.closed')));
 assert exists(select 1 from jsonb_array_elements(d->'backlog')x where not(x->>'own')::boolean and not(x?'id')and not(x?'party')and not(x?'creatorName'));
 assert not(d::text like '%زبون سري%');
 d:=public.solar_installation_schedule(today+1,today+1);assert exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'id'=current_setting('test.flex.unscheduled'));
 assert(select install_date from transactions where id=current_setting('test.flex.overdue')::bigint)=today-1;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003853',true);
do $$declare d jsonb;today date:=(now()at time zone 'Asia/Baghdad')::date;begin
 d:=public.solar_installation_schedule(today,today+3);assert d::text like '%زبون سري%';
 assert not exists(select 1 from jsonb_array_elements(d->'backlog')x where x->>'installerId'<>'00000000-0000-0000-0000-000000003853');
 begin perform public.solar_installation_schedule(today,today+1,'00000000-0000-0000-0000-000000003854');raise exception 'Engineer viewed another schedule';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003855',true);
do $$begin begin perform public.solar_installation_schedule(current_date,current_date);raise exception 'Warehouse stale admin';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS optional and cleared appointments, three-hour adjacency/overlap/midnight, daily flexible/overdue queue, completed exclusion, original dates and finances preserved, scoped calendar privacy
rollback;
