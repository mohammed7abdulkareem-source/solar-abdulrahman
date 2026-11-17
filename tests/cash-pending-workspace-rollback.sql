\set ON_ERROR_STOP on
-- Disposable database only: all profiles, transfers and cash postings roll back.
load 'safeupdate';
begin;
select set_config('test.cash418.baselineUSD',(select coalesce(sum(delta),0)::text from solar_private.cash_movements()where currency='USD'),true);
insert into public.profiles(id,display_name,username,user_type,is_admin,active,permissions) values
('00000000-0000-0000-0000-000000418101','مدير كشف التحويل','pending418admin','admin_staff',true,true,'{}'),
('00000000-0000-0000-0000-000000418102','المرسل ألف','pending418a','admin_staff',false,true,'{"cash":true,"cashTransferSend":true,"financeReceive":true,"cashExpense":true}'),
('00000000-0000-0000-0000-000000418103','المستلم باء','pending418b','admin_staff',false,true,'{"financeReceive":true}'),
('00000000-0000-0000-0000-000000418104','المرسل جيم','pending418c','admin_staff',false,true,'{"cashTransferSend":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418105','طرف أجنبي دال','pending418d','admin_staff',false,true,'{"financeReceive":true}'),
('00000000-0000-0000-0000-000000418106','قارئ قاصته فقط','pending418view','admin_staff',false,true,'{"cash":true,"financeReceive":true}'),
('00000000-0000-0000-0000-000000418107','مخزن برصيد قديم','pending418warehouse','admin_staff',true,true,'{"financeReceive":true}'),
('00000000-0000-0000-0000-000000418108','مهندس بصلاحية قديمة','pending418installer','installer',true,true,'{"financeReceive":true}'),
('00000000-0000-0000-0000-000000418109','مدير غير فعال','pending418inactiveadmin','admin_staff',true,false,'{}'),
('00000000-0000-0000-0000-000000418110','قاصة غير فعالة ممولة','pending418inactivecash','admin_staff',false,true,'{}'),
('00000000-0000-0000-0000-000000418111','قاصة غير فعالة سالبة','pending418negative','admin_staff',false,false,'{}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418101',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418102","mode":"deposit","currency":"IQD","amount":10000,"note":"تمويل معزول"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418102","mode":"deposit","currency":"USD","amount":10,"rate":1500,"note":"دولار مستقل"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418104","mode":"deposit","currency":"IQD","amount":5000,"note":"تمويل مستقل"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418104","mode":"deposit","currency":"USD","amount":20,"rate":1500,"note":"دولار مستقل"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418106","mode":"deposit","currency":"IQD","amount":350,"note":"تمويل القارئ"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418110","mode":"deposit","currency":"IQD","amount":400,"note":"رصيد قبل إيقاف المستخدم"}');
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000418107","mode":"deposit","currency":"IQD","amount":20,"note":"رصيد قبل تغيير الدور"}');
-- An existing negative owner must not disappear from the admin's cash total.
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id)values(-418111,'cash_expense',25,true,'00000000-0000-0000-0000-000000418111','00000000-0000-0000-0000-000000418111');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418102',true);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418201','00000000-0000-0000-0000-000000418103',300,25,'مصروف خاص لا يظهر في ملخص المعلق','ملاحظة خاصة لا تعرض في الملخص');
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418202','00000000-0000-0000-0000-000000418106',50);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418205','00000000-0000-0000-0000-000000418107',30);
do $$begin for i in 1..125 loop perform public.solar_cash_transfer_send(gen_random_uuid(),'00000000-0000-0000-0000-000000418103',1.25);end loop;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418104',true);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418203','00000000-0000-0000-0000-000000418105',700);
select public.solar_cash_transfer_send('00000000-0000-0000-0000-000000418204','00000000-0000-0000-0000-000000418102',80);
reset role;
update public.profiles set active=false where id='00000000-0000-0000-0000-000000418110';
update public.profiles set user_type='warehouse' where id='00000000-0000-0000-0000-000000418107';
update public.profiles set permissions='{"cash":true}' where id='00000000-0000-0000-0000-000000418106';
-- Current pending requests must survive period, query and currency filters.
update solar_private.cash_transfers set created_at='2020-01-01T00:00:00Z' where id='00000000-0000-0000-0000-000000418201';
create temporary table cash418_history as select
 (select md5(coalesce(jsonb_agg(to_jsonb(t)order by id)::text,'[]'))from public.transactions t) tx,
 (select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from solar_private.wallet_fx_entries e) wallet,
 (select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from public.solar_cash_entries e) entries,
 (select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from solar_private.cash_transfers e) transfers;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418101',true);
