-- All records are synthetic. Dashboard RPCs run as the authenticated app role.
\set ON_ERROR_STOP on
begin;
load 'safeupdate';

create function pg_temp.person(n int) returns uuid language sql immutable as $$
 select ('00000000-0000-0000-0000-'||lpad((414100+n)::text,12,'0'))::uuid
$$;
create function pg_temp.login(n int) returns void language sql as $$
 select set_config('request.jwt.claim.sub',pg_temp.person(n)::text,true)::text is not null
$$;
insert into public.profiles(id,username,display_name,user_type,is_admin,active,permissions)
select pg_temp.person(i),'ua414-'||i,name,role,admin,enabled,permissions::jsonb from (values
 (1,'مدير لوحة النشاط','admin_staff',true,true,'{}'),
 (2,'المستخدم الأول','admin_staff',false,true,'{}'),
 (3,'المستخدم الثاني','admin_staff',false,true,'{}'),
 (4,'أمين المخزن','warehouse',false,true,'{}'),
 (5,'مهندس التنصيب','installer',false,true,'{}'),
 (6,'مدير مخزن قديم','warehouse',true,true,'{}'),
 (7,'مدير غير فعال','admin_staff',true,false,'{}'),
 (8,'موظف بصلاحيات مالية','admin_staff',false,true,'{"profit":true,"cash":true,"userManagement":true}'),
 (9,'موظف متوقف','admin_staff',false,false,'{}'),
 (10,'مهندس سابق','installer',false,true,'{}')
) v(i,name,role,admin,enabled,permissions);
-- Reproduce a historical warehouse profile with the stale administrative bit.
-- Normal profile creation clears that bit, so seed just this legacy row explicitly.
set local session_replication_role=replica;
update public.profiles set is_admin=true where id=pg_temp.person(6);
set local session_replication_role=origin;
insert into public.customers(id,name,customer_type,owner_id,created_at) values
 (-414101,'زبون النشاط','wholesale',pg_temp.person(2),'2024-05-01'),
 (-414102,'زبون برصيد دائن','wholesale',pg_temp.person(2),'2024-05-01'),
 (-414103,'زبون المستخدم الثاني','system',pg_temp.person(3),'2024-05-01');
-- Times straddling midnight in Baghdad prove inclusion of both date bounds.
insert into public.transactions(id,kind,party_id,party_type,payment_mode,subtotal,total,cost,profit,
 expenses,expenses_on_customer,fx_pricing,cash,created_by,cashbox_user_id,created_at)
select id,'sale',customer,'customer',case when paid then 'cash' else 'credit' end,value,value,value-profit,profit,
 case id when -414101 then 70 when -414102 then 15 else 0 end,id<>-414101,true,paid,pg_temp.person(creator),pg_temp.person(wallet),at::timestamptz from(values
 (-414101,-414101,12000,200, false,2,2,'2024-05-09 21:00:00+00'),
 (-414102,-414101,300,20, true,2,2,'2024-05-10 20:59:59+00'),
 (-414103,-414101,500,50, false,3,3,'2024-05-09 20:59:59+00'),
 (-414104,-414101,1000,100, false,2,2,'2024-05-10 21:00:00+00'),
 (-414105,-414103,9000,900, false,3,3,'2024-05-10 09:30:00+00')
) v(id,customer,value,profit,paid,creator,wallet,at);
-- The document creator and holder of its profit are deliberately different.
insert into public.transactions(id,kind,party_id,party_type,payment_mode,subtotal,total,cost,profit,fx_pricing,cash,
 created_by,cashbox_user_id,created_at,installer_id,install_date,install_time,installation_status,installation_started_at,
 installation_completed_at,installation_closed_at,installation_expenses,installation_report)
values(-414106,'system',-414103,'customer','credit',20000,20000,19600,400,true,false,
 pg_temp.person(2),pg_temp.person(3),'2024-05-10 15:00:00Z',pg_temp.person(5),'2024-05-10','08:00','closed',
 '2024-05-10 08:00:00Z','2024-05-10 10:00:00Z','2024-05-11 10:00:00Z',60,
 jsonb_build_object('submittedBy',pg_temp.person(10)));

insert into public.transactions(id,kind,party_id,party_type,payment_mode,total,cash,cash_amount,cash_currency,
 created_by,cashbox_user_id,created_at)
