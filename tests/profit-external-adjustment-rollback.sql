-- Exercise the authorized entry points against a disposable database.
\set ON_ERROR_STOP on
begin;
load 'safeupdate';

insert into public.profiles(id,display_name,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000411301','إدارة التسوية الخارجية',true,'admin_staff',true,'{}'),
 ('00000000-0000-0000-0000-000000411302','المستخدم صاحب الرصيد',false,'admin_staff',true,'{"profit":true,"profitSettlement":true}'),
 ('00000000-0000-0000-0000-000000411303','مستخدم ربح مستقل',false,'admin_staff',true,'{"profit":true,"profitSettlement":true}'),
 ('00000000-0000-0000-0000-000000411304','مخزني',true,'warehouse',true,'{}'),
 ('00000000-0000-0000-0000-000000411305','مهندس',true,'installer',true,'{}'),
 ('00000000-0000-0000-0000-000000411306','مدير موقوف',true,'admin_staff',false,'{}');
insert into public.suppliers(id,name,account_currency) values (-411301,'مورد تسوية خارجية','IQD');
insert into public.transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at) values
 (-411301,'sale',100000,100000,25000,true,false,'credit','00000000-0000-0000-0000-000000411302','00000000-0000-0000-0000-000000411302',now()-interval '3 days'),
 (-411302,'sale',80000,80000,40000,true,false,'credit','00000000-0000-0000-0000-000000411303','00000000-0000-0000-0000-000000411303',now()-interval '3 days');
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id,cash_purpose,created_at) values
 (-411303,'cash_expense',125000.25,false,'00000000-0000-0000-0000-000000411302','00000000-0000-0000-0000-000000411302','expense',now()-interval '2 days');

create function pg_temp.financial_records() returns text language sql security definer set search_path='' as $$
 select md5(jsonb_build_array(
  (select jsonb_agg(to_jsonb(t) order by id) from public.transactions t),
  (select jsonb_agg(to_jsonb(t) order by id) from public.transaction_items t),
  (select jsonb_agg(to_jsonb(t) order by to_jsonb(t)::text) from public.cash_ledger t),
  (select jsonb_agg(to_jsonb(t) order by id) from public.solar_cash_entries t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.supplier_fx_entries t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.wallet_fx_entries t),
  (select jsonb_agg(to_jsonb(t) order by owner_id,source_key) from solar_private.profit_checkpoints t),
  (select jsonb_agg(to_jsonb(t) order by id) from solar_private.profit_settlements t),
  (select jsonb_agg(to_jsonb(t) order by id) from public.products t)
 )::text)
$$;
create function pg_temp.overview(owner_id uuid) returns jsonb language sql as $$
 select public.solar_profit_workspace('overview',null,jsonb_build_object('ownerId',owner_id))
$$;
create function pg_temp.adjustment_body(owner_id uuid,target numeric) returns jsonb language sql as $$
 select jsonb_build_object('ownerId',owner_id,'targetBalance',target,'note','اختبار تسوية أرباح خارجية',
   'expectedToken',pg_temp.overview(owner_id)->>'externalAdjustmentToken')
$$;
create function pg_temp.reject_call(action text,nonce uuid,body jsonb,codes text[] default null)
 returns void language plpgsql as $$
begin
 begin
  perform public.solar_profit_workspace(action,nonce,body);
 exception when others then
  if codes is not null and not(sqlstate=any(codes)) then raise;end if;
  return;
 end;
 raise exception 'Unexpected success for %',action;
end
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411301',true);
do $$
declare
 owner_id constant uuid:='00000000-0000-0000-0000-000000411302';
 other_id constant uuid:='00000000-0000-0000-0000-000000411303';
 admin_id constant uuid:='00000000-0000-0000-0000-000000411301';
 before_records text:=pg_temp.financial_records();
 before_company jsonb:=public.solar_profit_workspace('balance',null,'{"ownerId":"all"}');
 other_before jsonb:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',other_id));
 before_capital jsonb:=public.solar_capital_snapshot();
 body jsonb; nonce uuid:=gen_random_uuid(); saved jsonb; overview jsonb; result jsonb;
 caller uuid; approved_codes text[]:=array['PT409','40001'];