do $$declare a jsonb;b jsonb;r jsonb;row_keys text[];iqd numeric;usd numeric;begin
 a:=public.solar_cash_workspace();
 if(a->'summary'->>'pendingIQD')::numeric<>1316.25 or(a->'summary'->>'pendingCount')::integer<>130 or jsonb_array_length(a->'pendingTransfers')<>130 then raise exception 'pending requests capped or amount includes expenses %',a->'summary';end if;
 if(a->'summary'->>'transit')::numeric<>(a->'summary'->>'pendingIQD')::numeric then raise exception 'global pending differs from transit ledger';end if;
 if(a->'summary'->>'USD')::numeric<>current_setting('test.cash418.baselineUSD')::numeric+30 or(a->'summary'->>'availableUSD')::numeric<>current_setting('test.cash418.baselineUSD')::numeric+30 then raise exception 'pending mixed currencies';end if;
 if(a->'summary'->>'IQD')::numeric-(a->'summary'->>'transit')::numeric<>(a->'summary'->>'availableIQD')::numeric then raise exception 'available cash counted transit';end if;
 select sum((x->>'IQD')::numeric),sum((x->>'USD')::numeric)into iqd,usd from jsonb_array_elements(a->'owners')x;
 if iqd<>(a->'summary'->>'availableIQD')::numeric or usd<>(a->'summary'->>'availableUSD')::numeric then raise exception 'visible cashboxes do not reconcile with available totals';end if;
 for r in select value from jsonb_array_elements(a->'pendingTransfers')loop
  select array_agg(key order by key collate "C")into row_keys from jsonb_object_keys(r)key;
  if row_keys<>array['amount','created_at','currency','id','recipientName','recipient_id','senderName','sender_id','status']then raise exception 'unexpected pending metadata %',row_keys;end if;
  if r->>'status'<>'pending' or r->>'currency'<>'IQD' then raise exception 'invalid pending state/currency';end if;
 end loop;
 if(a->'pendingTransfers')::text like '%مصروف خاص%' or(a->'pendingTransfers')::text like '%ملاحظة خاصة%' then raise exception 'private transfer fields escaped whitelist';end if;
 if not exists(select 1 from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000418110' and x->>'active'='false' and(x->>'IQD')::numeric=400) then raise exception 'inactive funded cashbox omitted';end if;
 if not exists(select 1 from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000418111' and(x->>'IQD')::numeric=-25) then raise exception 'negative inactive cashbox omitted';end if;
 if not exists(select 1 from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000418107' and x->>'userType'='warehouse' and(x->>'IQD')::numeric=20) then raise exception 'funded operational owner omitted';end if;
 if exists(select 1 from jsonb_array_elements(a->'owners')x where x->>'id'='00000000-0000-0000-0000-000000418108')then raise exception 'zero operational owner newly exposed';end if;
 b:=public.solar_cash_workspace('{"from":"2099-01-01","to":"2099-01-31","currency":"USD","direction":"out","query":"لا توجد حركة بهذا البيان","limit":1}');
 if b->'pendingTransfers'<>a->'pendingTransfers' or b->'summary'->'pendingIQD'<>a->'summary'->'pendingIQD' or(b->>'count')::integer<>0 then raise exception 'ledger filters changed current pending requests';end if;
 b:=public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000418102"}');
 if(b->'summary'->>'pendingIQD')::numeric<>616.25 or(b->'summary'->>'pendingCount')::integer<>129 or(b->'summary'->>'transit')::numeric<>0 then raise exception 'admin selected-owner pending scope incorrect %',b->'summary';end if;
 select(x->>'IQD')::numeric into iqd from jsonb_array_elements(b->'owners')x where x->>'id'='00000000-0000-0000-0000-000000418102';
 if iqd<>(b->'summary'->>'availableIQD')::numeric or jsonb_array_length(b->'owners')<>jsonb_array_length(a->'owners')then raise exception 'selected balance/directory contract changed';end if;
 if exists(select 1 from jsonb_array_elements(b->'pendingTransfers')x where x->>'sender_id'<>'00000000-0000-0000-0000-000000418102' and x->>'recipient_id'<>'00000000-0000-0000-0000-000000418102')then raise exception 'selected owner leaked unrelated transfer';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418102',true);
do $$declare a jsonb;b jsonb;begin
 a:=public.solar_cash_workspace();
 if(a->'summary'->>'pendingIQD')::numeric<>616.25 or jsonb_array_length(a->'owners')<>1 or(a->'summary'->>'transit')::numeric<>0 then raise exception 'staff scope wrong';end if;
 if a::text like '%طرف أجنبي دال%' or a::text like '%00000000-0000-0000-0000-000000418105%'then raise exception 'unrelated party leaked';end if;
 if not exists(select 1 from jsonb_array_elements(a->'pendingTransfers')r where r->>'id'='00000000-0000-0000-0000-000000418201' and r->>'senderName'='المرسل ألف' and r->>'recipientName'='المستلم باء' and(r->>'amount')::numeric=300)then raise exception 'sender recipient names or amount incorrect';end if;
 begin perform public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000418104"}');raise exception 'staff switched owner';exception when insufficient_privilege then null;end;
 b:=public.solar_cash_transfer_overview();
 if exists(select 1 from jsonb_array_elements(b->'managers')x where x->>'id' in('00000000-0000-0000-0000-000000418107','00000000-0000-0000-0000-000000418108','00000000-0000-0000-0000-000000418109','00000000-0000-0000-0000-000000418110'))then raise exception 'ineligible transfer recipient selectable';end if;
 if not exists(select 1 from jsonb_array_elements(b->'managers')x where x->>'id'='00000000-0000-0000-0000-000000418103')then raise exception 'normal recipient disappeared';end if;
 foreach a in array array['{"recipient":"00000000-0000-0000-0000-000000418107"}'::jsonb,'{"recipient":"00000000-0000-0000-0000-000000418108"}'::jsonb,'{"recipient":"00000000-0000-0000-0000-000000418109"}'::jsonb]loop
  begin perform public.solar_cash_transfer_send(gen_random_uuid(),(a->>'recipient')::uuid,1);raise exception 'new transfer to ineligible recipient accepted';exception when insufficient_privilege then null;end;
 end loop;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418106',true);
do $$declare a jsonb;begin
 a:=public.solar_cash_workspace();
 if(a->'summary'->>'pendingIQD')::numeric<>50 or(a->'summary'->>'pendingCount')::integer<>1 or(a->'summary'->>'availableIQD')::numeric<>350 then raise exception 'cash-view-only own pending/available wrong';end if;
 if a::text like '%طرف أجنبي دال%' or a::text like '%المستلم باء%'then raise exception 'cash view leaked unrelated names';end if;
 begin perform public.solar_cash_transfer_overview();raise exception 'cash view gained transfer module';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418202','accepted');raise exception 'cash view gained receipt authority';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_reconcile('context');raise exception 'V417 admin guard regressed';exception when insufficient_privilege then null;end;
end $$;
do $$declare id uuid;begin
 foreach id in array array['00000000-0000-0000-0000-000000418107'::uuid,'00000000-0000-0000-0000-000000418108'::uuid,'00000000-0000-0000-0000-000000418109'::uuid]loop
  perform set_config('request.jwt.claim.sub',id::text,true);
  begin perform public.solar_cash_workspace();raise exception 'operational/inactive actor read cash workspace';exception when insufficient_privilege then null;end;
 end loop;
end $$;
reset role;
do $$declare b record;begin
 select * into b from cash418_history;
 if b.tx is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(t)order by id)::text,'[]'))from public.transactions t)
 or b.wallet is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from solar_private.wallet_fx_entries e)
 or b.entries is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from public.solar_cash_entries e)
 or b.transfers is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e)order by id)::text,'[]'))from solar_private.cash_transfers e)then raise exception 'reads or denied actions changed cash history';end if;
