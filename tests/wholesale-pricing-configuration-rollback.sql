\set ON_ERROR_STOP on
-- Actual pg-safeupdate must be installed in the isolated PostgreSQL container.
-- Loading per connection reproduces the production authenticator session guard.
load 'safeupdate';
begin;
create temp table safeupdate_probe(id integer);
insert into safeupdate_probe values(1);
do $$begin
 begin delete from safeupdate_probe;raise exception 'Safeupdate was not active';
 exception when others then
  if sqlerrm not like '%DELETE requires a WHERE clause%'then raise;end if;
 end;
 assert(select count(*)=1 from safeupdate_probe),'Safeupdate probe mutated data';
end$$;
insert into public.profiles(id,display_name,is_admin,user_type,active,permissions)values
('00000000-0000-0000-0000-000000412001','مدير إعدادات الأسعار',true,'admin_staff',true,'{}'),
('00000000-0000-0000-0000-000000412002','بائع أول',false,'admin_staff',true,'{"sale":true}'),
('00000000-0000-0000-0000-000000412003','بائع حر سابقًا',false,'admin_staff',true,'{"sale":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000412004','مسؤول إعدادات الأسعار',false,'admin_staff',true,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000412005','موظف مخزن',true,'warehouse',true,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000412006','مستخدم معطل',true,'admin_staff',false,'{"sale":true}');
create function pg_temp.config_actor(n integer)returns void language sql as $$select set_config('request.jwt.claim.sub',('00000000-0000-0000-0000-'||lpad((412000+n)::text,12,'0')),true)::text::void$$;
create function pg_temp.config_payload(enabled boolean,mode text,ids jsonb default'[]')returns jsonb language sql as $$
 select jsonb_build_object('enabled',enabled,'mode',mode,'userIds',ids,'expectedRevision',public.solar_wholesale_pricing('state')->'revision')
$$;
create function pg_temp.config_snapshot()returns jsonb language sql security definer as $$select jsonb_build_object(
 'control',(select to_jsonb(c)from solar_private.wholesale_pricing_control c where id),
 'members',(select jsonb_agg(to_jsonb(u)order by user_id)from solar_private.wholesale_pricing_users u),
 'audit',(select count(*)from solar_private.wholesale_pricing_audit),
 'notices',(select count(*)from public.solar_notifications),
 'push',(select count(*)from solar_private.push_deliveries),
 'requests',(select count(*)from solar_private.finance_requests))$$;
create function pg_temp.config_finances()returns text language sql security definer as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.products t),
 (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.profiles t))::text)$$;
create function pg_temp.config_recipients()returns integer language sql security definer as $$select count(*)::integer from public.profiles p
 where p.active and p.user_type not in('warehouse','installer')and(p.is_admin or p.permissions->>'sale'='true'or p.permissions->>'wholesalePricingManage'='true')$$;
create function pg_temp.config_reject(action text,nonce uuid,body jsonb,expected_code text)returns void language plpgsql as $$
declare snapshot jsonb:=pg_temp.config_snapshot();begin
 begin perform public.solar_wholesale_pricing(action,nonce,body);raise exception 'Invalid configuration accepted';
 exception when others then if sqlstate<>expected_code then raise;end if;end;
 assert snapshot=pg_temp.config_snapshot(),'Rejected request changed state, audit, notices or nonce';