begin
 assert(pg_temp.overview(owner_id)->>'retainedProfit')::numeric=-100000.25,'Signed opening retained balance';
 body:=pg_temp.adjustment_body(owner_id,0);
 assert nullif(body->>'expectedToken','') is not null,'Admin preview has no concurrency token';
 saved:=public.solar_profit_workspace('external_adjust',nonce,body);
 assert saved->>'ownerId'=owner_id::text and(saved->>'before')::numeric=-100000.25
    and(saved->>'after')::numeric=0 and(saved->>'delta')::numeric=100000.25,'Reset from a negative balance must add its magnitude';
 assert nullif(saved->>'createdAt','') is not null and nullif(saved->>'actorName','') is not null
    and saved->>'note'=body->>'note','Missing audit information';
 assert public.solar_profit_workspace('external_adjust',nonce,body)=saved,'Lost idempotency for a retried adjustment';
 perform pg_temp.reject_call('external_adjust',nonce,body||'{"targetBalance":1}',approved_codes);
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body||'{"targetBalance":7}',approved_codes);
 overview:=pg_temp.overview(owner_id);
 assert(overview->>'retainedProfit')::numeric=0 and(overview->>'available')::numeric=0,'Reset not reflected in personal workspace';
 assert(overview->'externalAdjustments'->0->>'id')=saved->>'id','No history of direct settlement';
 assert(select count(*)=1 from jsonb_array_elements(overview->'rows') x where x->>'kind'='external_adjustment');
 result:=public.solar_profit_detail('adjustment:'||(saved->>'id'),owner_id);
 assert result#>>'{movement,kind}'='external_adjustment' and result->>'invoice' is null,'Adjustment incorrectly linked to an invoice';

 -- A currency fraction can be set without rounding retained profit to whole dinars.
 body:=pg_temp.adjustment_body(owner_id,-1500.50);
 result:=public.solar_profit_workspace('external_adjust',gen_random_uuid(),body);
 assert(result->>'after')::numeric=-1500.5 and(result->>'delta')::numeric=-1500.5;
 body:=pg_temp.adjustment_body(owner_id,3400.75);
 result:=public.solar_profit_workspace('external_adjust',gen_random_uuid(),body);
 assert(result->>'after')::numeric=3400.75 and(result->>'delta')::numeric=4901.25;
 result:=public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',owner_id,'to',(now()at time zone'Asia/Baghdad')::date-1));
 assert(result->>'remaining')::numeric=3400.75 and(result#>>'{period,earned}')::numeric=-100000.25,'Historical period was rewritten';
 assert not exists(select 1 from jsonb_array_elements(result->'rows') x where x->>'kind'='external_adjustment');

 body:=pg_temp.adjustment_body(owner_id,12);
 foreach caller in array array[owner_id,other_id,'00000000-0000-0000-0000-000000411304'::uuid,
      '00000000-0000-0000-0000-000000411305'::uuid,'00000000-0000-0000-0000-000000411306'::uuid]loop
  perform set_config('request.jwt.claim.sub',caller::text,true);
  perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body,array['42501']);
 end loop;
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 result:=pg_temp.overview(owner_id);
 assert(result->>'retainedProfit')::numeric=3400.75;
 perform pg_temp.reject_call('overview',null,jsonb_build_object('ownerId',other_id),array['42501']);
 perform set_config('request.jwt.claim.sub',other_id::text,true);
 assert not exists(select 1 from jsonb_array_elements(pg_temp.overview(other_id)->'rows') x where x->>'kind'='external_adjustment');
 begin perform public.solar_profit_detail('adjustment:'||(saved->>'id'),owner_id);
  raise exception 'Foreign adjustment detail exposed';
 exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body||'{"targetBalance":1.111}');
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body||'{"targetBalance":"NaN"}');
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body||'{"targetBalance":null}');
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),body||jsonb_build_object('note',repeat('ع',2001)));
 assert pg_temp.financial_records()=before_records,'A personal adjustment wrote into financial records, cash, or ordinary settlements';
 assert public.solar_profit_workspace('balance',null,'{"ownerId":"all"}')=before_company,'Personal adjustment affected company reporting';
 assert public.solar_profit_workspace('balance',null,jsonb_build_object('ownerId',other_id))=other_before,'Other account changed';
 assert public.solar_capital_snapshot()=before_capital,'Personal adjustment affected company capital';
 assert not has_table_privilege('authenticated','solar_private.profit_balance_adjustments','INSERT, UPDATE, DELETE');
 assert not has_function_privilege('anon','public.solar_profit_workspace(text,uuid,jsonb)','EXECUTE');
 perform set_config('test.external.stale',pg_temp.adjustment_body(owner_id,0)::text,true);
end
$$;
reset role;

-- A new authorized sale increases remaining from the corrected amount. It also
-- invalidates a previously reviewed target without invalidating its audit trail.
insert into public.transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)
 values(-411304,'sale',40000,40000,1000,true,false,'credit','00000000-0000-0000-0000-000000411302','00000000-0000-0000-0000-000000411302');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411301',true);
do $$
declare owner_id constant uuid:='00000000-0000-0000-0000-000000411302';
begin
 assert(pg_temp.overview(owner_id)->>'retainedProfit')::numeric=4400.75;
 perform pg_temp.reject_call('external_adjust',gen_random_uuid(),current_setting('test.external.stale')::jsonb,array['PT409','40001']);
end
$$;

-- A pending request may refer to yesterday's earnings. Subsequent personal
-- adjustments must invalidate approval even when that period's sales did not change.
do $$
declare owner_id constant uuid:='00000000-0000-0000-0000-000000411303';
 admin_id constant uuid:='00000000-0000-0000-0000-000000411301';
 yesterday date:=(now()at time zone'Asia/Baghdad')::date-1;
 old_period jsonb:=jsonb_build_object('ownerId',owner_id,'to',yesterday);
 preview jsonb; req jsonb; decision jsonb; result jsonb; item jsonb;
