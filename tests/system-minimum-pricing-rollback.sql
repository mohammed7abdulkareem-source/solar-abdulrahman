\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,is_admin,user_type,phone,permissions)values
('00000000-0000-0000-0000-000000003970','مدير حد الربح',true,'admin_staff','07700003970','{}'),
('00000000-0000-0000-0000-000000003971','بائع حد الربح',false,'admin_staff','07700003971','{"system":true,"sale":true,"purchase":true,"installations":true,"operationControl":true}'),
('00000000-0000-0000-0000-000000003972','مخزن حد الربح',true,'warehouse','07700003972','{}'),
('00000000-0000-0000-0000-000000003973','مهندس حد الربح',true,'installer','07700003973','{}');
insert into products(id,code,name,qty,cost)values(-397001,'MIN-01','مادة حد الربح',100,1000),(-397002,'MIN-02','مادة ثانية للربح',100,500),(-397003,'MIN-03','كلفة كسرية للربح',10,1000.005);
insert into customers(id,name,customer_type,owner_id)values(-397001,'زبون حد الربح','system','00000000-0000-0000-0000-000000003971'),(-397002,'زبون جملة مستقل','wholesale','00000000-0000-0000-0000-000000003971');
insert into solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)values('https://fcm.googleapis.com/fcm/send/local-system-pricing','00000000-0000-0000-0000-000000003971','local-key','local-auth');
create function pg_temp.system_invoice(total numeric,invoice_id bigint default null)returns jsonb language sql security definer set search_path=''as $$
 select jsonb_build_object('kind','system','mode','credit','party','زبون حد الربح','partyId',-397001,'installerId','00000000-0000-0000-0000-000000003973','customerAddress','عنوان الاختبار','total',total,'items','[{"id":-397001,"qty":1,"price":0}]'::jsonb)||case when invoice_id is null then'{}'::jsonb else jsonb_build_object('invoiceId',invoice_id,'expectedRevision',(select pricing_revision from public.transactions where id=invoice_id),'expectedInstallationRevision',(select installation_revision from public.transactions where id=invoice_id))end
$$;
create function pg_temp.pricing_fingerprint()returns text language sql security definer set search_path=''as $$
 select md5(jsonb_build_object('tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),'products',(select jsonb_agg(to_jsonb(t)order by id)from public.products t),'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),'entries',(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),'requests',(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_requests t))::text)
$$;
create function pg_temp.pricing_notices(heading text)returns bigint language sql security definer set search_path=''as $$select count(*)from public.solar_notifications where title=heading$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003971',true);
do $$declare r jsonb;begin
 if not(public.solar_operation_status()->>'systemFreePricing')::boolean then raise exception 'Existing behavior is not unrestricted by default';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(900));perform set_config('test.minimum.legacy',r->>'id',true);
 if r->>'systemMarkupPercent'is not null then raise exception 'Legacy free sale stamped with restriction';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(900));perform set_config('test.minimum.legacy_delete',r->>'id',true);
 begin perform public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','system_pricing','freePricing',false,'markupPercent',25,'expectedRevision',public.solar_operation_status()->'revision'));raise exception 'FAIL staff can change mandatory pricing';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003970',true);
select set_config('test.minimum.control_before',pg_temp.pricing_fingerprint(),true);
do $$declare s jsonb;r jsonb;payload jsonb;nonce uuid:=gen_random_uuid();n bigint;begin
 s:=public.solar_operation_status();payload:=jsonb_build_object('kind','system_pricing','freePricing',false,'markupPercent',25,'expectedRevision',s->'revision','note','تجربة محلية فقط');
 r:=public.solar_operation_control(nonce,payload);n:=pg_temp.pricing_notices('تفعيل حد ربح المنظومات 25%');
 if n<>(select count(*)from public.profiles where active)then raise exception 'All-user activation notification missing';end if;
 if public.solar_operation_control(nonce,payload)<>r or pg_temp.pricing_notices('تفعيل حد ربح المنظومات 25%')<>n then raise exception 'Activation replay duplicated notifications';end if;
 if(r->>'systemFreePricing')::boolean or(r->>'systemMarkupPercent')::int<>25 or(r->>'sale')::boolean or(r->>'system')::boolean or(r->>'purchase')::boolean then raise exception 'Mandatory pricing paused sales or wrong percentage';end if;
 begin perform public.solar_operation_control(gen_random_uuid(),payload);raise exception 'FAIL stale policy';exception when sqlstate'PT409'then null;end;
 begin perform public.solar_operation_control(gen_random_uuid(),payload||jsonb_build_object('markupPercent',15.5,'expectedRevision',r->'revision'));raise exception 'FAIL invalid percent';exception when raise_exception then if sqlerrm='FAIL invalid percent'then raise;end if;end;
 if pg_temp.pricing_fingerprint()<>current_setting('test.minimum.control_before')then raise exception 'Changing pricing policy mutated historic finance or stock';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003971',true);
