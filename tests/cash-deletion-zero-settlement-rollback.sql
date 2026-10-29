\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003880','مدير موافقة النقد',true,'admin_staff','{}','07700003880'),
('00000000-0000-0000-0000-000000003881','صاحب قاصة الحذف',false,'admin_staff','{"cash":true,"cashDeposit":true,"cashExpense":true,"profit":true,"profitSettlement":true}','07700003881'),
('00000000-0000-0000-0000-000000003882','صاحب تسوية الصفر',false,'admin_staff','{"cash":true,"profit":true,"profitSettlement":true}','07700003882'),
('00000000-0000-0000-0000-000000003883','مخزن بصلاحية قديمة',true,'warehouse','{}','07700003883'),
('00000000-0000-0000-0000-000000003884','مهندس بصلاحية قديمة',true,'installer','{}','07700003884');
insert into suppliers(id,name,account_currency)values(-388001,'مورد تسوية صفر','IQD'),(-388002,'مورد دولار تسوية صفر','USD');
insert into transactions(id,kind,total,subtotal,profit,fx_pricing,cash,payment_mode,created_by,cashbox_user_id)
values(-388001,'sale',2000000,2000000,2000000,true,false,'credit','00000000-0000-0000-0000-000000003882','00000000-0000-0000-0000-000000003882');
create function pg_temp.wallet(uid uuid)returns jsonb language sql security definer as $$select solar_private.usd_wallet(uid)$$;
create function pg_temp.financial_hash()returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.wallet_fx_entries t),(select jsonb_agg(to_jsonb(t)order by id)from solar_private.supplier_fx_entries t),
 (select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.finance_requests t),(select jsonb_agg(to_jsonb(t)order by invoice_id)from solar_private.deleted_sales t),
 (select jsonb_agg(to_jsonb(t)order by id)from solar_private.receipt_change_audit t))::text)$$;
create function pg_temp.approve_cash(tid bigint)returns uuid language plpgsql security definer as $$
declare c jsonb;r jsonb;uid text:=current_setting('request.jwt.claim.sub',true);begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',tid));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',tid,'expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
 c:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);
 perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',c->>'reviewToken'));
 perform set_config('request.jwt.claim.sub',uid,true);return(r->>'id')::uuid;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
do $$declare r jsonb;n uuid:=gen_random_uuid();b jsonb;begin
 b:='{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"deposit","currency":"IQD","amount":2000000,"note":"إيداع الحذف"}';
 r:=public.solar_cash_save(n,b);perform set_config('test.cash.deposit',r->>'id',true);perform set_config('test.cash.nonce',n::text,true);perform set_config('test.cash.payload',b::text,true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"expense","currency":"IQD","amount":479000,"note":"مصروف أول"}');perform set_config('test.cash.expense',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"expense","currency":"IQD","amount":479000,"note":"مصروف ثان"}');perform set_config('test.cash.second',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"external_profit","currency":"IQD","amount":300000,"note":"أرباح خارجية للحذف"}');perform set_config('test.cash.profit',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"capital_deposit","currency":"IQD","amount":50000,"note":"رأس مال"}');perform set_config('test.cash.capital',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"deposit","currency":"USD","amount":100,"rate":1500,"note":"دولار أصلي"}');perform set_config('test.cash.usd',r->>'id',true);
 r:=public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"expense","currency":"USD","amount":40,"rate":1600,"note":"أجور دولار"}');perform set_config('test.cash.usdexpense',r->>'id',true);
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
do $$declare c jsonb;r jsonb;b jsonb;n uuid:=gen_random_uuid();f text;begin
 c:=public.solar_cash_movement_detail('tx:'||current_setting('test.cash.expense'));assert(c->'deletion'->>'canRequest')::boolean;
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.expense')::bigint));
 assert(c->>'cashEffect')::numeric=479000;assert(c->>'profitEffectIQD')::numeric=479000;
 r:=public.solar_cash_record('get','tx:'||current_setting('test.cash.expense'));
 begin perform public.solar_cash_record('update','tx:'||current_setting('test.cash.expense'),gen_random_uuid(),jsonb_build_object('amount',0,'note','صفر لمصروف عادي','expectedToken',r->>'token'));raise exception 'FAIL zero ordinary cash';exception when invalid_parameter_value then null;end;
 b:=jsonb_build_object('invoiceId',c->'id','expectedToken',c->>'token');f:=pg_temp.financial_hash();
 r:=public.solar_receipt_delete_requests('request',n,b);assert r->>'status'='pending';perform set_config('test.cash.request',r->>'id',true);
 assert public.solar_receipt_delete_requests('request',n,b)=r;
 assert public.solar_receipt_delete_requests('request',gen_random_uuid(),b)=r;
 assert pg_temp.financial_hash()=f,'Request/replay modified cash or profits';
 c:=public.solar_cash_movement_detail('tx:'||current_setting('test.cash.expense'));assert c->'deletion'->>'pendingRequestId'=r->>'id';
 begin perform public.solar_receipt_delete_requests('approve',n,'{}');raise exception 'FAIL staff approval';exception when insufficient_privilege then null;end;
 begin delete from public.transactions where id=current_setting('test.cash.expense')::bigint;raise exception 'FAIL direct cash deletion';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003882',true);
 begin perform public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.expense')::bigint));raise exception 'FAIL foreign cash context';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('get',n);raise exception 'FAIL foreign request';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
 perform public.solar_receipt_delete_requests('reject',n,'{"note":"مراجعة المصروف"}');assert pg_temp.financial_hash()=f,'Rejection modified cash';
