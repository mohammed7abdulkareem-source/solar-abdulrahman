\set ON_ERROR_STOP on
-- Run only against an isolated database. All fixtures and postings are rolled back.
load 'safeupdate';
begin;
insert into public.profiles(id,display_name,username,user_type,active,is_admin,permissions) values
('00000000-0000-0000-0000-000000417101','مدير اختبار المطابقة','cash417admin','admin_staff',true,true,'{}'),
('00000000-0000-0000-0000-000000417102','موظف بكل صلاحيات الصندوق','cash417staff','admin_staff',true,false,'{"cash":true,"cashAdminTools":true,"cashDeposit":true,"cashExpense":true,"cashExchange":true,"cashExternalProfit":true,"cashTransferSend":true,"financeReceive":true,"adminOnly":true,"is_admin":true}'),
('00000000-0000-0000-0000-000000417103','موظف دون أدوات','cash417ordinary','admin_staff',true,false,'{"cash":true}'),
('00000000-0000-0000-0000-000000417104','مدير غير نشط','cash417inactive','admin_staff',false,true,'{"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417105','مخزن بصفة إدارية قديمة','cash417warehouse','warehouse',true,true,'{"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417106','مهندس بصفة إدارية قديمة','cash417installer','installer',true,true,'{"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417107','مدير سابق','cash417former','admin_staff',true,false,'{"cashAdminTools":true}'),
('00000000-0000-0000-0000-000000417108','مستلم اختبار','cash417recipient','admin_staff',true,false,'{"financeReceive":true}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417101',true);
select public.solar_exchange_rate_set(1500,(public.solar_exchange_rate_get()->>'revision')::bigint);
select public.solar_cash_save('00000000-0000-0000-0000-000000417111','{"ownerId":"00000000-0000-0000-0000-000000417102","mode":"deposit","currency":"IQD","amount":1000,"note":"رصيد اختبار معزول"}');
select public.solar_cash_save('00000000-0000-0000-0000-000000417112','{"ownerId":"00000000-0000-0000-0000-000000417102","mode":"deposit","currency":"USD","amount":5,"rate":1500,"note":"رصيد دولار معزول"}');
-- Model a valid pre-upgrade staff request. Its cached success must not bypass
-- current authorization; neither its payload nor historical response is rewritten.
insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values
('00000000-0000-0000-0000-000000417113','00000000-0000-0000-0000-000000417107','cash_reconcile','{"ownerId":"00000000-0000-0000-0000-000000417107","mode":"zero","currency":"both","note":"طلب تاريخي"}','{"requestId":"00000000-0000-0000-0000-000000417113","mode":"cash_reconcile","rows":[]}');
-- Create authentic saved capital/legacy-wallet/correction requests as an admin,
-- then demote that actor to model old authorized staff requests after upgrade.
update public.profiles set is_admin=true where id='00000000-0000-0000-0000-000000417107';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417107',true);
do $$declare p jsonb;r jsonb;c jsonb;movement text;begin
 p:=jsonb_build_object('ownerId',auth.uid(),'mode','capital_deposit','currency','IQD','amount',100,'note','إضافة رأس مال تاريخية');
 r:=public.solar_cash_save('00000000-0000-0000-0000-000000417121',p);
 perform set_config('test.cash417.capitalpayload',p::text,true);
 movement:='tx:'||(r->>'id');perform set_config('test.cash417.capitalmovement',movement,true);
 c:=public.solar_cash_record('get',movement);
 p:=jsonb_build_object('amount',110,'note','تصحيح رأس مال تاريخي','expectedToken',c->>'token');
 perform public.solar_cash_record('update',movement,'00000000-0000-0000-0000-000000417125',p);
 perform set_config('test.cash417.capitalcorrection',p::text,true);
 p:=jsonb_build_object('ownerId',auth.uid(),'mode','capital_withdraw','currency','IQD','amount',10,'note','سحب رأس مال تاريخي');
 perform public.solar_cash_save('00000000-0000-0000-0000-000000417122',p);
 perform set_config('test.cash417.withdrawpayload',p::text,true);
 p:=jsonb_build_object('mode','deposit','amount',5,'rate',1500,'note','إضافة دولار تاريخية');
 perform public.solar_fx('wallet','00000000-0000-0000-0000-000000417123',p);
 perform set_config('test.cash417.walletdeposit',p::text,true);
 p:=jsonb_build_object('mode','withdraw','amount',1,'rate',1500,'note','سحب دولار تاريخي');
 perform public.solar_fx('wallet','00000000-0000-0000-0000-000000417124',p);
 perform set_config('test.cash417.walletwithdraw',p::text,true);
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','external_profit','currency','IQD','amount',300,'note','ربح تاريخي للاختبار'));
 p:=jsonb_build_object('ownerId',auth.uid(),'mode','distribution','currency','IQD','amount',50,'note','توزيع تاريخي للاختبار');
 r:=public.solar_cash_save('00000000-0000-0000-0000-000000417126',p);
 perform set_config('test.cash417.distributionpayload',p::text,true);
 movement:='tx:'||(r->>'id');perform set_config('test.cash417.distributionmovement',movement,true);
 c:=public.solar_cash_record('get',movement);
 p:=jsonb_build_object('amount',40,'note','تصحيح توزيع تاريخي','expectedToken',c->>'token');
 perform public.solar_cash_record('update',movement,'00000000-0000-0000-0000-000000417127',p);
 perform set_config('test.cash417.distributioncorrection',p::text,true);