end$$;
select pg_temp.config_actor(1);
set local role authenticated;
do $$declare before_value jsonb;after_value jsonb;r jsonb;body jsonb;nonce uuid:=gen_random_uuid();financial_hash text:=pg_temp.config_finances();begin
 before_value:=pg_temp.config_snapshot();
 assert not(before_value->'control'->>'scope_configured')::boolean,'Use a clean isolated V4.1 fixture';
 body:=pg_temp.config_payload(true,'selected','["00000000-0000-0000-0000-000000412001","00000000-0000-0000-0000-000000412002","00000000-0000-0000-0000-000000412003"]');
 r:=public.solar_wholesale_pricing('configure',nonce,body);after_value:=pg_temp.config_snapshot();
 assert(r->>'enabled')::boolean and(r->>'scopeConfigured')::boolean and r->>'scopeMode'='selected';
 assert(r->>'effectiveEnforced')::boolean and not(r->>'canOverride')::boolean,'Selected admin bypassed explicit configuration';
 assert(r->>'revision')::bigint=(before_value->'control'->>'revision')::bigint+1,'Combined save must increment once';
 assert(after_value->>'audit')::bigint=(before_value->>'audit')::bigint+1,'Combined save must audit once';
 assert(after_value->>'requests')::bigint=(before_value->>'requests')::bigint+1;
 assert(after_value->>'notices')::bigint=(before_value->>'notices')::bigint+pg_temp.config_recipients(),'Combined save emitted duplicate/missing notices';
 assert(r->>'changedCount')::integer=1 and(r->>'notifiedCount')::integer=pg_temp.config_recipients();
 assert public.solar_wholesale_pricing('configure',nonce,body)=r,'Same request should return identical current state';
 assert after_value=pg_temp.config_snapshot(),'Retry duplicated writes';
 perform pg_temp.config_reject('configure',nonce,body||'{"enabled":false}', 'PT409');
 perform pg_temp.config_reject('scope',nonce,body-'enabled','PT409');
 perform set_config('test.config.firstNonce',nonce::text,true);perform set_config('test.config.firstPayload',body::text,true);
 assert financial_hash=pg_temp.config_finances(),'Configuration changed financial data or general permissions';
 perform set_config('test.config.financialHash',financial_hash,true);
 -- An identical desired configuration under a new request is a true no-op.
 before_value:=pg_temp.config_snapshot();r:=public.solar_wholesale_pricing('configure',gen_random_uuid(),pg_temp.config_payload(true,'selected',body->'userIds'));
 after_value:=pg_temp.config_snapshot();assert r->>'changedCount'='0'and r->>'notifiedCount'='0';
 assert before_value-'requests'=after_value-'requests','No-op changed anything besides its idempotency acknowledgement';
end$$;
reset role;
-- Verify one final-state notice per recipient, no intermediate toggle messages.
do $$begin
 assert not exists(select 1 from solar_notifications where user_id between '00000000-0000-0000-0000-000000412001'and'00000000-0000-0000-0000-000000412006'and title<>'تحديث إعدادات أسعار بيع الجملة');
 assert(select count(*)=1 from solar_notifications where user_id='00000000-0000-0000-0000-000000412003'and body like '%حسابك مشمول%');
 assert(select count(*)=1 from solar_notifications where user_id='00000000-0000-0000-0000-000000412004'and body like '%غير مشمول%');
 assert not exists(select 1 from solar_notifications where user_id in('00000000-0000-0000-0000-000000412005','00000000-0000-0000-0000-000000412006'));