select id,kind,customer,'customer',mode,total,cash,amount,currency,pg_temp.person(creator),pg_temp.person(wallet),at::timestamptz from(values
 (-414107,'customer_payment',-414101,'payment',300,true,300,'IQD',3,2,'2024-05-10 08:00+00'),
 (-414108,'system_payment',-414103,'payment',4500,true,3,'USD',2,2,'2024-05-10 11:00+00'),
 (-414109,'customer_payment',-414101,'payment',100,true,100,'IQD',2,3,'2024-05-10 12:00+00'),
 (-414110,'customer_payment',-414101,'opening_balance',-200,false,0,'IQD',2,2,'2024-05-08 12:00+00'),
 (-414111,'customer_payment',-414101,'charge_other',-50,false,0,'IQD',2,2,'2024-05-10 12:01+00'),
 (-414112,'customer_payment',-414102,'payment',160,false,0,'IQD',3,2,'2024-05-10 12:02+00'),
 (-414113,'customer_payment',-414101,'payment',17,true,17,'IQD',3,2,'2024-05-10 21:00+00')
) v(id,kind,customer,mode,total,cash,amount,currency,creator,wallet,at);

insert into public.transactions(id,kind,total,cash,cash_purpose,cash_currency,cash_amount,created_by,cashbox_user_id,created_at)
values(-414114,'cash_expense',30,true,'expense','IQD',30,pg_temp.person(2),pg_temp.person(2),'2024-05-10 12:30Z'),
      (-414115,'cash_expense',3000,true,'expense','USD',2,pg_temp.person(2),pg_temp.person(2),'2024-05-10 12:31Z'),
      (-414116,'profit_expense',10,false,null,'IQD',0,pg_temp.person(2),pg_temp.person(2),'2024-05-10 12:32Z');

insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount,expense,status,created_at,decided_at,decided_by) values
 (pg_temp.person(101),pg_temp.person(2),pg_temp.person(3),120,5,'accepted','2024-05-09 19:00Z','2024-05-10 10:00Z',pg_temp.person(3)),
 (pg_temp.person(102),pg_temp.person(3),pg_temp.person(2),70,0,'accepted','2024-05-10 09:00Z','2024-05-10 11:00Z',pg_temp.person(2)),
 (pg_temp.person(103),pg_temp.person(2),pg_temp.person(3),60,0,'pending','2024-05-10 09:00Z',null,null),
 (pg_temp.person(104),pg_temp.person(2),pg_temp.person(3),900,0,'rejected','2024-05-10 09:00Z','2024-05-10 12:00Z',pg_temp.person(3)),
 (pg_temp.person(105),pg_temp.person(2),pg_temp.person(3),700,0,'accepted','2024-05-10 09:00Z','2024-05-11 12:00Z',pg_temp.person(3));
-- Recreate both sides of each transfer. One rejected transfer refunded 880
-- instead of 900. It is the only mismatch the audit should find in this window.
insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id,created_at)
select leg.owner,leg.delta,leg.kind,t.id,t.sender_id,leg.at
from solar_private.cash_transfers t cross join lateral(values
 (t.sender_id,-t.amount,'transfer_out',t.created_at),
 (null::uuid,t.amount,'transfer_transit',t.created_at),
 (null::uuid,-t.amount,'transfer_transit',t.decided_at),
 (t.recipient_id,t.amount,'transfer_in',case when t.status='accepted' then t.decided_at end),
 (t.sender_id,880,'transfer_refund',case when t.status='rejected' then t.decided_at end),
 (t.sender_id,-t.expense,'handover_expense',case when t.expense>0 then t.created_at end)
) leg(owner,delta,kind,at)
where t.id in (pg_temp.person(101),pg_temp.person(102),pg_temp.person(103),pg_temp.person(104),pg_temp.person(105)) and leg.at is not null;
-- Direct handovers post once to each side, in their actual currency.
insert into solar_private.finance_requests(request_id,actor_id,action,payload,response,created_at)
values(pg_temp.person(201),pg_temp.person(1),'admin_cash_transfer','{}',jsonb_build_object(
 'transferId',pg_temp.person(201),'senderId',pg_temp.person(3),'recipientId',pg_temp.person(2),'currency','USD','amount',4,
 'date','2024-05-10T13:00:00Z','receiptNo',414201),'2024-05-10 13:00Z');
insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,entry_type,finance_request_id,created_at)
values(pg_temp.person(3),'USD',-4,-6000,1500,'admin_transfer_out',pg_temp.person(201),'2024-05-10 13:00Z'),
      (pg_temp.person(2),'USD', 4, 6000,1500,'admin_transfer_in',pg_temp.person(201),'2024-05-10 13:00Z');
insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,entry_type,transaction_id,created_at)
values(pg_temp.person(2),'USD',3,4500,1500,'payment',-414108,'2024-05-10 11:00Z'),
      (pg_temp.person(2),'USD',-2,-3000,1500,'expense',-414115,'2024-05-10 12:31Z');
insert into solar_private.warehouse_audit(invoice_id,actor_id,action,before_items,after_items,created_at)
select -414101,pg_temp.person(4),action,'[]','[]',stamp::timestamptz from(values
 ('ready','2024-05-10 06:00Z'),('save','2024-05-10 07:00Z'),('reopen','2024-05-10 08:00Z'),('ready','2024-05-10 21:00Z'))v(action,stamp);
insert into solar_private.stock_transfers(id,receipt_no,from_id,to_id,from_name,to_name,items,actor_id,actor_name,
 status,created_at,prepared_at,prepared_by) overriding system value
select pg_temp.person(301),-414301,a.id,b.id,a.name,b.name,'[]',pg_temp.person(3),'صاحب الطلب','posted',
 '2024-05-09 10:00Z','2024-05-10 08:00Z',pg_temp.person(4)
from solar_private.warehouses a cross join lateral(select * from solar_private.warehouses w where w.id<>a.id order by w.id limit 1)b where a.is_primary;

-- A personal external settlement changes the current entitlement even when
-- inspecting an older day. It is never new income earned on that day.
select pg_temp.login(1);
do $$declare o jsonb;begin
 o:=public.solar_profit_workspace('overview',null,jsonb_build_object('ownerId',pg_temp.person(2)));
 assert (o->>'retainedProfit')::numeric=-2725;
 perform public.solar_profit_workspace('external_adjust',pg_temp.person(401),jsonb_build_object(
  'ownerId',pg_temp.person(2),'targetBalance',-700,'expectedToken',o->>'externalAdjustmentToken','note','تسوية اختبار النشاط'));
end $$;

create function pg_temp.detail(n int) returns jsonb language sql as $$
 select public.solar_user_activity(jsonb_build_object('ownerId',pg_temp.person(n),'from','2024-05-10','to','2024-05-10'))
$$;
-- A read-only call must leave both financial and operational ledgers intact.
create function pg_temp.fingerprint() returns text language sql security definer set search_path='' as $$
 select md5(jsonb_build_array(
  (select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),
  (select jsonb_agg(to_jsonb(t) order by id) from public.solar_cash_entries t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.cash_transfers t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.wallet_fx_entries t),
  (select jsonb_agg(to_jsonb(t) order by request_id) from solar_private.finance_requests t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.warehouse_audit t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.stock_transfers t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.profit_balance_adjustments t)
 )::text)