end$$;
reset role;
do $$begin
 assert(select count(*)from solar_notifications where delete_request_id=current_setting('test.cash.request')::uuid and event='receipt_delete_requested')=1;
 assert not exists(select 1 from solar_notifications n join profiles p on p.id=n.user_id where n.delete_request_id=current_setting('test.cash.request')::uuid and n.event='receipt_delete_requested'and(p.user_type in('warehouse','installer')or not p.is_admin));
end$$;
-- Revoking cash viewing also protects previously saved deletion snapshots.
select set_config('test.cash.permissions',(select permissions::text from profiles where id='00000000-0000-0000-0000-000000003881'),true);
update profiles set permissions='{}'where id='00000000-0000-0000-0000-000000003881';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
do $$begin
 assert jsonb_array_length(public.solar_receipt_delete_requests('list',null,'{"status":""}')->'rows')=0;
 begin perform public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.expense')::bigint));raise exception 'FAIL cash permission revoked context';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('get',current_setting('test.cash.request')::uuid);raise exception 'FAIL cash permission revoked snapshot';exception when insufficient_privilege then null;end;
end$$;
reset role;
update profiles set permissions=current_setting('test.cash.permissions')::jsonb where id='00000000-0000-0000-0000-000000003881';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
do $$declare c jsonb;r jsonb;d jsonb;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.expense')::bigint));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',c->'id','expectedToken',c->>'token'));
 c:=public.solar_cash_record('get','tx:'||current_setting('test.cash.expense'));
 perform public.solar_cash_record('update','tx:'||current_setting('test.cash.expense'),gen_random_uuid(),jsonb_build_object('amount',600000,'note','مصروف مصحح','expectedToken',c->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
 d:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);assert(d->>'stale')::boolean;
 begin perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));raise exception 'FAIL changed cash approved';exception when sqlstate 'PT409'then null;end;
 perform public.solar_receipt_delete_requests('reject',(r->>'id')::uuid,'{}');
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
do $$declare before_cash numeric;approval_id uuid;c jsonb;f text;begin
 before_cash:=solar_private.cash_balance('00000000-0000-0000-0000-000000003881');
 approval_id:=pg_temp.approve_cash(current_setting('test.cash.expense')::bigint);
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003881')=before_cash+600000;
 assert not exists(select 1 from transactions where id=current_setting('test.cash.expense')::bigint);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
 c:=public.solar_receipt_delete_requests('get',approval_id);assert(c->'snapshot'->>'total')::numeric=600000;f:=pg_temp.financial_hash();
 perform public.solar_receipt_delete_requests('approve',approval_id,'{}');assert pg_temp.financial_hash()=f,'Repeated approval refunded twice';
