\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000411001','مدير نطاق الأسعار',true,'admin_staff','07700411001',true,'{}'),
('00000000-0000-0000-0000-000000411002','بائع مشمول',false,'admin_staff','07700411002',true,'{"sale":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000411003','بائع بصلاحية حرة',false,'admin_staff','07700411003',true,'{"sale":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000411004','مسؤول أسعار',false,'admin_staff','07700411004',true,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000411005','بائع خارج النطاق',false,'admin_staff','07700411005',true,'{"sale":true}'),
('00000000-0000-0000-0000-000000411006','مخزن بصلاحية قديمة',true,'warehouse','07700411006',true,'{"wholesalePricingManage":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000411007','مهندس بصلاحية قديمة',true,'installer','07700411007',true,'{"wholesalePricingManage":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000411008','حساب معطل',true,'admin_staff','07700411008',false,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000411009','حساب بلا بيع',false,'admin_staff','07700411009',true,'{}'),
('00000000-0000-0000-0000-000000411010','مدير أسعار بلا بيع',false,'admin_staff','07700411010',true,'{"wholesalePricingManage":true}');
insert into public.products(id,code,name,qty,cost)values(-411001,'SCOPE-A','مادة نطاق الأسعار',1000,100);
insert into public.customers(id,name,customer_type,owner_id)
select -411000-n,'عميل نطاق '||n,'wholesale',('00000000-0000-0000-0000-00000041100'||n)::uuid from generate_series(1,5)n;
create function pg_temp.scope_actor(n integer)returns void language sql as $$select set_config('request.jwt.claim.sub',('00000000-0000-0000-0000-'||lpad((411000+n)::text,12,'0')),true)::text::void$$;
create function pg_temp.scope_payload(price numeric,invoice_id bigint default null,quantity numeric default 1)returns jsonb language plpgsql security definer as $$
declare c public.customers;t public.transactions;begin
 if invoice_id is not null then select * into t from transactions where id=invoice_id;select * into c from customers where id=t.party_id;
 else select * into c from customers where owner_id=auth.uid()and id between -411005 and -411001 limit 1;end if;
 return jsonb_build_object('kind','sale','mode','credit','partyId',c.id,'party',c.name,'notes','نطاق الأسعار',
 'items',jsonb_build_array(jsonb_build_object('id',-411001,'qty',quantity,'price',price)),
 'wholesalePricingRevision',public.solar_wholesale_pricing('state')->'revision')||case when invoice_id is null then'{}'::jsonb else jsonb_build_object('invoiceId',t.id,'expectedRevision',t.pricing_revision,'warehouseId',t.warehouse_id)end;
end$$;
create function pg_temp.scope_hash()returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.products t),
 (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.profiles t))::text)$$;
create function pg_temp.scope_save(mode text,ids jsonb default'[]',nonce uuid default gen_random_uuid())returns jsonb language sql as $$
 select public.solar_wholesale_pricing('scope',nonce,jsonb_build_object('mode',mode,'userIds',ids,'expectedRevision',public.solar_wholesale_pricing('state')->'revision'))
$$;
create function pg_temp.scope_below_rejected(invoice_id bigint default null,quantity numeric default 1)returns void language plpgsql as $$
declare before_hash text:=pg_temp.scope_hash();begin
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(900,invoice_id,quantity));raise exception 'Underpriced invoice accepted';exception when sqlstate'PT422'then null;end;
 assert pg_temp.scope_hash()=before_hash,'Rejected save mutated financial/profile history';
end$$;

-- Legacy default retains admin/free permission until an explicit scope choice.
select pg_temp.scope_actor(1);
set local role authenticated;
do $$declare s jsonb;r jsonb;price jsonb;begin
 s:=public.solar_wholesale_pricing('state');assert not(s->>'scopeConfigured')::boolean and s->>'scopeMode'='all';
 assert(s->>'canOverride')::boolean and(s->>'legacyCanOverride')::boolean;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(900));perform set_config('test.scope.historical',r->>'id',true);
 select x into price from jsonb_array_elements(s->'products')x where(x->>'id')::bigint=-411001;
 perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(jsonb_build_object('productId',-411001,'minPrice',1000,'enabled',true,'expectedRevision',price->'revision'))));
 s:=public.solar_wholesale_pricing('state');perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',true,'expectedRevision',s->'revision'));
 perform pg_temp.scope_actor(3);s:=public.solar_wholesale_pricing('state');assert(s->>'canOverride')::boolean and not(s->>'effectiveEnforced')::boolean;
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(900));
 perform pg_temp.scope_actor(2);perform pg_temp.scope_below_rejected();