begin
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 preview:=public.solar_profit_workspace('overview',null,old_period);
 req:=public.solar_profit_workspace('request',gen_random_uuid(),old_period||jsonb_build_object('expectedToken',preview->>'token'));
 assert req->>'status'='pending';
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 perform public.solar_profit_workspace('external_adjust',gen_random_uuid(),pg_temp.adjustment_body(owner_id,50000));
 select value into strict item from jsonb_array_elements(pg_temp.overview(owner_id)->'requests') where value->>'id'=req->>'id';
 decision:=jsonb_build_object('id',req->>'id','expectedToken',item->>'token','share',40000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge');
 perform pg_temp.reject_call('approve',gen_random_uuid(),decision,array['40001','PT409']);
 result:=public.solar_profit_workspace('reject',gen_random_uuid(),decision||jsonb_build_object('note','طلب قديم'));
 assert result->>'status'='rejected';
 perform public.solar_profit_workspace('external_adjust',gen_random_uuid(),pg_temp.adjustment_body(owner_id,27500));
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 preview:=public.solar_profit_workspace('overview',null,old_period);
 perform pg_temp.reject_call('request',gen_random_uuid(),old_period||jsonb_build_object('expectedToken',preview->>'token'));
 preview:=pg_temp.overview(owner_id);
 assert(preview->>'available')::numeric=27500 and(preview->>'retainedProfit')::numeric=27500;
 req:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',preview->>'token'));
 assert(req->>'profit')::numeric=27500;
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 select value into strict item from jsonb_array_elements(pg_temp.overview(owner_id)->'requests') where value->>'id'=req->>'id';
 decision:=jsonb_build_object('id',req->>'id','expectedToken',item->>'token','share',27500,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge');
 result:=public.solar_profit_workspace('approve',gen_random_uuid(),decision);
 assert result->>'status'='approved' and(result->>'share')::numeric=27500;
 preview:=pg_temp.overview(owner_id);
 assert(preview->>'available')::numeric=0 and(preview->>'retainedProfit')::numeric=0,'Subsequent ordinary approval failed to settle the adjusted amount once';
end
$$;
reset role;

-- Older unlinked profit distributions reduce retained profit but are absent
-- from the original settlement source list. A target reset must reconcile
-- that prior difference once, so later earnings can be settled normally.
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions)
 values('00000000-0000-0000-0000-000000411307','توزيع أرباح قديم',false,'admin_staff',true,'{"profit":true,"profitSettlement":true}');
insert into public.transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)
 values(-411305,'sale',500,500,100,true,false,'credit','00000000-0000-0000-0000-000000411307','00000000-0000-0000-0000-000000411307');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411301',true);
do $$
declare owner_id constant uuid:='00000000-0000-0000-0000-000000411307'; preview jsonb; saved jsonb;
begin
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',owner_id,'mode','deposit','currency','IQD','amount',200,'note','تمويل قاصة الاختبار'));
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',owner_id,'mode','distribution','currency','IQD','amount',30,'note','توزيع أرباح عادي'));
 preview:=pg_temp.overview(owner_id);
 assert(preview->>'retainedProfit')::numeric=70 and(preview->>'available')::numeric=100,'Fixture should have a previous direct distribution';
 saved:=public.solar_profit_workspace('external_adjust',gen_random_uuid(),pg_temp.adjustment_body(owner_id,0));
 assert(saved->>'before')::numeric=70 and(saved->>'delta')::numeric=-70,'Reset must use retained profit after the distribution';
 assert(pg_temp.overview(owner_id)->>'retainedProfit')::numeric=0;
end
$$;
reset role;
insert into public.transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)
 values(-411306,'sale',50,50,9,true,false,'credit','00000000-0000-0000-0000-000000411307','00000000-0000-0000-0000-000000411307');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411307',true);
do $$
declare owner_id constant uuid:='00000000-0000-0000-0000-000000411307'; preview jsonb; req jsonb; item jsonb; decision jsonb;
begin
 preview:=pg_temp.overview(owner_id);
 assert(preview->>'retainedProfit')::numeric=9 and(preview->>'available')::numeric=9,'Previous withdrawal left phantom earnings in the next settlement';
 req:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',preview->>'token'));
 assert(req->>'profit')::numeric=9;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000411301',true);
 select value into strict item from jsonb_array_elements(pg_temp.overview(owner_id)->'requests') where value->>'id'=req->>'id';
 decision:=jsonb_build_object('id',req->>'id','expectedToken',item->>'token','share',9,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge');
 perform public.solar_profit_workspace('approve',gen_random_uuid(),decision);
 preview:=pg_temp.overview(owner_id);
 assert(preview->>'retainedProfit')::numeric=0 and(preview->>'available')::numeric=0;
end
$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS signed direct personal profit adjustments, idempotence, scope, account history, subsequent earnings and settlements
