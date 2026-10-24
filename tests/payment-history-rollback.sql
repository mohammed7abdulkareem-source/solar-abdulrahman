\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003700','مدير السجل',true,'admin_staff','07700003700','{}'),
('00000000-0000-0000-0000-000000003701','صاحب الوصولات',false,'admin_staff','07700003701','{"customerPayment":true,"systemPayment":true,"supplierPayment":true}'),
('00000000-0000-0000-0000-000000003702','مستخدم آخر',false,'admin_staff','07700003702','{"customerPayment":true}'),
('00000000-0000-0000-0000-000000003703','مهندس السجل',true,'installer','07700003703','{}'),
('00000000-0000-0000-0000-000000003704','مخزن السجل',false,'warehouse','07700003704','{}'),
('00000000-0000-0000-0000-000000003705','قراءة الحساب فقط',false,'admin_staff','07700003705','{"customerStatement":true}'),
('00000000-0000-0000-0000-000000003706','بدون صلاحية',false,'admin_staff','07700003706','{}');
insert into customers(id,name,customer_type,owner_id) values
(-370001,'عميل التسلسل','wholesale','00000000-0000-0000-0000-000000003701'),
(-370002,'عميل المنظومات','system','00000000-0000-0000-0000-000000003701'),
(-370003,'عميل المستخدم الآخر','wholesale','00000000-0000-0000-0000-000000003702'),
(-370004,'عميل القراءة','wholesale','00000000-0000-0000-0000-000000003705');
insert into suppliers(id,name) values(-370001,'مورد التسلسل');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,created_at)
values(-370001,'customer_payment',-370001,'عميل التسلسل',-10000,false,'opening_balance','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-01T00:00Z');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,created_at)
select -371000-i,'customer_payment',-370001,'عميل التسلسل',i,true,'payment','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-24T12:00Z'::timestamptz+i*interval '1 second' from generate_series(1,64)i;
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,created_at)
values(-372001,'customer_payment',-370001,'عميل التسلسل',25,true,'payment','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-24T20:59:59Z'),
(-372002,'system_payment',-370002,'عميل المنظومات',50,true,'payment','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-24T21:00:00Z'),
(-372003,'customer_payment',-370003,'عميل المستخدم الآخر',77,true,'payment','00000000-0000-0000-0000-000000003702','00000000-0000-0000-0000-000000003702','2026-10-24T12:00Z'),
(-372004,'customer_payment',-370004,'عميل القراءة',88,true,'payment','00000000-0000-0000-0000-000000003705','00000000-0000-0000-0000-000000003705','2026-10-24T12:00Z'),
(-372005,'supplier_payment',-370001,'مورد التسلسل',10,true,'cash','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-24T12:00Z'),
(-372006,'customer_payment',-370001,'عميل التسلسل',-5,false,'charge_other','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','2026-10-24T12:00Z');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003701',true);
do $$declare a jsonb;b jsonb;c jsonb;r jsonb;begin
 a:=public.solar_payment_history('list');
 if(a->>'count')::integer<>67 or jsonb_array_length(a->'rows')<>30 then raise exception 'FAIL owner list/count %',a;end if;
 b:=public.solar_payment_history('list','{"offset":30}');c:=public.solar_payment_history('list','{"offset":60}');
 if jsonb_array_length(b->'rows')<>30 or jsonb_array_length(c->'rows')<>7 or exists(select 1 from jsonb_array_elements(a->'rows')x join jsonb_array_elements(b->'rows')y on x->>'id'=y->>'id') then raise exception 'FAIL sequence pages';end if;
 a:=public.solar_payment_history('list','{"from":"2026-10-24","to":"2026-10-24"}');if(a->>'count')::integer<>66 then raise exception 'FAIL Baghdad last second %',a->>'count';end if;
 a:=public.solar_payment_history('list','{"from":"2026-10-25","to":"2026-10-25"}');if(a->>'count')::integer<>1 or a->'rows'->0->>'kind'<>'system_payment' then raise exception 'FAIL Baghdad next midnight';end if;
 a:=public.solar_payment_history('get','{"id":-372001}');if a->'receipt'->>'creatorPhone'<>'07700003701' or(a->'receipt'->>'oldBalance')::numeric-(a->'receipt'->>'remaining')::numeric<>25 then raise exception 'FAIL original legacy receipt';end if;
 a:=public.solar_payment_history('get','{"id":-372005}');if a->>'type'<>'supplier' or(a->'receipt'->>'total')::numeric<>10 then raise exception 'FAIL supplier original';end if;
 begin perform public.solar_payment_history('get','{"id":-372003}');raise exception 'FAIL other owner receipt';exception when insufficient_privilege then null;end;
 begin perform public.solar_payment_history('get','{"id":-370001}');raise exception 'FAIL opening is payment';exception when insufficient_privilege then null;end;
 begin perform public.solar_payment_history('list','{"from":"2026-10-25","to":"2026-10-24"}');raise exception 'FAIL reversed dates';exception when invalid_parameter_value then null;end;
 begin perform public.solar_payment_history('delete','{}');raise exception 'FAIL mutating action';exception when invalid_parameter_value then null;end;
 r:=public.solar_customer_payment_context(-370001);
 r:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-370001,'amount',37,'mode','payment','notes','لقطة أصلية','expectedToken',r->>'token'));
 perform set_config('test.original',r::text,true);
 a:=public.solar_payment_history('get',jsonb_build_object('id',(r->>'id')::bigint));
 if a->'receipt'->>'balanceBasis'<>'issued' or a->'receipt'->>'remaining'<>r->>'remaining' or a->'receipt'->>'oldBalance'<>r->>'oldBalance' then raise exception 'FAIL saved issue snapshot';end if;