end$$;
reset role;

-- Explicit selection prevails over old free/admin flags without rewriting any
-- profile permission or historical accounting row. A true retry emits nothing.
select pg_temp.scope_actor(4);
set local role authenticated;
do $$declare s jsonb;r jsonb;body jsonb;nonce uuid:=gen_random_uuid();h text:=pg_temp.scope_hash();begin
 s:=public.solar_wholesale_pricing('state');
 assert exists(select 1 from jsonb_array_elements(s->'eligibleUsers')u where u->>'id'='00000000-0000-0000-0000-000000411001');
 assert not exists(select 1 from jsonb_array_elements(s->'eligibleUsers')u where u->>'id' in('00000000-0000-0000-0000-000000411006','00000000-0000-0000-0000-000000411007','00000000-0000-0000-0000-000000411008','00000000-0000-0000-0000-000000411009','00000000-0000-0000-0000-000000411010'));
 assert not exists(select 1 from jsonb_array_elements(s->'eligibleUsers')u where u?'permissions'or u?'phone'or u?'email'or u?'balance');
 body:=jsonb_build_object('mode','selected','userIds','["00000000-0000-0000-0000-000000411001","00000000-0000-0000-0000-000000411002","00000000-0000-0000-0000-000000411003"]'::jsonb,'expectedRevision',s->'revision');
 r:=public.solar_wholesale_pricing('scope',nonce,body);assert(r->>'scopeConfigured')::boolean and r->>'scopeMode'='selected';
 assert(r->>'changedCount')::integer=1 and(r->>'notifiedCount')::integer>0;
 assert public.solar_wholesale_pricing('scope',nonce,body)=r,'Same scope retry response differs';
 perform set_config('test.scope.request',nonce::text,true);perform set_config('test.scope.requestBody',body::text,true);
 assert pg_temp.scope_hash()=h,'Scope changed financial rows or general permissions';
 begin perform public.solar_wholesale_pricing('scope',nonce,body||'{"mode":"all","userIds":[]}');raise exception 'Changed idempotency payload accepted';exception when sqlstate'PT409'then null;end;
 perform pg_temp.scope_actor(1);s:=public.solar_wholesale_pricing('state');assert(s->>'effectiveEnforced')::boolean and not(s->>'canOverride')::boolean and(s->>'legacyCanOverride')::boolean;perform pg_temp.scope_below_rejected();
 perform pg_temp.scope_actor(3);s:=public.solar_wholesale_pricing('state');assert(s->>'effectiveEnforced')::boolean and not(s->>'canOverride')::boolean;perform pg_temp.scope_below_rejected();
 perform pg_temp.scope_actor(5);s:=public.solar_wholesale_pricing('state');assert not(s->>'effectiveEnforced')::boolean and s->>'reason'='outside_scope';
 assert not(s?'eligibleUsers')and not(s?'selectedUserIds'),'Seller received user roster';
 perform public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(900));
end$$;
reset role;
do $$begin
 assert(select count(*)from solar_private.wholesale_pricing_audit where request_id=current_setting('test.scope.request')::uuid)=1;
 assert(select count(*)from solar_private.finance_requests where request_id=current_setting('test.scope.request')::uuid)=1;
 assert exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000411003'and title='تحديث نطاق أسعار بيع الجملة'and body like'%مشمول%');
 assert exists(select 1 from solar_notifications where user_id='00000000-0000-0000-0000-000000411005'and title='تحديث نطاق أسعار بيع الجملة'and body like'%غير مشمول%');
end$$;