end$$;
reset role;
do $$begin
 assert(select(invoice->>'total')::numeric from solar_private.deleted_sales where invoice_id=current_setting('test.cash.expense')::bigint)=600000;
 assert(select count(*)from solar_private.receipt_change_audit where transaction_id=current_setting('test.cash.expense')::bigint and action='cash_delete')=1;
end$$;
set local role authenticated;
select pg_temp.approve_cash(current_setting('test.cash.second')::bigint);
select pg_temp.approve_cash(current_setting('test.cash.profit')::bigint);
select pg_temp.approve_cash(current_setting('test.cash.capital')::bigint);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
do $$declare c jsonb;begin
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003881')=2000000;
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.usd')::bigint));
 assert c->>'blockedReason'is not null,'Consumed USD deposit could be deleted';
 begin perform public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',c->'id','expectedToken',c->>'token'));raise exception 'FAIL consumed USD request';exception when raise_exception then if sqlerrm='FAIL consumed USD request'then raise;end if;end;
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.cash.usdexpense')::bigint));
 assert(c->>'cashEffect')::numeric=40;assert(c->>'profitEffectIQD')::numeric=60000,'FX gain and operating cost not reversed together';
end$$;
reset role;
-- A downstream failure must restore the removed USD entry, archived receipt
-- and every cached/audited financial response in the same transaction.
create function pg_temp.fail_cash_deletion()returns trigger language plpgsql as $$begin if old.id=current_setting('test.cash.usdexpense')::bigint then raise exception 'forced_cash_deletion_failure';end if;return old;end$$;
create trigger test_cash_delete_failure before delete on public.transactions for each row execute function pg_temp.fail_cash_deletion();
set local role authenticated;
do $$declare f text:=pg_temp.financial_hash();begin
 begin perform pg_temp.approve_cash(current_setting('test.cash.usdexpense')::bigint);raise exception 'FAIL partial cash deletion';exception when raise_exception then if sqlerrm<>'forced_cash_deletion_failure'then raise;end if;end;
 assert pg_temp.financial_hash()=f,'Failed cash deletion leaked an archive, wallet removal or cached response';
end$$;
reset role;
drop trigger test_cash_delete_failure on public.transactions;
set local role authenticated;
select pg_temp.approve_cash(current_setting('test.cash.usdexpense')::bigint);
do $$begin
 assert(pg_temp.wallet('00000000-0000-0000-0000-000000003881')->>'amount')::numeric=100;
 assert(pg_temp.wallet('00000000-0000-0000-0000-000000003881')->>'book')::numeric=150000;
end$$;
select pg_temp.approve_cash(current_setting('test.cash.usd')::bigint);
do $$begin
 assert(pg_temp.wallet('00000000-0000-0000-0000-000000003881')->>'amount')::numeric=0;
 assert(pg_temp.wallet('00000000-0000-0000-0000-000000003881')->>'book')::numeric=0;
end$$;
-- Removing an IQD deposit can leave cash negative; incoming collections recover it.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003881',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003881","mode":"expense","currency":"IQD","amount":1500000,"note":"مصروف لاحق"}');
select pg_temp.approve_cash(current_setting('test.cash.deposit')::bigint);
do $$begin assert solar_private.cash_balance('00000000-0000-0000-0000-000000003881')=-1500000;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
do $$declare r jsonb;begin
 r:=public.solar_cash_save(current_setting('test.cash.nonce')::uuid,current_setting('test.cash.payload')::jsonb);
 assert(r->>'deleted')::boolean;assert not exists(select 1 from transactions where id=current_setting('test.cash.deposit')::bigint),'Creation replay restored deleted cash';