end $$;
update public.profiles set is_admin=false,permissions='{"cash":true,"cashAdminTools":true,"adminOnly":true}' where id='00000000-0000-0000-0000-000000417107';
create temporary table cash417_before as select
 (select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.transactions t) tx,
 (select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from solar_private.wallet_fx_entries e) wallet,
 (select md5(coalesce(jsonb_agg(to_jsonb(f) order by request_id)::text,'[]')) from solar_private.finance_requests f) requests,
 (select md5(coalesce(jsonb_agg(to_jsonb(c) order by kind)::text,'[]')) from solar_private.receipt_counters c) counters;
create temporary table cash417_original_tx as select id,to_jsonb(t) data from public.transactions t;
create temporary table cash417_original_wallet as select id,to_jsonb(t) data from solar_private.wallet_fx_entries t;
create temporary table cash417_history as select
 (select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from solar_private.supplier_fx_entries e) suppliers,
 (select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from public.transaction_items e) items,
 (select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from public.customers e) customers;
set local role authenticated;
do $$declare actor uuid;owner jsonb;mode text;cur text;payload jsonb;begin
 foreach actor in array array['00000000-0000-0000-0000-000000417102'::uuid,'00000000-0000-0000-0000-000000417103'::uuid,'00000000-0000-0000-0000-000000417104'::uuid,'00000000-0000-0000-0000-000000417105'::uuid,'00000000-0000-0000-0000-000000417106'::uuid,'00000000-0000-0000-0000-000000417107'::uuid] loop
  perform set_config('request.jwt.claim.sub',actor::text,true);
  for owner in select value from jsonb_array_elements(jsonb_build_array(actor,null,'00000000-0000-0000-0000-000000417101')) loop
   payload:=jsonb_build_object('ownerId',owner);
   begin perform public.solar_cash_reconcile('context',null,payload);raise exception 'unauthorized public context % %',actor,owner;exception when insufficient_privilege then null;end;
   begin perform solar_private.cash_reconcile('context',null,payload);raise exception 'unauthorized private context % %',actor,owner;exception when insufficient_privilege then null;end;
   foreach mode in array array['set','zero'] loop
    foreach cur in array array['IQD','USD','both'] loop
     begin perform public.solar_cash_reconcile('apply',gen_random_uuid(),payload||jsonb_build_object('mode',mode,'currency',cur,'target',0,'rate',1500,'expectedToken','stale-token','note','محاولة تعديل محظورة'));raise exception 'unauthorized public apply % % %',actor,mode,cur;exception when insufficient_privilege then null;end;
    end loop;
   end loop;
  end loop;
  begin perform solar_private.cash_reconcile('apply',gen_random_uuid(),jsonb_build_object('ownerId',actor,'mode','zero','currency','both'));raise exception 'unauthorized private apply %',actor;exception when insufficient_privilege then null;end;
  foreach mode in array array['capital_deposit','capital_withdraw','distribution'] loop
   foreach cur in array array['IQD','USD'] loop
    payload:=jsonb_build_object('ownerId',actor,'mode',mode,'currency',cur,'amount',1,'rate',1500,'note','محاولة أدوات إدارية');
    begin perform public.solar_cash_save(gen_random_uuid(),payload);raise exception 'unauthorized capital % % %',actor,mode,cur;exception when insufficient_privilege then null;end;
    begin perform solar_private.cash_save(gen_random_uuid(),payload);raise exception 'unauthorized private capital % % %',actor,mode,cur;exception when insufficient_privilege then null;end;
   end loop;
  end loop;
  foreach mode in array array['deposit','withdraw'] loop
   payload:=jsonb_build_object('mode',mode,'amount',1,'rate',1500,'note','محاولة دولار قديمة');
   begin perform public.solar_fx('wallet',gen_random_uuid(),payload);raise exception 'unauthorized legacy wallet % %',actor,mode;exception when insufficient_privilege then null;end;
   begin perform solar_private.fx('wallet',gen_random_uuid(),payload);raise exception 'unauthorized private wallet % %',actor,mode;exception when insufficient_privilege then null;end;
  end loop;
 end loop;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417107',true);
 begin perform public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417113','{"ownerId":"00000000-0000-0000-0000-000000417107","mode":"zero","currency":"both","note":"طلب تاريخي"}');raise exception 'former admin replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_save('00000000-0000-0000-0000-000000417121',current_setting('test.cash417.capitalpayload')::jsonb);raise exception 'former capital deposit replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_save('00000000-0000-0000-0000-000000417122',current_setting('test.cash417.withdrawpayload')::jsonb);raise exception 'former capital withdraw replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_save('00000000-0000-0000-0000-000000417126',current_setting('test.cash417.distributionpayload')::jsonb);raise exception 'former distribution replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('wallet','00000000-0000-0000-0000-000000417123',current_setting('test.cash417.walletdeposit')::jsonb);raise exception 'former legacy wallet deposit replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_fx('wallet','00000000-0000-0000-0000-000000417124',current_setting('test.cash417.walletwithdraw')::jsonb);raise exception 'former legacy wallet withdraw replay succeeded';exception when insufficient_privilege then null;end;
 foreach mode in array array['capital','distribution'] loop
  if(public.solar_cash_record('get',current_setting('test.cash417.'||mode||'movement'))->>'canEdit')::boolean is distinct from false then raise exception 'former reserved correction context allowed %',mode;end if;
  begin perform public.solar_cash_record('update',current_setting('test.cash417.'||mode||'movement'),gen_random_uuid(),'{"amount":1,"note":"تعديل محظور"}');raise exception 'former reserved correction allowed %',mode;exception when insufficient_privilege then null;end;
  begin perform public.solar_cash_record('update',current_setting('test.cash417.'||mode||'movement'),case mode when 'capital' then '00000000-0000-0000-0000-000000417125'::uuid else '00000000-0000-0000-0000-000000417127'::uuid end,current_setting('test.cash417.'||mode||'correction')::jsonb);raise exception 'former reserved correction replay allowed %',mode;exception when insufficient_privilege then null;end;
 end loop;
 -- A foreign successful request and malformed payloads reveal no cached data.
 begin perform public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417111','{}');raise exception 'foreign replay succeeded';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_reconcile(null,null,'[]');raise exception 'authorization did not precede input validation';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','',true);
 begin perform public.solar_cash_reconcile('context');raise exception 'missing auth succeeded';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$declare before_row record;begin
 select * into before_row from cash417_before;
 if before_row.tx is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(t) order by id)::text,'[]')) from public.transactions t)
 or before_row.wallet is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from solar_private.wallet_fx_entries e)
 or before_row.requests is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(f) order by request_id)::text,'[]')) from solar_private.finance_requests f)
 or before_row.counters is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(c) order by kind)::text,'[]')) from solar_private.receipt_counters c) then raise exception 'denied operation changed accounting/history';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417101',true);