end $$;
-- Each existing state transition removes exactly its pending amount. Direct
-- administrator handovers are immediate and never become pending requests.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418102',true);
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418205','cancelled');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418103',true);
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418201','accepted');
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418201','accepted');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418102',true);
select public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000418204','rejected');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418101',true);
do $$declare a jsonb;b jsonb;begin
 a:=public.solar_cash_workspace();
 if(a->'summary'->>'pendingIQD')::numeric<>906.25 or(a->'summary'->>'pendingCount')::integer<>127 or(a->'summary'->>'transit')::numeric<>906.25 then raise exception 'pending state transitions wrong %',a->'summary';end if;
 if exists(select 1 from jsonb_array_elements(a->'pendingTransfers')x where x->>'id'in('00000000-0000-0000-0000-000000418201','00000000-0000-0000-0000-000000418204','00000000-0000-0000-0000-000000418205'))then raise exception 'decided transfer remained pending';end if;
 perform public.solar_cash_record('transfer',null,gen_random_uuid(),'{"senderId":"00000000-0000-0000-0000-000000418104","recipientId":"00000000-0000-0000-0000-000000418103","amount":100,"currency":"IQD","note":"تسليم مباشر معزول"}');
 b:=public.solar_cash_workspace();
 if b->'pendingTransfers'<>a->'pendingTransfers' or b->'summary'->'availableIQD'<>a->'summary'->'availableIQD' or b->'summary'->'transit'<>a->'summary'->'transit' then raise exception 'direct handover became pending or changed combined cash';end if;
end $$;
reset role;
do $$begin
 if md5(pg_get_functiondef('solar_private.cash_allowed(text)'::regprocedure))<>'596911077f9ada1d5ebf08299f65f0ce'
 or md5(pg_get_functiondef('solar_private.cash_reconcile(text,uuid,jsonb)'::regprocedure))<>'c3b07e867c70d059ced268838c4517e2'then raise exception 'strict admin policy definitions changed';end if;
 if has_function_privilege('anon','public.solar_cash_workspace(jsonb)','execute') or has_table_privilege('authenticated','solar_private.cash_transfers','select')then raise exception 'transfer data access broadened';end if;
 raise notice 'PASS same-snapshot pending totals and parties; >100 pending, filters, own scope, view-only read, inactive/negative/dedicated funded owners, unchanged financial reads, recipient eligibility, accept/reject/cancel, immediate handover and V417 guards';
end $$;
rollback;