end$$;
update solar_private.wholesale_pricing_users set selected_at='2001-01-01',selected_by='00000000-0000-0000-0000-000000412004'where user_id='00000000-0000-0000-0000-000000412002';
select pg_temp.config_actor(4);
set local role authenticated;
do $$declare r jsonb;s jsonb;body jsonb;nonce uuid:=gen_random_uuid();before_value jsonb;begin
 -- Remove only obsolete IDs; kept member metadata must survive, new ID inserts.
 r:=public.solar_wholesale_pricing('configure',nonce,pg_temp.config_payload(false,'selected','["00000000-0000-0000-0000-000000412002","00000000-0000-0000-0000-000000412004"]'));
 assert not(r->>'enabled')::boolean and r->'selectedUserIds'='["00000000-0000-0000-0000-000000412002","00000000-0000-0000-0000-000000412004"]';
 before_value:=pg_temp.config_snapshot();
 assert exists(select 1 from jsonb_array_elements(before_value->'members')m where m->>'user_id'='00000000-0000-0000-0000-000000412002'and(m->>'selected_at')::timestamptz='2001-01-01'and m->>'selected_by'='00000000-0000-0000-0000-000000412004'),'Kept membership metadata was replaced';
 assert jsonb_array_length(before_value->'members')=2;
 -- Legacy scope changes still work with safeupdate and keep the off state.
 body:=jsonb_build_object('mode','selected','userIds','["00000000-0000-0000-0000-000000412002"]'::jsonb,'expectedRevision',r->'revision');nonce:=gen_random_uuid();
 r:=public.solar_wholesale_pricing('scope',nonce,body);assert not(r->>'enabled')::boolean;
 perform set_config('test.config.scopeNonce',nonce::text,true);perform set_config('test.config.scopePayload',body::text,true);
 -- Legacy toggle still changes only enabled and remains retryable.
 body:=jsonb_build_object('enabled',true,'expectedRevision',r->'revision');nonce:=gen_random_uuid();
 r:=public.solar_wholesale_pricing('toggle',nonce,body);assert(r->>'enabled')::boolean and r->'selectedUserIds'='["00000000-0000-0000-0000-000000412002"]';
 perform set_config('test.config.toggleNonce',nonce::text,true);perform set_config('test.config.togglePayload',body::text,true);
 -- Saving an empty selected draft while disabled is valid; enabling it is not.
 r:=public.solar_wholesale_pricing('configure',gen_random_uuid(),pg_temp.config_payload(false,'selected'));
 assert not(r->>'enabled')::boolean and r->'selectedUserIds'='[]';
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'selected'),'22023');
 perform pg_temp.config_reject('toggle',gen_random_uuid(),jsonb_build_object('enabled',true,'expectedRevision',r->'revision'),'22023');
 perform pg_temp.config_reject('scope',gen_random_uuid(),pg_temp.config_payload(false,'selected')-'enabled','22023');
 -- Recover all older uncertain actions against CURRENT protected state.
 before_value:=pg_temp.config_snapshot();
 s:=public.solar_wholesale_pricing('scope',current_setting('test.config.scopeNonce')::uuid,current_setting('test.config.scopePayload')::jsonb);
 assert not(s->>'enabled')::boolean and s->'selectedUserIds'='[]'and s->'revision'=r->'revision';
 s:=public.solar_wholesale_pricing('toggle',current_setting('test.config.toggleNonce')::uuid,current_setting('test.config.togglePayload')::jsonb);
 assert not(s->>'enabled')::boolean and s->'revision'=r->'revision';
 perform pg_temp.config_actor(1);
 s:=public.solar_wholesale_pricing('configure',current_setting('test.config.firstNonce')::uuid,current_setting('test.config.firstPayload')::jsonb);
 assert not(s->>'enabled')::boolean and s->'selectedUserIds'='[]'and s->'revision'=r->'revision';
 assert before_value=pg_temp.config_snapshot(),'Recovery of old writes changed final state';
 -- All mode applies to users created after this save too.
 r:=public.solar_wholesale_pricing('configure',gen_random_uuid(),pg_temp.config_payload(true,'all'));assert r->>'scopeMode'='all'and(r->>'enabled')::boolean;
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(false,'all')||jsonb_build_object('expectedRevision',(r->>'revision')::bigint-1),'PT409');
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'all')||'{"enabled":"true"}','22023');
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'all')-'enabled','22023');
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'selected','["00000000-0000-0000-0000-000000412005"]'),'PT409');
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'selected','["00000000-0000-0000-0000-000000412006"]'),'PT409');
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(true,'selected','["00000000-0000-0000-0000-000000412002","00000000-0000-0000-0000-000000412002"]'),'22023');
 assert current_setting('test.config.financialHash')=pg_temp.config_finances(),'Settings rewrote financial rows or permissions';
end$$;
reset role;
insert into public.profiles(id,display_name,user_type,active,permissions)values('00000000-0000-0000-0000-000000412007','بائع أضيف لاحقًا','admin_staff',true,'{"sale":true,"wholesaleFreePricing":true}');
select pg_temp.config_actor(7);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_wholesale_pricing('state');assert(r->>'effectiveEnforced')::boolean and not(r->>'canOverride')::boolean,'All omitted a future free-permission seller';
 assert not(r?'eligibleUsers')and not(r?'selectedUserIds'),'Ordinary user received scope roster';
 perform pg_temp.config_reject('configure',gen_random_uuid(),pg_temp.config_payload(false,'all'),'42501');
 perform pg_temp.config_actor(5);perform pg_temp.config_reject('configure',gen_random_uuid(),'{"enabled":false,"mode":"all","userIds":[],"expectedRevision":0}','42501');
 perform pg_temp.config_actor(6);perform pg_temp.config_reject('configure',gen_random_uuid(),'{"enabled":false,"mode":"all","userIds":[],"expectedRevision":0}','42501');
end$$;
reset role;
-- Safeupdate is still active after every success/failure/replay.
do $$begin
 begin delete from safeupdate_probe;raise exception 'Safeupdate disabled by configuration';
 exception when others then if sqlerrm not like '%DELETE requires a WHERE clause%'then raise;end if;end;
end$$;
set constraints all immediate;
rollback;
\echo PASS atomic wholesale configuration with real safeupdate, retained membership metadata, legacy recovery and no financial mutation