do $$declare c jsonb;r jsonb;p jsonb;begin
 c:=public.solar_cash_reconcile('context',null,'{"ownerId":"00000000-0000-0000-0000-000000417102"}');
 if(c->'rows'->0->>'IQD')::numeric<>1000 or(c->'rows'->0->>'USD')::numeric<>5 then raise exception 'admin context inaccurate';end if;
 p:=jsonb_build_object('ownerId','00000000-0000-0000-0000-000000417102','mode','set','currency','IQD','target',1200,'note','تصحيح إداري معزول','expectedToken',c->>'token');
 r:=public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417114',p);
 if(r->'rows'->0->>'afterIQD')::numeric<>1200 or(r->'rows'->0->>'afterUSD')::numeric<>5 then raise exception 'admin set mixed currencies';end if;
 if public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417114',p)<>r then raise exception 'admin exact replay changed';end if;
 perform set_config('test.cash417.replay',p::text,true);
 begin perform public.solar_cash_reconcile('apply',gen_random_uuid(),p);raise exception 'stale admin token accepted';exception when sqlstate 'PT409' then null;end;
 c:=public.solar_cash_reconcile('context',null,'{"ownerId":"00000000-0000-0000-0000-000000417102"}');
 r:=public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417115',jsonb_build_object('ownerId','00000000-0000-0000-0000-000000417102','mode','set','currency','USD','target',2,'note','تصحيح دولار إداري','expectedToken',c->>'token'));
 if(r->'rows'->0->>'afterUSD')::numeric<>2 or(r->'rows'->0->>'afterBook')::numeric<>3000 or(r->'rows'->0->>'afterIQD')::numeric<>1200 then raise exception 'USD correction math changed';end if;
 c:=public.solar_cash_reconcile('context',null,'{"ownerId":"00000000-0000-0000-0000-000000417102"}');
 r:=public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417116',jsonb_build_object('ownerId','00000000-0000-0000-0000-000000417102','mode','zero','currency','both','note','تصفير إداري معزول','expectedToken',c->>'token'));
 if(r->'rows'->0->>'afterIQD')::numeric<>0 or(r->'rows'->0->>'afterUSD')::numeric<>0 or(r->'rows'->0->>'afterBook')::numeric<>0 then raise exception 'admin zero math changed';end if;
