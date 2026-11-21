begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000418201','Admin',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000418202','Original cashier',false,'admin_staff','{"customers":true,"customerStatement":true,"customerPayment":true,"systemPayment":true}'),
 ('00000000-0000-0000-0000-000000418203','New account owner',false,'admin_staff','{"customers":true,"customerStatement":true,"customerPayment":true,"systemPayment":true}');
insert into public.customers(id,name,customer_type,owner_id) values
 (-418201,'عميل جملة لنقل الحساب','wholesale','00000000-0000-0000-0000-000000418202'),
 (-418202,'عميل منظومة لنقل الحساب','system','00000000-0000-0000-0000-000000418202');
insert into public.transactions(id,kind,party_type,party_id,party_name,total,payment_mode,cash,created_by,cashbox_user_id) values
 (-418201,'sale','customer',-418201,'عميل جملة لنقل الحساب',1200,'credit',false,'00000000-0000-0000-0000-000000418202','00000000-0000-0000-0000-000000418202'),
 (-418202,'system','customer',-418202,'عميل منظومة لنقل الحساب',1200,'credit',false,'00000000-0000-0000-0000-000000418202','00000000-0000-0000-0000-000000418202');
create function pg_temp.pay_context(is_system boolean,cid bigint) returns jsonb language sql as $$
 select case when is_system then public.solar_system_payment_context(cid) else public.solar_customer_payment_context(cid) end
$$;
create function pg_temp.pay_create(is_system boolean,key uuid,payload jsonb) returns jsonb language sql as $$
 select case when is_system then public.solar_system_payment_save(key,payload) else public.solar_customer_payment_save(key,payload) end
$$;
create function pg_temp.pay_edit(is_system boolean,action text,key uuid,payload jsonb) returns jsonb language sql as $$
 select case when is_system then public.solar_statement_system_payment(action,key,payload) else public.solar_customer_payment_manage(action,key,payload) end
$$;

set local role authenticated;
do $$
declare
 admin_id uuid:='00000000-0000-0000-0000-000000418201';
 former uuid:='00000000-0000-0000-0000-000000418202';
 target_id uuid:='00000000-0000-0000-0000-000000418203';
 cid bigint; is_system boolean; account jsonb; payload jsonb; cached jsonb; correction jsonb;
 create_key uuid; edit_key uuid; receipt_id bigint; edit_ctx jsonb; statement jsonb; next_receipt jsonb;
begin
 for cid in select unnest(array[-418201,-418202]) loop
  is_system:=cid=-418202;
  perform set_config('request.jwt.claim.sub',former::text,true);
  account:=pg_temp.pay_context(is_system,cid);
  create_key:=gen_random_uuid(); edit_key:=gen_random_uuid();
  payload:=jsonb_build_object('customerId',cid,'mode','payment','amount',100,'notes','original receipt details','expectedToken',account->>'token');
  cached:=pg_temp.pay_create(is_system,create_key,payload);
  receipt_id:=(cached->>'id')::bigint;
  edit_ctx:=pg_temp.pay_edit(is_system,'get',null,jsonb_build_object('id',receipt_id));
  correction:=jsonb_build_object('id',receipt_id,'amount',120,'notes','original corrected details','expectedToken',edit_ctx->>'token');
  cached:=pg_temp.pay_edit(is_system,'update',edit_key,correction);
  assert cached=pg_temp.pay_edit(is_system,'update',edit_key,correction),'authorized correction replay changed';
  edit_ctx:=pg_temp.pay_edit(is_system,'get',null,jsonb_build_object('id',receipt_id));
  -- Capture an open new-payment draft after the correction, so the token
  -- was current when the transfer began. Keep the untouched creation replay
  -- separate from the edited receipt's creation cache.
  account:=pg_temp.pay_context(is_system,cid);
  create_key:=gen_random_uuid();
  payload:=payload||jsonb_build_object('amount',10,'expectedToken',account->>'token');
  cached:=pg_temp.pay_create(is_system,create_key,payload);
  assert cached=pg_temp.pay_create(is_system,create_key,payload),'authorized save replay changed';
  account:=pg_temp.pay_context(is_system,cid);
  perform set_config('request.jwt.claim.sub',admin_id::text,true);
  perform public.solar_customer_save('transfer_owner',gen_random_uuid(),
   jsonb_build_object('id',cid,'ownerId',target_id,'token',public.solar_customer_get(cid)->>'token'));

  perform set_config('request.jwt.claim.sub',former::text,true);
  begin perform public.solar_customer_statement(cid);raise exception 'transferred statement opened';exception when insufficient_privilege then null;end;
  begin perform public.solar_customer_documents(cid);raise exception 'transferred documents opened';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_context(is_system,cid);raise exception 'transferred payment form reopened';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_create(is_system,gen_random_uuid(),payload||jsonb_build_object('expectedToken',account->>'token'));raise exception 'cached draft posted after transfer';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_create(is_system,create_key,payload);raise exception 'former owner received a cached account context';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_edit(is_system,'get',null,jsonb_build_object('id',receipt_id));raise exception 'former owner previewed transferred account';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_edit(is_system,'update',gen_random_uuid(),correction||jsonb_build_object('expectedToken',edit_ctx->>'token'));raise exception 'open edit posted after transfer';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_edit(is_system,'update',edit_key,correction);raise exception 'former owner replayed account correction';exception when insufficient_privilege then null;end;

  perform set_config('request.jwt.claim.sub',target_id::text,true);
  statement:=public.solar_customer_statement(cid);
  assert (statement->>'balance')::numeric=1070,'transferred balance changed';
  assert jsonb_array_length(statement->'rows')=3 and not exists(select 1 from jsonb_array_elements(statement->'rows') x where x->>'receiptRestricted' is distinct from 'true'),'prior receipts disclosed to target';
  begin perform public.solar_payment_history('get',jsonb_build_object('id',receipt_id));raise exception 'historical receipt ownership moved';exception when insufficient_privilege then null;end;
  begin perform pg_temp.pay_edit(is_system,'get',null,jsonb_build_object('id',receipt_id));raise exception 'new owner editing historical receipt';exception when insufficient_privilege then null;end;
  account:=pg_temp.pay_context(is_system,cid);
  next_receipt:=pg_temp.pay_create(is_system,gen_random_uuid(),jsonb_build_object('customerId',cid,'mode','payment','amount',15,'notes','new owner receipt','expectedToken',account->>'token'));
  assert (next_receipt->>'remaining')::numeric=1055,'new owner payment did not reduce transferred balance';
  assert (pg_temp.pay_edit(is_system,'get',null,jsonb_build_object('id',(next_receipt->>'id')::bigint))->>'total')::numeric=15,'new owner missing their own edit right';
 end loop;
end $$;
reset role;
do $$begin
 assert (select count(*)=4 from public.transactions where party_id in(-418201,-418202) and kind in('customer_payment','system_payment') and created_by='00000000-0000-0000-0000-000000418202' and cashbox_user_id=created_by),'old receipts/cash changed or duplicate submission';
 assert (select count(*)=2 from public.transactions where party_id in(-418201,-418202) and kind in('customer_payment','system_payment') and created_by='00000000-0000-0000-0000-000000418203' and cashbox_user_id=created_by),'new receipts attributed to wrong cashier';
end $$;
rollback;