select set_config('test.minimum.failed_before',pg_temp.pricing_fingerprint(),true);
do $$declare r jsonb;nonce uuid:=gen_random_uuid();begin
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1249.999));raise exception 'FAIL below 25 percent';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1000)||'{"cost":0,"profit":999999,"systemMarkupPercent":0}');raise exception 'FAIL forged client cost';exception when sqlstate'PT422'then null;end;
 if pg_temp.pricing_fingerprint()<>current_setting('test.minimum.failed_before')then raise exception 'Rejected system save left stock/customer/cash/request effects';end if;
 r:=public.solar_invoice_save(nonce,pg_temp.system_invoice(1250));perform set_config('test.minimum.bound',r->>'id',true);perform set_config('test.minimum.nonce',nonce::text,true);perform set_config('test.minimum.saved',r::text,true);
 if(r->>'cost')::numeric<>1000 or(r->>'profit')::numeric<>250 or(r->>'systemMarkupPercent')::int<>25 then raise exception 'Exactly 25 percent invalid %',r;end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1600));perform set_config('test.minimum.expenses',r->>'id',true);
 -- A profitable aggregate may include differently priced materials; the limit
 -- applies to the whole system, never to individual zero-priced components.
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1875)||'{"items":[{"id":-397001,"qty":1,"price":0},{"id":-397002,"qty":1,"price":0}]}');
 if(r->>'cost')::numeric<>1500 or(r->>'profit')::numeric<>375 then raise exception 'Aggregate markup wrong';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003970',true);
do $$declare r jsonb;id bigint:=current_setting('test.minimum.expenses')::bigint;before_hash text;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1600,id)||'{"approvedInstallationExpenses":280}');
 if(r->>'profit')::numeric<>320 then raise exception 'Approved expenses omitted from net profit';end if;
 before_hash:=pg_temp.pricing_fingerprint();
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1600,id)||'{"approvedInstallationExpenses":281}');raise exception 'FAIL expense broke total markup';exception when sqlstate'PT422'then null;end;
 if pg_temp.pricing_fingerprint()<>before_hash then raise exception 'Rejected expense left accounting differences';end if;
 -- Global 15% affects new sales and financial edits, preserving prior contracts.
 before_hash:=pg_temp.pricing_fingerprint();
 r:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','system_pricing','freePricing',false,'markupPercent',15,'expectedRevision',public.solar_operation_status()->'revision'));
 if pg_temp.pricing_fingerprint()<>before_hash then raise exception 'Percentage change rewrote existing agreements';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003971',true);
do $$declare r jsonb;id bigint:=current_setting('test.minimum.legacy')::bigint;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(900,id)||'{"notes":"تصحيح عنوان فقط دون تغيير السعر أو المواد"}');
 if(r->>'total')::numeric<>900 or r->>'systemMarkupPercent'is not null then raise exception 'Unrestricted historical agreement was repriced';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(900,id)||'{"items":[{"id":-397002,"qty":2,"price":0}]}');raise exception 'FAIL same-cost material edit bypassed minimum';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(950,id));raise exception 'FAIL edit below 15 percent';exception when sqlstate'PT422'then null;end;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1150,id));
 if(r->>'systemMarkupPercent')::int<>15 then raise exception 'Repricing did not adopt selected 15 percent';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1149.99));raise exception 'FAIL below 15 percent';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1150.01)||'{"items":[{"id":-397003,"qty":1,"price":0}]}');raise exception 'FAIL fractional minimum rounded down';exception when sqlstate'PT422'then null;end;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1150.02)||'{"items":[{"id":-397003,"qty":1,"price":0}]}');
 if(r->>'cost')::numeric<>1000.01 then raise exception 'Frozen fractional cost rounding changed';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","partyId":-397002,"party":"زبون جملة مستقل","mode":"credit","items":[{"id":-397001,"qty":1,"price":500}]}');
 if(r->>'total')::numeric<>500 then raise exception 'Wholesale acquired a system-only limit';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(1150));perform set_config('test.minimum.fifteen',r->>'id',true);
