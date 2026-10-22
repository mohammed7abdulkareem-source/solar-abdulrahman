\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions) values
('00000000-0000-0000-0000-000000003670','إدارة السعر',true,'admin_staff','07700003670','{}'),
('00000000-0000-0000-0000-000000003671','صاحب الفاتورة بدون غلق',false,'admin_staff','07700003671','{"system":true}'),
('00000000-0000-0000-0000-000000003672','صاحب فاتورة آخر',false,'admin_staff','07700003672','{"system":true,"installations":true}'),
('00000000-0000-0000-0000-000000003673','مهندس السعر',true,'installer','07700003673','{}'),
('00000000-0000-0000-0000-000000003674','مسؤول المخزن',true,'warehouse','07700003674','{}');
insert into products(id,code,name,qty,cost) values(-367001,'PRICE-CARD','لوح تنصيب',20,100);
insert into customers(id,name,customer_type,owner_id) values(-367001,'عميل المستخدم الأول','system','00000000-0000-0000-0000-000000003671'),(-367002,'عميل المستخدم الثاني','system','00000000-0000-0000-0000-000000003672');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003671',true);
select set_config('test.owner_job',public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-367001,"party":"عميل المستخدم الأول","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003673","customerAddress":"العنوان","total":4850000,"items":[{"id":-367001,"qty":1,"price":0}]}')->>'id',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003672',true);
select set_config('test.other_job',public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","partyId":-367002,"party":"عميل المستخدم الثاني","mode":"credit","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000003673","customerAddress":"العنوان الثاني","total":9000000,"items":[{"id":-367001,"qty":1,"price":0}]}')->>'id',true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003671',true);
do $$declare jobs jsonb;j jsonb;begin
 jobs:=public.solar_installation_jobs();j:=jobs->0;
 if jsonb_array_length(jobs)<>1 or(j->>'sellingPrice')::numeric<>4850000 or(j->>'id')::bigint<>current_setting('test.owner_job')::bigint then raise exception 'FAIL own selling price or foreign receipt scope';end if;
 if(j->>'canManage')::boolean or j ?|array['cost','total','expenses','installationExpenses'] then raise exception 'FAIL sale visibility granted extra financial/closing permissions';end if;
 begin perform public.solar_installation_action(current_setting('test.owner_job')::bigint,0,'close','{"amount":0}');raise exception 'FAIL price visibility granted close';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003670',true);
do $$declare jobs jsonb;begin jobs:=public.solar_installation_jobs();if jsonb_array_length(jobs)<>2 or not exists(select 1 from jsonb_array_elements(jobs) j where(j->>'sellingPrice')::numeric=4850000) or not exists(select 1 from jsonb_array_elements(jobs) j where(j->>'sellingPrice')::numeric=9000000) then raise exception 'FAIL admin selling prices';end if;end$$;
reset role;
update transactions set warehouse_status='ready',warehouse_prepared_at=now() where id=current_setting('test.owner_job')::bigint;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003670',true);
select public.solar_installation_action(current_setting('test.owner_job')::bigint,0,'close','{"amount":0}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003671',true);
do $$declare j jsonb;begin j:=public.solar_installation_jobs()->0;if j->>'installationStatus'<>'closed' or(j->>'sellingPrice')::numeric<>4850000 then raise exception 'FAIL closed job selling price';end if;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003673',true);
do $$declare jobs jsonb;begin
 jobs:=public.solar_installation_jobs();if jsonb_array_length(jobs)<>2 or exists(select 1 from jsonb_array_elements(jobs) j where j ?|array['sellingPrice','total','cost','profit','expenses','installationExpenses']) then raise exception 'FAIL stale-admin engineer price exposure';end if;
 if exists(select 1 from jsonb_array_elements(jobs) j,jsonb_array_elements(j->'items') i where i ?|array['price','cost']) then raise exception 'FAIL engineer item prices';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003674',true);
do $$begin begin perform public.solar_installation_jobs();raise exception 'FAIL warehouse access';exception when insufficient_privilege then null;end;end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000003671';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003671',true);
do $$begin begin perform public.solar_installation_jobs();raise exception 'FAIL inactive login';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
\echo PASS owner selling price without close, original owner isolation, admin prices, closed/open visibility, no engineer/warehouse financial exposure, no privilege escalation
rollback;
