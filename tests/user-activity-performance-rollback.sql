-- The public RPC is tested using an authenticated administrator against synthetic accounts.
\set ON_ERROR_STOP on
begin;
create function pg_temp.uid(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((416800+n)::text,12,'0'))::uuid
$$;
insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (pg_temp.uid(1),'مدير اختبار النشاط',true,true,'admin','{}'),
 (pg_temp.uid(2),'البائع',false,true,'admin_staff','{}'),
 (pg_temp.uid(3),'مستفيد آخر',false,true,'admin_staff','{}'),
 (pg_temp.uid(4),'بدون مبيعات',false,true,'warehouse','{}');
insert into public.transactions(id,kind,subtotal,total,cost,profit,expenses,expenses_on_customer,source_currency,exchange_rate,
 source_subtotal,fx_pricing,cash,created_by,cashbox_user_id,installation_status,created_at,installation_closed_at)
select id,kind,subtotal,total,cost,profit,expense,payer,currency,rate,subtotal/rate,fx,false,pg_temp.uid(creator),pg_temp.uid(box),
 status,at::timestamptz,closed_at::timestamptz from(values
 (-416801,'sale',1500,1600,950,550,100,true,'USD',1500,true,2,2,'none','2024-02-27 21:00Z',null),
 (-416802,'sale',400,400,0,999,0,null,'IQD',1,false,2,2,'none','2024-02-29 08:00Z',null),
 (-416803,'sale',300,300,310,-30,20,false,'IQD',1,true,2,2,'none','2024-02-29 09:00Z',null),
 (-416804,'system',500,500,550,-100,50,null,'IQD',1,true,2,2,'closed','2024-02-29 13:00Z','2024-03-10 13:00Z'),
 (-416805,'system',2500,2500,1000,1500,0,null,'IQD',1,true,2,2,'pending','2024-03-02 20:59:59Z',null),
 (-416806,'sale',90000,90000,91000,-1000,0,true,'IQD',1,true,3,2,'none','2024-02-28 00:00Z',null),
 (-416807,'sale',9999,9999,99,9900,0,true,'IQD',1,true,2,2,'none','2024-03-02 21:00Z',null)
) t(id,kind,subtotal,total,cost,profit,expense,payer,currency,rate,fx,creator,box,status,at,closed_at);
insert into public.transaction_items(transaction_id,product_name,qty,cost,price) values(-416802,'مادة قديمة',2,120,200);
-- More than 50 receipts on one day: the chart must never aggregate the recent timeline.
insert into public.transactions(id,kind,subtotal,total,profit,fx_pricing,cash,created_by,cashbox_user_id,created_at)
 select -416900-g,'sale',10,10,2,true,false,null,pg_temp.uid(2),'2024-02-28 14:00Z' from generate_series(1,60) g;
-- Profit transfer affects personal profit reports but not what the user sold.
insert into solar_private.invoice_profit_owners(invoice_id,owner_id,updated_by) values(-416801,pg_temp.uid(3),pg_temp.uid(1));
insert into solar_private.profit_settlements(id,owner_id,date_to,profit,status,share,snapshot,receipt,decided_at)
 select pg_temp.uid(100+n),pg_temp.uid(person),'2024-01-20',profit,status,share,'[]','{}',at::timestamptz from(values
 (1,2,500,'approved',50,'2024-02-27 21:00Z'),(2,2,400,'approved',200,'2024-03-02 20:59:59Z'),
 (3,2,100,'approved',0,'2024-03-01 12:00Z'),(4,2,900,'rejected',null,'2024-03-01 12:00Z'),
 (5,2,800,'approved',800,'2024-03-02 21:00Z'),(6,3,901,'approved',900,'2024-03-01 12:00Z'),
 (7,2,1600,'approved',null,'2024-02-29 12:00Z')
 ) t(n,person,profit,status,share,at);