-- Target-aware previews and saves use the OWNER, even when an unselected
-- administrator edits the selected owner's invoice. Historical prices survive
-- notes-only saves but changed economics use today's scope/floors.
select pg_temp.scope_actor(2);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(1000));perform set_config('test.scope.target',r->>'id',true);
end$$;
reset role;
select pg_temp.scope_actor(4);
select pg_temp.scope_save('selected','["00000000-0000-0000-0000-000000411002","00000000-0000-0000-0000-000000411003"]');
set local role authenticated;
do $$declare s jsonb;r jsonb;begin
 perform pg_temp.scope_actor(1);s:=public.solar_wholesale_pricing('state');assert not(s->>'effectiveEnforced')::boolean;
 s:=public.solar_wholesale_pricing('state',null,jsonb_build_object('invoiceId',current_setting('test.scope.target')::bigint));
 assert(s->>'effectiveEnforced')::boolean and not(s->>'appliesToCurrentUser')::boolean and(s->>'appliesToSubject')::boolean;
 assert s->>'pricingSubjectId'='00000000-0000-0000-0000-000000411002';perform pg_temp.scope_below_rejected(current_setting('test.scope.target')::bigint);
 perform pg_temp.scope_actor(5);
 begin perform public.solar_wholesale_pricing('state',null,jsonb_build_object('invoiceId',current_setting('test.scope.target')::bigint));raise exception 'Foreign invoice scope leaked';exception when insufficient_privilege then null;end;
 perform pg_temp.scope_actor(4);perform pg_temp.scope_save('all');
 perform pg_temp.scope_actor(1);r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.scope_payload(900,current_setting('test.scope.historical')::bigint)||'{"notes":"ملاحظة فقط"}');
 assert(r->>'total')::numeric=900;perform pg_temp.scope_below_rejected(current_setting('test.scope.historical')::bigint,2);
end$$;
reset role;

-- Scope changes stale a new financial write, not a successful cached attempt.
set local role authenticated;
do $$declare body jsonb;s jsonb;nonce uuid:=gen_random_uuid();r jsonb;begin
 perform pg_temp.scope_actor(2);body:=pg_temp.scope_payload(1000);r:=public.solar_invoice_save(nonce,body);
 perform pg_temp.scope_actor(4);perform pg_temp.scope_save('selected','["00000000-0000-0000-0000-000000411002"]');
 perform pg_temp.scope_actor(2);
 begin perform public.solar_invoice_save(gen_random_uuid(),body);raise exception 'Stale scope revision accepted';exception when sqlstate'PT409'then null;end;
 assert public.solar_invoice_save(nonce,body)=r,'Previously confirmed invoice retry changed';
end$$;
reset role;

-- Raw/trusted warehouse amendments cannot use the editor's out-of-scope status
-- to bypass the selected owner's minimum. Existing owner reassignment is closed
-- only after explicit configuration; initial authorized on-behalf saves survive.
update public.transactions set fx_pricing=false where id=current_setting('test.scope.target')::bigint;
select pg_temp.scope_actor(1);
set local role authenticated;
do $$declare h text:=pg_temp.scope_hash();begin
 begin update public.transactions set created_by='00000000-0000-0000-0000-000000411005',cashbox_user_id='00000000-0000-0000-0000-000000411005'where id=current_setting('test.scope.target')::bigint;raise exception 'Admin forged unselected owner';exception when insufficient_privilege then null;end;
 assert pg_temp.scope_hash()=h;
end$$;
reset role;
select pg_temp.scope_actor(6);
do $$declare h text:=pg_temp.scope_hash();begin
 begin
  update public.transaction_items set price=900 where transaction_id=current_setting('test.scope.target')::bigint;
  set constraints solar_wholesale_item_pricing_check immediate;
  raise exception 'Warehouse bypassed selected owner';
 exception when sqlstate'PT422'then null;end;
 assert pg_temp.scope_hash()=h;
end$$;
select pg_temp.scope_actor(1);
-- Existing trusted on-behalf writer; authenticated legacy INSERT already has
-- separate baseline invoice-account guards, unrelated to scope selection.
insert into public.transactions(id,kind,party_id,party_name,created_by,cashbox_user_id,subtotal,total,profit,payment_mode)
 values(-411090,'sale',-411005,'عميل نطاق 5','00000000-0000-0000-0000-000000411005','00000000-0000-0000-0000-000000411005',0,0,0,'credit');
reset role;