end$$;
-- An entirely supplier-allocated settlement is valid from its first approval.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003882',true);
do $$declare c jsonb;r jsonb;d jsonb;s jsonb;begin
 c:=public.solar_profit_workspace('overview');r:=public.solar_profit_workspace('request',gen_random_uuid(),jsonb_build_object('expectedToken',c->>'token'));perform set_config('test.zero.settlement',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003880',true);
 c:=public.solar_profit_workspace('overview');select value into d from jsonb_array_elements(c->'requests')where value->>'id'=r->>'id';select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-388001;
 begin perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',d->>'id','expectedToken',d->>'token','share',-1,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge'));raise exception 'FAIL negative approval';exception when raise_exception then if sqlerrm='FAIL negative approval'then raise;end if;end;
 r:=public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',d->>'id','expectedToken',d->>'token','share',0,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge','supplierId',-388001,'supplierToken',s->>'token','supplierRate',s->'rate'));
 assert(r->>'share')::numeric=0;assert(r->'receipt'->>'amount')::numeric=0;
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003882')=0;
 perform set_config('test.zero.expense',r->'receipt'->>'id',true);
end$$;
do $$declare c jsonb;s jsonb;r jsonb;b jsonb;n uuid:=gen_random_uuid();begin
 c:=public.solar_cash_record('get','profit:'||current_setting('test.zero.settlement'));assert(c->>'amount')::numeric=0;
 select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-388001;
 perform public.solar_cash_record('update','profit:'||current_setting('test.zero.settlement'),gen_random_uuid(),jsonb_build_object('amount',500000,'note','حصة مؤقتة','expectedToken',c->>'token','supplierId',-388001,'supplierToken',s->>'token'));
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003882')=-500000;
 c:=public.solar_cash_record('get','profit:'||current_setting('test.zero.settlement'));select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-388002;
 b:=jsonb_build_object('amount',0,'note','كل الربح للمورد','expectedToken',c->>'token','supplierId',-388002,'supplierToken',s->>'token');
 r:=public.solar_cash_record('update','profit:'||current_setting('test.zero.settlement'),n,b);assert public.solar_cash_record('update','profit:'||current_setting('test.zero.settlement'),n,b)=r;
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003882')=0;
 c:=public.solar_cash_record('get','profit:'||current_setting('test.zero.settlement'));assert(c->>'amount')::numeric=0;assert(c->>'supplierAmountIQD')::numeric=2000000;
 select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-388001;assert(s->>'balance')::numeric=0;
 select value into s from jsonb_array_elements(c->'suppliers')where(value->>'id')::bigint=-388002;assert(s->>'balance')::numeric=round(2000000/(s->>'rate')::numeric,2);
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',current_setting('test.zero.expense')::bigint));assert c->>'blockedReason'is not null,'Independent settlement expense deletion allowed';
end$$;
reset role;
do $$begin
 assert(select count(*)from transactions where profit_settlement_id=current_setting('test.zero.settlement')::uuid)=1;
 assert(select total from transactions where id=current_setting('test.zero.expense')::bigint)=0;
 assert(select count(*)from solar_private.profit_checkpoints where owner_id='00000000-0000-0000-0000-000000003882')=1;
 assert not has_function_privilege('authenticated','solar_private.cash_receipt_delete(bigint,uuid)','EXECUTE');
 assert not has_function_privilege('anon','public.solar_receipt_delete_requests(text,uuid,jsonb)','EXECUTE');
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003882',true);
do $$declare c jsonb;begin
 c:=public.solar_profit_workspace('overview');assert(c->>'available')::numeric=0,'Zero share reopened settled profit';
 begin perform public.solar_cash_record('update','profit:'||current_setting('test.zero.settlement'),gen_random_uuid(),'{"amount":0,"note":"غير مخول"}');raise exception 'FAIL staff zero-share edit';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003883',true);
do $$begin begin perform public.solar_receipt_delete_requests('list');raise exception 'FAIL warehouse';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003884',true);
do $$begin begin perform public.solar_receipt_delete_requests('list');raise exception 'FAIL installer';exception when insufficient_privilege then null;end;end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS cash deletion approval/rejection/replay, exact cash/profit/FX/capital reversal, current-receipt staleness, own-only scope/admin notices, negative IQD, deleted creation tombstone, zero initial/corrected settlement and supplier/checkpoint consistency