set local role authenticated;
select set_config('request.jwt.claim.sub',pg_temp.uid(1)::text,true);
do $guard$
declare d jsonb;p jsonb;row jsonb;
 payload jsonb:=jsonb_build_object('ownerId',pg_temp.uid(2),'from','2024-02-28','to','2024-03-02');
begin
 d:=public.solar_user_activity(payload);p:=d->'performance';
 assert (d#>>'{sales,count}')::int=65 and (d#>>'{sales,totalIQD}')::numeric=5900;
 assert (p->>'eligibleSalesIQD')::numeric=3300 and (p->>'companyProfitIQD')::numeric=700 and (p->>'marginPercent')::numeric=21.21,p;
 assert (p->>'approvedShareIQD')::numeric=250 and (p->>'approvedShareBaseIQD')::numeric=1000 and (p->>'approvedShareCount')::int=3
  and (p->>'approvedSharePercent')::numeric=25;
 assert (d#>>'{profit,earnedIQD}')::numeric<>700 and jsonb_array_length(d->'recent')=50;
 assert p->>'granularity'='day' and p->>'from'='2024-02-28' and p->>'to'='2024-03-02' and p->>'currency'='IQD';
 assert jsonb_array_length(p->'series')=4;
 select v into row from jsonb_array_elements(p->'series') v where v->>'start'='2024-02-29';
 assert row->>'end'='2024-02-29' and (row->>'companyProfitIQD')::numeric=30 and (row->>'eligibleSalesIQD')::numeric=1200;
 assert (p#>>'{series,0,invoiceCount}')::int=61 and (p#>>'{series,2,invoiceCount}')::int=0;
 assert (select sum((v->>'salesIQD')::numeric) from jsonb_array_elements(p->'series') v)=(d#>>'{sales,totalIQD}')::numeric;
 assert (select sum((v->>'companyProfitIQD')::numeric) from jsonb_array_elements(p->'series') v)=(p->>'companyProfitIQD')::numeric;
 p:=public.solar_user_activity(payload||'{"from":"2024-01-30"}')->'performance';
 assert p->>'granularity'='month' and p#>>'{series,0,start}'='2024-01-30' and p#>>'{series,1,end}'='2024-02-29'
  and p#>>'{series,2,end}'='2024-03-02';
 p:=public.solar_user_activity(payload||'{"from":"2020-10-10"}')->'performance';
 assert p->>'granularity'='year' and jsonb_array_length(p->'series')=5 and p#>>'{series,0,start}'='2020-10-10'
  and p#>>'{series,4,end}'='2024-03-02';
 p:=public.solar_user_activity(payload-'from')->'performance';
 assert p->>'from'='2024-02-28' and (p->>'companyProfitIQD')::numeric=700;
 p:=public.solar_user_activity(payload||jsonb_build_object('ownerId',pg_temp.uid(3)))->'performance';
 assert (p->>'companyProfitIQD')::numeric=-1000 and (p->>'marginPercent')::numeric=-1.11 and (p->>'approvedShareIQD')::numeric=900;
 p:=public.solar_user_activity(payload||jsonb_build_object('ownerId',pg_temp.uid(4)))->'performance';
 assert (p->>'eligibleSalesIQD')::numeric=0 and p->'marginPercent'='null'::jsonb and p->'approvedSharePercent'='null'::jsonb
  and (p->>'approvedShareCount')::int=0 and jsonb_array_length(p->'series')=4;
 assert not(public.solar_user_activity('{}')?'performance');
 assert not has_function_privilege('authenticated','solar_private.user_activity_performance(uuid,date,date)','execute');
 assert not has_function_privilege('anon','solar_private.user_activity_performance(uuid,date,date)','execute');
 perform set_config('request.jwt.claim.sub',pg_temp.uid(2)::text,true);
 begin perform public.solar_user_activity(payload);raise exception 'Unauthorized performance detail';
 exception when insufficient_privilege then null;end;
end$guard$;
rollback;
\echo PASS user performance receipt accounting, margin, approved user shares, Baghdad chart and admin scope.