-- Pending price/toggle retries acknowledge their old save but return CURRENT
-- protected scope/catalog, so another manager's intervening choice is visible.
select pg_temp.scope_actor(4);
set local role authenticated;
do $$declare p jsonb;s jsonb;price_body jsonb;toggle_body jsonb;price_nonce uuid:=gen_random_uuid();toggle_nonce uuid:=gen_random_uuid();scope_body jsonb;scope_nonce uuid:=gen_random_uuid();first jsonb;current_state jsonb;begin
 s:=public.solar_wholesale_pricing('state');select x into p from jsonb_array_elements(s->'products')x where(x->>'id')::bigint=-411001;
 price_body:=jsonb_build_object('items',jsonb_build_array(jsonb_build_object('productId',-411001,'minPrice',1100,'enabled',true,'expectedRevision',p->'revision')));
 first:=public.solar_wholesale_pricing('save',price_nonce,price_body);
 assert public.solar_wholesale_pricing('save',price_nonce,price_body)=first,'Unchanged price retry differs';
 toggle_body:=jsonb_build_object('enabled',false,'expectedRevision',first->'revision');first:=public.solar_wholesale_pricing('toggle',toggle_nonce,toggle_body);
 assert public.solar_wholesale_pricing('toggle',toggle_nonce,toggle_body)=first,'Unchanged toggle retry differs';
 scope_body:=jsonb_build_object('mode','selected','userIds','["00000000-0000-0000-0000-000000411003"]'::jsonb,'expectedRevision',first->'revision');
 first:=public.solar_wholesale_pricing('scope',scope_nonce,scope_body);
 current_state:=public.solar_wholesale_pricing('state');
 s:=public.solar_wholesale_pricing('save',price_nonce,price_body);assert s->'selectedUserIds'=current_state->'selectedUserIds'and s->'revision'=current_state->'revision';
 s:=public.solar_wholesale_pricing('toggle',toggle_nonce,toggle_body);assert s->'selectedUserIds'=current_state->'selectedUserIds'and s->'revision'=current_state->'revision';
 s:=pg_temp.scope_save('selected','["00000000-0000-0000-0000-000000411003"]');assert(s->>'changedCount')::integer=0 and(s->>'notifiedCount')::integer=0;
 assert s->'revision'=current_state->'revision','No-op scope increments revision';
 s:=pg_temp.scope_save('all');
 first:=public.solar_wholesale_pricing('scope',scope_nonce,scope_body);assert first->>'scopeMode'='all'and first->'revision'=s->'revision','Late scope retry restored obsolete selection';
 begin perform public.solar_wholesale_pricing('scope',gen_random_uuid(),scope_body);raise exception 'Stale scope change accepted';exception when sqlstate'PT409'then null;end;
 perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',true,'expectedRevision',s->'revision'));
end$$;
reset role;

-- Invalid targets, unprivileged actors and stale scope revisions fail atomically.
set local role authenticated;
do $$declare n integer;candidate text;body jsonb;s jsonb;h text;begin
 perform pg_temp.scope_actor(4);s:=public.solar_wholesale_pricing('state');h:=pg_temp.scope_hash();
 foreach candidate in array array['00000000-0000-0000-0000-000000411006','00000000-0000-0000-0000-000000411007','00000000-0000-0000-0000-000000411008','00000000-0000-0000-0000-000000411009','00000000-0000-0000-0000-000000411010','00000000-0000-0000-0000-000000999999']loop
  begin perform pg_temp.scope_save('selected',jsonb_build_array(candidate));raise exception 'Invalid scope user accepted';exception when sqlstate'PT409'then null;end;
 end loop;
 begin perform pg_temp.scope_save('selected','[]');raise exception 'Empty selected scope accepted';exception when invalid_parameter_value then null;end;
 begin perform pg_temp.scope_save('selected','["00000000-0000-0000-0000-000000411002","00000000-0000-0000-0000-000000411002"]');raise exception 'Duplicate scope user accepted';exception when invalid_parameter_value then null;end;
 begin perform public.solar_wholesale_pricing('scope',gen_random_uuid(),jsonb_build_object('mode','all','userIds','[]'::jsonb,'expectedRevision',-1));raise exception 'Invalid revision';exception when invalid_parameter_value then null;end;
 for n in select x from unnest(array[2,5,6,7,8,9])x loop
  perform pg_temp.scope_actor(n);
  begin perform public.solar_wholesale_pricing('scope',gen_random_uuid(),jsonb_build_object('mode','all','userIds','[]'::jsonb,'expectedRevision',s->'revision'));raise exception 'Scope management permission bypass';exception when insufficient_privilege then null;end;
 end loop;
 assert pg_temp.scope_hash()=h;
 begin insert into solar_private.wholesale_pricing_users(user_id)values('00000000-0000-0000-0000-000000411005');raise exception 'Direct scope write';exception when insufficient_privilege then null;end;
 begin perform solar_private.wholesale_scope_effective('00000000-0000-0000-0000-000000411002',auth.uid());raise exception 'Private helper exposed';exception when insufficient_privilege then null;end;
end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS explicit per-user pricing authority, legacy default, selected admin/free binding, owner-context privacy, historical signatures, stale/replay, no permission/financial mutations and protected scope metadata
