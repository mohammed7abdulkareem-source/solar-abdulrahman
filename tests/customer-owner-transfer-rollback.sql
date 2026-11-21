-- All records belong to this isolated test transaction.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,username,is_admin,user_type,active,permissions) values
 ('00000000-0000-0000-0000-000000418801','Transfer admin','transfer.admin',true,'admin_staff',true,'{}'),
 ('00000000-0000-0000-0000-000000418802','Transfer duplicate','transfer.source',false,'admin_staff',true,'{"customers":true,"customerStatement":true,"customerReconcile":true}'),
 ('00000000-0000-0000-0000-000000418803','Transfer duplicate','transfer.target',false,'admin_staff',true,'{"customers":true,"customerStatement":true}'),
 ('00000000-0000-0000-0000-000000418804','Transfer warehouse','transfer.wh',true,'warehouse',true,'{}'),
 ('00000000-0000-0000-0000-000000418805','Transfer engineer','transfer.installer',true,'installer',true,'{}'),
 ('00000000-0000-0000-0000-000000418806','Transfer inactive','transfer.inactive',false,'admin_staff',false,'{}');
create temp table attempts(action text primary key, request_id uuid not null default gen_random_uuid(), data jsonb not null);
grant select,insert on attempts to authenticated;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418802',true);
insert into attempts(action,data) values('create','{"id":-418801,"name":"عميل اختبار التحويل","customerType":"wholesale","phone":"07700418801","openingBalance":500}');
select public.solar_customer_save(action,request_id,data)->>'id' from attempts where action='create';
insert into attempts(action,data)
 select 'update',jsonb_build_object('id',-418801,'name',r->>'name','phone',r->>'phone','customerType','wholesale','token',r->>'token')
 from (select public.solar_customer_get(-418801) r) current_record;
do $$begin
 assert (select (public.solar_customer_save(action,request_id,data)->>'openingBalance')::numeric=500 from attempts where action='update'),
  'Omitted opening changed the account on ordinary edit';
end $$;
reset role;
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,notes) values
 (-418801,'sale',-418801,'عميل اختبار التحويل',300,false,'credit','00000000-0000-0000-0000-000000418802','00000000-0000-0000-0000-000000418802','fixture private source'),
 (-418802,'customer_payment',null,'عميل اختبار التحويل',100,true,'payment','00000000-0000-0000-0000-000000418801','00000000-0000-0000-0000-000000418801','fixture private admin');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418802',true);
insert into attempts(action,data)
 select 'customer_balance',jsonb_build_object('customerId',-418801,'actual',750,'token',r->>'token','note','fixture')
 from (select public.solar_customer_statement(-418801) r) current_record;
select public.solar_reconcile(action,request_id,data)->>'customerId' from attempts where action='customer_balance';
do $$declare payload jsonb:=jsonb_build_object('id',-418801,'ownerId','00000000-0000-0000-0000-000000418803','token',public.solar_customer_get(-418801)->>'token');begin
 begin perform public.solar_customer_transfer_targets();raise exception 'User saw target list';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),payload);raise exception 'User transferred own customer';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_save('update',gen_random_uuid(),payload||'{"customerType":"wholesale","name":"تعديل"}');raise exception 'Ordinary update changed owner';exception when insufficient_privilege then null;end;
 begin update public.customers set owner_id='00000000-0000-0000-0000-000000418803' where id=-418801;raise exception 'Direct staff transfer succeeded';exception when insufficient_privilege then null;end;
end $$;
reset role;
create temp table original_customer as select to_jsonb(c) customer from public.customers c where id=-418801;
create temp table original_rows as select solar_private.customer_ledger(-418801) ledger;
create temp table original_financial as
 select t.id,to_jsonb(t) original from public.transactions t join solar_private.customer_movement_links() l on l.transaction_id=t.id where l.customer_id=-418801;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418801',true);
insert into attempts(action,data)
 select 'transfer_owner',jsonb_build_object('id',-418801,'ownerId','00000000-0000-0000-0000-000000418803','token',r->>'token')
 from (select public.solar_customer_get(-418801) r) current_record;