end$$;
-- An approved deletion must still remove a historical unrestricted agreement;
-- its temporary line removals never force a new price or bypass admin review.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003970',true);
do $$declare c jsonb;r jsonb;id bigint:=current_setting('test.minimum.legacy_delete')::bigint;begin
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',id));
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',id,'expectedToken',c->>'token'));
 c:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);
 perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',c->>'reviewToken'));
end$$;
reset role;
do $$begin if exists(select 1 from public.transactions where id=current_setting('test.minimum.legacy_delete')::bigint)then raise exception 'Minimum pricing blocked an approved historical deletion';end if;end$$;
set local role authenticated;
-- The same checks protect legacy row-level mutation paths at transaction end.
reset role;
set constraints all immediate;
do $$declare before_hash text:=pg_temp.pricing_fingerprint();begin
 begin update public.transactions set total=1,cost=0,profit=999999 where id=current_setting('test.minimum.bound')::bigint;raise exception 'FAIL legacy header bypass';exception when sqlstate'PT422'then null;end;
 begin update public.transaction_items set cost=2000 where transaction_id=current_setting('test.minimum.bound')::bigint;raise exception 'FAIL legacy line bypass';exception when sqlstate'PT422'then null;end;
 if pg_temp.pricing_fingerprint()<>before_hash then raise exception 'Rejected legacy changes survived';end if;
end$$;
set constraints all deferred;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003972',true);
do $$begin begin perform public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','system_pricing','freePricing',true,'markupPercent',15,'expectedRevision',public.solar_operation_status()->'revision'));raise exception 'FAIL warehouse control';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003970',true);
do $$declare s jsonb;r jsonb;before_hash text:=pg_temp.pricing_fingerprint();begin
 s:=public.solar_operation_control(gen_random_uuid(),jsonb_build_object('kind','system_pricing','freePricing',true,'markupPercent',15,'expectedRevision',public.solar_operation_status()->'revision'));
 if pg_temp.pricing_fingerprint()<>before_hash then raise exception 'Enabling free pricing mutated financial rows';end if;
 if not exists(select 1 from public.solar_notifications where title='تشغيل البيع الحر للمنظومات')then raise exception 'Free-pricing notification missing';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003971',true);
 r:=public.solar_invoice_save(current_setting('test.minimum.nonce')::uuid,pg_temp.system_invoice(1250));
 if r<>current_setting('test.minimum.saved')::jsonb then raise exception 'Already saved retry was repriced after a policy change';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.system_invoice(500));
 if(r->>'total')::numeric<>500 or r->>'systemMarkupPercent'is not null then raise exception 'Free pricing did not lift minimum';end if;
end$$;
reset role;
do $$begin
 if has_table_privilege('authenticated','solar_private.operation_controls','update')or has_function_privilege('authenticated','solar_private.system_pricing_control(uuid,jsonb)','execute')or has_function_privilege('authenticated','solar_private.assert_system_pricing(bigint)','execute')then raise exception 'Pricing internals exposed';end if;
 if not exists(select 1 from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.title='تفعيل حد ربح المنظومات 25%')then raise exception 'Policy push not queued';end if;
 raise notice 'PASS 15/25 total-cost minimum, higher price allowed, original frozen costs, full expense atomicity, safe legacy contracts, server/raw enforcement, replay, shared revisions, all-user notices and permissions';
end$$;
rollback;