$$;
set local role authenticated;
select pg_temp.login(1);
select set_config('test.activity.before',pg_temp.fingerprint(),true);
do $$
declare d jsonb; list jsonb; ops jsonb; n int;
begin
 list:=public.solar_user_activity('{}');
 assert jsonb_typeof(list->'users')='array' and list ? 'asOf';
 assert not exists(select 1 from jsonb_array_elements(list->'users') x where (x->>'id')::uuid in (pg_temp.person(1),pg_temp.person(6),pg_temp.person(7)));
 foreach n in array array[2,3,4,5,9] loop
  assert exists(select 1 from jsonb_array_elements(list->'users')x where x->>'id'=pg_temp.person(n)::text),'Missing non-admin profile';
 end loop;
 d:=pg_temp.detail(2);
 assert (d#>>'{sales,count}')::int=3 and (d#>>'{sales,wholesaleCount}')::int=2 and (d#>>'{sales,systemCount}')::int=1,d->'sales';
 assert (d#>>'{sales,wholesaleIQD}')::numeric=12300 and (d#>>'{sales,systemIQD}')::numeric=20000 and (d#>>'{sales,totalIQD}')::numeric=32300,d->'sales';
 assert (d#>>'{profit,earnedIQD}')::numeric=-2820 and (d#>>'{profit,remainingIQD}')::numeric=-700,d->'profit';
 assert (d#>>'{collections,IQD}')::numeric=300 and (d#>>'{collections,USD}')::numeric=3 and (d#>>'{collections,count}')::int=2,d->'collections';
 assert (d#>>'{debts,dueIQD}')::numeric=12350 and (d#>>'{debts,creditIQD}')::numeric=160 and (d#>>'{debts,netIQD}')::numeric=12190,d->'debts';
 assert (d#>>'{debts,debtorCount}')::int=1 and (d#>>'{debts,customerCount}')::int=2,d->'debts';
 assert (d#>>'{handovers,outgoing,IQD}')::numeric=120 and (d#>>'{handovers,outgoing,count}')::int=1,d->'handovers';
 assert (d#>>'{handovers,incoming,IQD}')::numeric=70 and (d#>>'{handovers,incoming,USD}')::numeric=4 and (d#>>'{handovers,incoming,count}')::int=2,d->'handovers';
 assert (d#>>'{handovers,pendingOutgoing,IQD}')::numeric=60 and (d#>>'{handovers,pendingOutgoing,count}')::int=1,d->'handovers';
 assert (d#>>'{cash,USD}')::numeric=5 and (d#>>'{cash,IQD}')::numeric=-248,d->'cash';
 assert (d#>>'{expenses,cash,IQD}')::numeric=30 and (d#>>'{expenses,cash,USD}')::numeric=2 and (d#>>'{expenses,cash,count}')::int=2,d->'expenses';
 assert (d#>>'{expenses,companySaleIQD}')::numeric=70 and (d#>>'{expenses,customerSaleIQD}')::numeric=15
  and (d#>>'{expenses,personalProfitIQD}')::numeric=10 and (d#>>'{expenses,systemInstallationIQD}')::numeric=60,d->'expenses';
 assert (d#>>'{review,checkedTransfers}')::int=5 and (d#>>'{review,differenceCount}')::int=1,d->'review';
 assert exists(select 1 from jsonb_array_elements(d#>'{review,differences}') x where x->>'kind'='transfer_refund'
  and x->>'ref'=pg_temp.person(104)::text and (x->>'expected')::numeric=900 and (x->>'posted')::numeric=880),d->'review';
 assert not exists(select 1 from jsonb_array_elements(d->'recent')x where x->>'id'='tx:-414105'),'Unrelated receipt appeared in recent activity';
 assert (public.solar_user_activity(jsonb_build_object('ownerId',pg_temp.person(2)))#>>'{profit,earnedIQD}')::numeric=-2725,
  'Personal external balance adjustment counted as earned company income';
 assert (pg_temp.detail(9)#>>'{user,active}')::boolean=false and (pg_temp.detail(9)#>>'{sales,count}')::int=0;
 ops:=pg_temp.detail(4)->'operations';
 assert (ops#>>'{warehouse,prepared}')::int=1 and (ops#>>'{warehouse,edited}')::int=1 and (ops#>>'{warehouse,reopened}')::int=1 and (ops#>>'{warehouse,transfersPrepared}')::int=1,ops;
 assert jsonb_array_length(ops->'recent')>=4,ops;
 ops:=pg_temp.detail(5)->'operations';
 assert (ops#>>'{installer,scheduled}')::int=1 and (ops#>>'{installer,started}')::int=1 and (ops#>>'{installer,completed}')::int=0 and (ops#>>'{installer,closed}')::int=0,ops;
 ops:=pg_temp.detail(10)->'operations';
 assert (ops#>>'{installer,completed}')::int=1 and (ops#>>'{installer,scheduled}')::int=0,ops;

 foreach n in array array[1,6,7] loop
  begin perform pg_temp.detail(n);raise exception 'Admin target exposed'; exception when insufficient_privilege then null;end;
 end loop;
 foreach n in array array[2,4,5,6,7,8] loop
  perform pg_temp.login(n);
  begin perform public.solar_user_activity('{}');raise exception 'Non-admin actor listed users';exception when insufficient_privilege then null;end;
  begin perform pg_temp.detail(2);raise exception 'Non-admin actor read another dashboard';exception when insufficient_privilege then null;end;
 end loop;
 perform pg_temp.login(1);
 begin perform public.solar_user_activity(jsonb_build_object('ownerId',pg_temp.person(2),'from','2024-05-11','to','2024-05-10'));raise exception 'Inverted period accepted';exception when invalid_parameter_value then null;end;
 begin perform public.solar_user_activity(jsonb_build_object('ownerId',pg_temp.person(2),'to','2099-01-01'));raise exception 'Future period accepted';exception when invalid_parameter_value then null;end;
 assert pg_temp.fingerprint()=current_setting('test.activity.before'),'Activity reads changed ledger history';
 assert not has_function_privilege('anon','public.solar_user_activity(jsonb)','EXECUTE');
 assert not has_function_privilege('authenticated','solar_private.user_activity_operations(uuid,date,date)','EXECUTE');
end $$;
reset role;
rollback;
\echo PASS user activity, office admin gate, roles, owners, Baghdad dates, signed balances, distinct currencies and read-only reporting