do $$declare listing jsonb:=public.solar_customer_transfer_targets();candidate jsonb;payload jsonb;req uuid;response jsonb;begin
 assert (select count(*) from jsonb_array_elements(listing) v where (v->>'id') in ('00000000-0000-0000-0000-000000418801','00000000-0000-0000-0000-000000418802','00000000-0000-0000-0000-000000418803'))=3,'Eligible users missing';
 assert not exists(select 1 from jsonb_array_elements(listing) v where v->>'id' in ('00000000-0000-0000-0000-000000418804','00000000-0000-0000-0000-000000418805','00000000-0000-0000-0000-000000418806')),'Invalid transfer target listed';
 assert exists(select 1 from jsonb_array_elements(listing) v where v->>'id'='00000000-0000-0000-0000-000000418803' and v->>'name' like '%@transfer.target'),'Duplicate label ambiguous';
 select data,request_id into payload,req from attempts where action='transfer_owner';
 foreach candidate in array array['"00000000-0000-0000-0000-000000418802"'::jsonb,'"00000000-0000-0000-0000-000000418804"'::jsonb,'"00000000-0000-0000-0000-000000418805"'::jsonb,'"00000000-0000-0000-0000-000000418806"'::jsonb,'"00000000-0000-0000-0000-000000418807"'::jsonb,'null'::jsonb] loop
  begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),jsonb_set(payload,'{ownerId}',candidate));raise exception 'Invalid destination accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin update public.customers set owner_id='00000000-0000-0000-0000-000000418803' where id=-418801;raise exception 'Unaudited direct admin transfer';exception when insufficient_privilege then null;end;
 response:=public.solar_customer_save('transfer_owner',req,payload);
 assert response->>'id'='-418801' and response->>'ownerId'='00000000-0000-0000-0000-000000418803' and response->>'name'='عميل اختبار التحويل';
 assert public.solar_customer_save('transfer_owner',req,payload)=response,'Retry changed transfer';
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),payload);raise exception 'Stale token accepted';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_customer_save('transfer_owner',req,payload||'{"ownerId":"00000000-0000-0000-0000-000000418801"}');raise exception 'Reused request with mismatched target';exception when sqlstate 'PT409' then null;end;
end $$;
reset role;
do $$declare before_record jsonb:=(select customer from original_customer);after_record jsonb:=(select to_jsonb(c) from public.customers c where id=-418801);begin
 assert (after_record->>'customer_revision')::bigint=(before_record->>'customer_revision')::bigint+1;
 assert after_record-array['owner_id','customer_revision']=before_record-array['owner_id','customer_revision'],'Customer identity or opening changed';
 assert solar_private.customer_ledger(-418801)=(select ledger from original_rows),'Ledger changed';
 assert not exists(select 1 from original_financial o left join public.transactions t on t.id=o.id where to_jsonb(t) is distinct from o.original),'Financial snapshot, author, numbers or cashbox changed';
 assert (select count(*) from solar_private.customer_changes where action='transfer_owner' and customer_id=-418801)=1;
 assert exists(select 1 from solar_private.customer_changes where action='transfer_owner' and customer_id=-418801 and actor_id='00000000-0000-0000-0000-000000418801'
  and before_customer->>'ownerId'='00000000-0000-0000-0000-000000418802' and after_customer->>'ownerId'='00000000-0000-0000-0000-000000418803'
  and before_opening=500 and after_opening=500),'Audit missing ownership transition';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418802',true);
do $$declare a record;begin
 begin perform public.solar_customer_statement(-418801);raise exception 'Former owner can read statement';exception when insufficient_privilege then null;end;
 assert not exists(select 1 from public.customers where id=-418801),'Former owner sees raw customer';
 for a in select * from attempts where action in ('create','update') loop
  begin perform public.solar_customer_save(a.action,a.request_id,a.data);raise exception 'Former owner can replay customer snapshot';exception when insufficient_privilege then null;end;
 end loop;
 for a in select * from attempts where action in ('create','customer_balance') loop
  begin perform public.solar_reconcile(case a.action when 'create' then 'create_customer' else a.action end,a.request_id,a.data);raise exception 'Former owner can replay account balance';exception when insufficient_privilege then null;end;
 end loop;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418803',true);
do $$declare statement jsonb:=public.solar_customer_statement(-418801); r jsonb:=public.solar_customer_get(-418801);updated jsonb;begin
 assert (statement->>'balance')::numeric=750 and exists(select 1 from public.customers where id=-418801),'Recipient lacks correct account';
 assert not exists(select 1 from jsonb_array_elements(statement->'rows') l where not coalesce((l->>'receiptRestricted')::boolean,false)
   or l ? 'receiptNo' or l ? 'createdBy' or l ? 'notes'),'Foreign receipt leaked in transferred account';
 updated:=public.solar_customer_save('update',gen_random_uuid(),jsonb_build_object('id',-418801,'name',r->>'name','phone',r->>'phone','customerType','wholesale','token',r->>'token'));
 assert (updated->>'openingBalance')::numeric=500 and (updated->>'balance')::numeric=750,'Edit touched a protected foreign opening';
 updated:=public.solar_customer_save('update',gen_random_uuid(),jsonb_build_object('id',-418801,'name',r->>'name','phone',r->>'phone','customerType','wholesale','token',updated->>'token','openingBalance',510));
 assert (updated->>'openingBalance')::numeric=510 and (updated->>'balance')::numeric=760,'Protected opening correction double-counted the previous opening';
end $$;
reset role;
do $$begin
 assert not exists(select 1 from original_financial o left join public.transactions t on t.id=o.id where to_jsonb(t) is distinct from o.original),'New owner rewrote a former owner receipt';
 assert exists(select 1 from public.transactions t where t.party_id=-418801 and t.payment_mode='opening_balance' and t.total=-10 and t.created_by='00000000-0000-0000-0000-000000418803' and not t.cash),'Opening correction missing personal delta';
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000418801',true);
do $$declare r jsonb:=public.solar_customer_get(-418801);updated jsonb;begin
 updated:=public.solar_customer_save('update',gen_random_uuid(),jsonb_build_object('id',-418801,'name',r->>'name','phone',r->>'phone','customerType','wholesale','ownerId','00000000-0000-0000-0000-000000418801','token',r->>'token','openingBalance',525));
 assert updated->>'ownerId'='00000000-0000-0000-0000-000000418801' and (updated->>'openingBalance')::numeric=525 and (updated->>'balance')::numeric=775,'Existing admin edit contract regressed';
 begin perform public.solar_customer_save(action,request_id,data) from attempts where action='transfer_owner';raise exception 'Acknowledged a superseded transfer';exception when sqlstate 'PT409' then null;end;
end $$;
do $$declare actor text;begin
 foreach actor in array array['00000000-0000-0000-0000-000000418804','00000000-0000-0000-0000-000000418805','00000000-0000-0000-0000-000000418806'] loop
  perform set_config('request.jwt.claim.sub',actor,true);
  begin perform public.solar_customer_transfer_targets();raise exception 'Invalid actor saw transfer list';exception when insufficient_privilege then null;end;
  begin perform public.solar_customer_save(action,request_id,data) from attempts where action='transfer_owner';raise exception 'Invalid actor can transfer';exception when insufficient_privilege then null;end;
 end loop;
end $$;
reset role;
set constraints all immediate;
rollback;