end$$;
reset role;
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id)
values(-372007,'customer_payment',-370001,'عميل التسلسل',13,true,'payment','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701');
insert into transactions(id,kind,party_id,party_name,total,cost,profit,cash,created_by,cashbox_user_id,installer_id,installation_status,created_at)
values(-372008,'system',-370002,'عميل المنظومات',1000,0,1000,false,'00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003703','pending','2026-10-23T12:00Z');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,system_invoice_id,created_at)
values(-372009,'system_payment',-370002,'عميل المنظومات',100,true,'payment','00000000-0000-0000-0000-000000003701','00000000-0000-0000-0000-000000003701',-372008,'2026-10-24T13:00Z');
select set_config('test.before',(select md5(jsonb_agg(to_jsonb(t) order by id)::text) from transactions t),true);
set local role authenticated;
do $$declare r jsonb:=current_setting('test.original')::jsonb;a jsonb;begin
 a:=public.solar_payment_history('get',jsonb_build_object('id',(r->>'id')::bigint));
 if a->'receipt'->>'remaining'<>r->>'remaining' then raise exception 'FAIL new payment changed historical snapshot';end if;
end$$;
do $$declare r jsonb;begin
 r:=public.solar_payment_history('get','{"id":-372009}');
 if(r->'receipt'->>'invoiceBefore')::numeric<>1000 or(r->'receipt'->>'invoiceAfter')::numeric<>900 then raise exception 'FAIL legacy allocated invoice balances';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003702',true);
do $$declare r jsonb;begin
 r:=public.solar_payment_history('list');if(r->>'count')::integer<>1 then raise exception 'FAIL scope count';end if;
 begin perform public.solar_payment_history('list','{"kind":"supplier_payment"}');raise exception 'FAIL unauthorized kind';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003705',true);
do $$declare r jsonb;begin r:=public.solar_payment_history('get','{"id":-372004}');if r->'receipt'->>'party'<>'عميل القراءة' then raise exception 'FAIL statement reader original receipt';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003700',true);
do $$declare r jsonb;begin r:=public.solar_payment_history('list');if(r->>'count')::integer<>72 then raise exception 'FAIL admin scope %',r->>'count';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003703',true);
do $$begin begin perform public.solar_payment_history('list');raise exception 'FAIL engineer stale admin';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003704',true);
do $$begin begin perform public.solar_payment_history('list');raise exception 'FAIL warehouse';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003706',true);
do $$begin begin perform public.solar_payment_history('list');raise exception 'FAIL no capability';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin if(select md5(jsonb_agg(to_jsonb(t) order by id)::text) from transactions t)<>current_setting('test.before') then raise exception 'FAIL read modified business records';end if;end$$;
set constraints all immediate;
\echo PASS history pagination, Baghdad boundaries, own records and permissions, original snapshots, supplier currency receipt, read-only actions
rollback;