end $$;
reset role;
-- Revocation invalidates a previously successful administrator's nonce too.
update public.profiles set is_admin=false,permissions='{"cashAdminTools":true}' where id='00000000-0000-0000-0000-000000417101';
set local role authenticated;
do $$begin
 begin perform public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417114',current_setting('test.cash417.replay')::jsonb);raise exception 'demoted admin replay succeeded';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set is_admin=true,active=false where id='00000000-0000-0000-0000-000000417101';
set local role authenticated;
do $$begin
 begin perform public.solar_cash_reconcile('apply','00000000-0000-0000-0000-000000417114',current_setting('test.cash417.replay')::jsonb);raise exception 'inactive admin replay succeeded';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set active=true where id='00000000-0000-0000-0000-000000417101';
-- Existing staff posting workflows stay permissioned and operational.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417102',true);
do $$declare transfer uuid;r jsonb;begin
 r:=public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','deposit','currency','IQD','amount',1000,'note','إيداع مصرح'));
 r:=public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',auth.uid(),'mode','expense','currency','IQD','amount',100,'note','مصروف مصرح'));
 if(r->>'afterIQD')::numeric<>900 then raise exception 'ordinary deposit/expense changed';end if;
 -- Currency exchange is not a manual balance correction and stays available.
 perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"buy_usd","amount":0.1,"rate":1500,"note":"شراء دولار مصرح"}');
 perform public.solar_fx('wallet',gen_random_uuid(),'{"mode":"sell_usd","amount":0.1,"rate":1500,"note":"بيع دولار مصرح"}');
 transfer:=public.solar_cash_transfer_send(gen_random_uuid(),'00000000-0000-0000-0000-000000417108',200,0,'','تسليم مصرح');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417108',true);
 perform public.solar_cash_transfer_decide(transfer,'accepted');
 if(public.solar_cash_workspace()->'summary'->>'IQD')::numeric<>200 then raise exception 'authorized transfer receive changed';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000417102',true);
 -- No table-level substitute for the administrative reconciliation RPC.
 begin insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note) values(auth.uid(),'IQD',123,123,1,0,'cash_reconcile','محاولة مباشرة');raise exception 'raw private reconciliation allowed';exception when insufficient_privilege then null;end;
 begin insert into public.solar_cash_entries(owner_id,delta,entry_type,actor_id,notes) values(auth.uid(),123,'transfer_in',auth.uid(),'محاولة مباشرة');raise exception 'raw cash entry allowed';exception when insufficient_privilege then null;end;
 begin insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-417101,'cash_income',123,true,auth.uid(),auth.uid());raise exception 'raw cash transaction allowed';exception when insufficient_privilege then null;end;
 begin update public.transactions set total=0 where finance_request_id='00000000-0000-0000-0000-000000417111';raise exception 'raw cash balance reset allowed';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$declare history record;begin
 if exists(select 1 from cash417_original_tx b left join public.transactions t using(id) where b.data is distinct from to_jsonb(t)) then raise exception 'historical transactions rewritten';end if;
 if exists(select 1 from cash417_original_wallet b left join solar_private.wallet_fx_entries t using(id) where b.data is distinct from to_jsonb(t)) then raise exception 'historical wallet entries rewritten';end if;
 select * into history from cash417_history;
 if history.suppliers is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from solar_private.supplier_fx_entries e)
 or history.items is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from public.transaction_items e)
 or history.customers is distinct from(select md5(coalesce(jsonb_agg(to_jsonb(e) order by id)::text,'[]')) from public.customers e) then raise exception 'unrelated accounting changed';end if;
 if solar_private.cash_balance('00000000-0000-0000-0000-000000417102')<>700 then raise exception 'staff cash effect inaccurate';end if;
 if(select count(*) from solar_private.wallet_fx_entries where finance_request_id='00000000-0000-0000-0000-000000417114')<>1 then raise exception 'replay duplicated correction';end if;
 if exists(select 1 from solar_private.wallet_fx_entries where finance_request_id in('00000000-0000-0000-0000-000000417114','00000000-0000-0000-0000-000000417115','00000000-0000-0000-0000-000000417116') and gain<>0) then raise exception 'reconciliation became profit';end if;
 if has_function_privilege('anon','public.solar_cash_reconcile(text,uuid,jsonb)','execute') or has_function_privilege('anon','solar_private.cash_reconcile(text,uuid,jsonb)','execute') then raise exception 'anonymous execution exposed';end if;
 if has_table_privilege('authenticated','solar_private.wallet_fx_entries','insert') or has_table_privilege('authenticated','solar_private.finance_requests','insert') then raise exception 'private accounting writes exposed';end if;
 raise notice 'PASS active true-admin reconciliation/capital only; legacy grants and cached capital/wallet/distribution/correction replays denied; ordinary deposits, expenses, FX exchange and transfers preserved; immutable history and exact currency math';
end $$;
rollback;
