begin;
insert into profiles(id,display_name,honorific,is_admin,user_type,permissions)values
('00000000-0000-0000-0000-000000003800','مدير الفلتر','الإداري',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003801','سفيان','الحاج',false,'admin_staff','{"salesHistory":true}'),
('00000000-0000-0000-0000-000000003802','أشرف','',false,'admin_staff','{"salesHistory":true}'),
('00000000-0000-0000-0000-000000003803','مستخدم سابق','',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003804','مهندس','',true,'installer','{"salesHistory":true}');
update profiles set active=false where id='00000000-0000-0000-0000-000000003803';
insert into products(id,code,name,qty,cost)values(-380001,'USER-FILTER','مادة الفلتر',1000,1000);
insert into transactions(id,kind,party_name,total,subtotal,cost,profit,created_by,cashbox_user_id,receipt_no,created_at,installation_status)
select -380000-n,case when n in(32,33,39)then 'system' else 'sale' end,'زبون الفلتر '||n,20000,20000,10000,10000,
 case when n<=33 then '00000000-0000-0000-0000-000000003801'::uuid when n<=39 then '00000000-0000-0000-0000-000000003802'::uuid else '00000000-0000-0000-0000-000000003803'::uuid end,
 case when n<=33 then '00000000-0000-0000-0000-000000003801'::uuid when n<=39 then '00000000-0000-0000-0000-000000003802'::uuid else '00000000-0000-0000-0000-000000003803'::uuid end,
 n,'2026-10-20T10:00Z'::timestamptz+n*interval '1 minute',case when n in(32,39)then 'completed' when n=33 then 'pending' else 'none' end
from generate_series(1,40)n;
insert into transaction_items(transaction_id,product_id,product_name,qty,price,cost)
select id,-380001,'مادة الفلتر',case when created_by='00000000-0000-0000-0000-000000003801' then 2 else 1 end,20000,10000 from transactions where id between -380040 and -380001;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003800',true);
do $$declare d jsonb;begin
 d:=public.solar_sales_history_by_user(null);assert(d->>'count')::int=40;assert jsonb_array_length(d->'rows')=30;
 assert exists(select 1 from jsonb_array_elements(d->'users')x where x->>'id'='00000000-0000-0000-0000-000000003803' and not(x->>'active')::boolean);
 d:=public.solar_sales_history_by_user('00000000-0000-0000-0000-000000003801');assert(d->>'count')::int=33;assert d->>'ownerName'='الحاج سفيان';assert jsonb_array_length(d->'rows')=30;assert not exists(select 1 from jsonb_array_elements(d->'rows')x where x->>'created_by'<>'00000000-0000-0000-0000-000000003801');
 d:=public.solar_sales_history_by_user('00000000-0000-0000-0000-000000003801',page_offset=>30);assert(d->>'count')::int=33;assert jsonb_array_length(d->'rows')=3;
 d:=public.solar_sales_history_by_user('00000000-0000-0000-0000-000000003801',sale_kind=>'system',job_status=>'completed');assert(d->>'count')::int=1;
 d:=public.solar_sales_period_by_user('00000000-0000-0000-0000-000000003801');assert(d->'summary'->>'invoiceCount')::int=33 and(d->'summary'->>'quantitySold')::numeric=66;
 d:=public.solar_sales_period_by_user('00000000-0000-0000-0000-000000003802');assert(d->'summary'->>'invoiceCount')::int=6 and(d->'summary'->>'quantitySold')::numeric=6;
 d:=public.solar_sales_period_by_user(null);assert(d->'summary'->>'invoiceCount')::int=40 and(d->'summary'->>'quantitySold')::numeric=73;
 assert(public.solar_sales_history()->>'count')::int=40;assert(public.solar_sales_period()->'summary'->>'invoiceCount')::int=40;
 d:=public.solar_sales_history_by_user('00000000-0000-0000-0000-000000003801',date_from=>'2026-10-21',date_to=>'2026-10-21');assert(d->>'count')::int=0;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003801',true);
do $$declare d jsonb;begin
 d:=public.solar_sales_history_by_user(null);assert(d->>'count')::int=33;assert jsonb_array_length(d->'users')=1;assert d->'users'->0->>'id'=auth.uid()::text;
 d:=public.solar_sales_period_by_user(null);assert(d->'summary'->>'quantitySold')::numeric=66;assert d->>'scope'='own';assert d->'rows'->0->>'remainingQty' is null;
 begin perform public.solar_sales_history_by_user('00000000-0000-0000-0000-000000003802');raise exception 'Cross-user history accepted';exception when insufficient_privilege then null;end;
 begin perform public.solar_sales_period_by_user('00000000-0000-0000-0000-000000003802');raise exception 'Cross-user report accepted';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003804',true);
do $$begin
 begin perform public.solar_sales_history_by_user(null);raise exception 'Installer stale admin bit accepted';exception when insufficient_privilege then null;end;
 begin perform public.solar_sales_period_by_user(null);raise exception 'Installer report accepted';exception when insufficient_privilege then null;end;
end$$;
reset role;
do $$begin
 assert not has_function_privilege('anon','public.solar_sales_history_by_user(uuid,text,text,date,date,text,integer)','execute');
 assert not has_function_privilege('anon','public.solar_sales_period_by_user(uuid,text,text,date,date,text)','execute');
end$$;
rollback;
