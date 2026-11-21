-- Local synthetic records only. Prove selectivity at the RPCs used by the statement.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000422501','مدير الاختبار',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000422502','صاحب الوصل الأصلي',false,'admin_staff','{"customers":true,"customerStatement":true,"sale":true,"system":true}'),
 ('00000000-0000-0000-0000-000000422503','مستلم الاختبار',false,'admin_staff','{"customers":true,"customerStatement":true,"sale":true,"system":true,"installations":true,"deletionRequests":true}'),
 ('00000000-0000-0000-0000-000000422504','المالك التالي',false,'admin_staff','{"customers":true,"customerStatement":true,"system":true}'),
 ('00000000-0000-0000-0000-000000422505','مخزن',true,'warehouse','{}');
insert into public.customers(id,name,customer_type,owner_id) values
 (-422501,'عميل وصل اختبار فريد','system','00000000-0000-0000-0000-000000422502'),
 (-422502,'عميل آخر لاختبار الربط','system','00000000-0000-0000-0000-000000422502'),
 (-422503,'أسم مشترك للاختبار','system','00000000-0000-0000-0000-000000422502');
-- Emulate duplicate names saved by older versions before the current write guard.
alter table public.customers disable trigger solar_customer_guard;
insert into public.customers(id,name,customer_type,owner_id) values
 (-422504,'اسم مشترك للاختبار','system','00000000-0000-0000-0000-000000422502');
alter table public.customers enable trigger solar_customer_guard;

insert into public.products(id,code,name,qty,cost) values(-422501,'RESP4225','بطارية الاختبار',8,900);
insert into public.transactions(id,kind,party_id,party_name,total,payment_mode,cash,created_by,cashbox_user_id,notes)
 select id,k,pid,n,t,mode,cash,'00000000-0000-0000-0000-000000422502'::uuid,'00000000-0000-0000-0000-000000422502'::uuid,'نص أصلي '||id
 from (values
  (42250101,'system',-422501,'عميل وصل اختبار فريد',5138000,'credit',false),
  (42250102,'sale',-422501,'عميل وصل اختبار فريد',11000,'cash',true),
  (42250103,'sale',null,'عميل وصل اختبار فريد',21000,'credit',false),
  (42250104,'customer_payment',-422501,'عميل وصل اختبار فريد',9000,'payment',true),
  (42250105,'system',-422502,'عميل وصل اختبار فريد',42000,'credit',false),
  (42250106,'sale',null,'اسم مشترك للاختبار',31000,'credit',false),
  (42250107,'sale',-422501,'عميل وصل اختبار فريد',7000,'credit',false)
 ) as fixture(id,k,pid,n,t,mode,cash);
update public.transactions set expenses=500 where id=42250101;
update public.transactions set expenses=500,expenses_on_customer=false,fx_pricing=true where id=42250102;
insert into public.transaction_items(transaction_id,product_id,product_name,qty,price,cost)
 select id,-422501,'بطارية الاختبار',1,1250,900 from public.transactions where id between 42250101 and 42250107 and kind in ('sale','system');

-- Match the product balance to the six fixture lines posted to warehouse 1.
update public.products set qty=(select qty from solar_private.warehouse_stocks where product_id=-422501 and warehouse_id=1) where id=-422501;

create function pg_temp.financial_snapshot() returns jsonb language sql as $$
 select jsonb_build_object(
  'ledger',solar_private.customer_ledger(-422501),
  'cashboxes',(select jsonb_object_agg(id,solar_private.cash_balance(id)) from public.profiles
   where id between '00000000-0000-0000-0000-000000422501' and '00000000-0000-0000-0000-000000422505'),
  'invoices',(select jsonb_agg(to_jsonb(t) order by id) from public.transactions t where id between 42250101 and 42250107),
  'lines',(select jsonb_agg(to_jsonb(i) order by id) from public.transaction_items i where transaction_id between 42250101 and 42250107),
  'warehouse',(select jsonb_agg(to_jsonb(w) order by warehouse_id) from solar_private.warehouse_stocks w where product_id=-422501),
  'stock',(select to_jsonb(p) from public.products p where id=-422501))
$$;
create temp table original as select pg_temp.financial_snapshot() as financial;
create temp table transfer(request_id uuid default gen_random_uuid(), payload jsonb, response jsonb);
grant select,insert,update on transfer to authenticated;
create function pg_temp.payload(destination uuid, selection jsonb) returns jsonb language sql as $$
 select jsonb_build_object('id',-422501,'ownerId',destination,'token',public.solar_customer_get(-422501)->>'token',
  'receiptToken',public.solar_customer_transfer_receipts(-422501)->>'receiptToken','receiptIds',selection)
$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422501',true);
do $$declare choices jsonb:=public.solar_customer_transfer_receipts(-422501); payload jsonb; selection jsonb; begin
 assert (select array_agg((x->>'id')::bigint order by (x->>'id')::bigint) from jsonb_array_elements(choices->'receipts') x)
  =array[42250101,42250102,42250103,42250107]::bigint[], 'Chooser included a payment, ambiguous or foreign invoice, or lost a linked invoice';
 assert not exists(select 1 from jsonb_array_elements(choices->'receipts') x where x->>'ownerId' is distinct from '00000000-0000-0000-0000-000000422502');
 assert jsonb_array_length(public.solar_customer_transfer_receipts(-422503)->'receipts')=0 and jsonb_array_length(public.solar_customer_transfer_receipts(-422504)->'receipts')=0,'Ambiguous legacy name accepted';
 payload:=pg_temp.payload('00000000-0000-0000-0000-000000422503','[42250101,42250102]');
 foreach selection in array array['[42250101,42250104]'::jsonb,'[42250101,42250105]'::jsonb,'[42250106]'::jsonb,'[9999999999]'::jsonb,'[42250102,42250102]'::jsonb,'["42250101"]'::jsonb,'{}'::jsonb] loop
  begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),payload||jsonb_build_object('receiptIds',selection));
   raise exception 'Invalid selection accepted %',selection; exception when invalid_parameter_value then null; end;
 end loop;
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),payload||'{"receiptToken":"stale"}');raise exception 'Changed receipt list accepted';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),payload||'{"ownerId":"00000000-0000-0000-0000-000000422505"}');raise exception 'Warehouse destination accepted';exception when invalid_parameter_value then null;end;
 assert public.solar_customer_get(-422501)->>'ownerId'='00000000-0000-0000-0000-000000422502','Failed requests changed owner';
 insert into transfer(payload) values(payload);
end$$;
do $$declare actor text;begin
 foreach actor in array array['00000000-0000-0000-0000-000000422502','00000000-0000-0000-0000-000000422503','00000000-0000-0000-0000-000000422505'] loop
  perform set_config('request.jwt.claim.sub',actor,true);
  begin perform public.solar_customer_transfer_receipts(-422501);raise exception 'Nonadmin opened receipt chooser';exception when insufficient_privilege then null;end;
  begin perform public.solar_customer_save('transfer_owner',request_id,payload) from transfer;raise exception 'Nonadmin forged transfer';exception when insufficient_privilege then null;end;
 end loop;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422501',true);
update transfer set response=public.solar_customer_save('transfer_owner',request_id,payload);
do $$declare a record;choices jsonb:=public.solar_customer_transfer_receipts(-422501);begin
 select * into a from transfer;
 assert a.response->>'receiptCount'='2' and a.response->'receiptIds'='[42250101,42250102]'::jsonb,'Selected list was lost';
 assert public.solar_customer_save('transfer_owner',a.request_id,a.payload)=a.response,'Retry changed the result';
 assert (select count(*) from jsonb_array_elements(choices->'receipts') x where x->>'ownerId'='00000000-0000-0000-0000-000000422503')=2;
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),a.payload);raise exception 'Stale transfer accepted';exception when sqlstate 'PT409' then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422503',true);
do $$declare account jsonb;row_json jsonb;doc jsonb;batch jsonb;begin
 foreach account in array array[public.solar_customer_get(-422501),public.solar_customer_statement(-422501)] loop
  assert (account->>'balance')::numeric=5157000,'Ledger balance changed or doubled after assignment';
  select x into row_json from jsonb_array_elements(account->'rows') x where x->>'id'='42250101';
  assert row_json->>'kind'='system' and row_json->'assignedReceipt'='true'::jsonb and row_json->'canFollowInstallation'='true'::jsonb
   and row_json->'canEditReceipt'='false'::jsonb and row_json->'canDeleteReceipt'='false'::jsonb,'Transferred system lost read/follow or gained invoice mutation';
  select x into row_json from jsonb_array_elements(account->'rows') x where x->>'id'='42250102';
  assert row_json->>'kind'='sale' and row_json->'assignedReceipt'='true'::jsonb and row_json->'canFollowInstallation'='false'::jsonb
   and row_json->'canEditReceipt'='false'::jsonb and row_json->'canDeleteReceipt'='false'::jsonb,'Wholesale receipt got system/financial actions';
  assert (select count(*) from jsonb_array_elements(account->'rows') x where x->'receiptRestricted'='true'::jsonb and x->>'id' like 'restricted:%' and not x ? 'receiptNo')=3,'Unselected receipts or payment leaked';
  batch:=public.solar_customer_invoice_report_batch(-422501,array[42250101,42250102,42250103,42250104,42250105],account->>'token');
  assert jsonb_array_length(batch->'rows')=2 and not exists(select 1 from jsonb_array_elements(batch->'rows') x where x->>'id' not in ('42250101','42250102') or jsonb_array_length(x->'items')<>1),'Batch fetched unselected document or missed selected item';
 end loop;
 doc:=public.solar_customer_documents(-422501,null,null,'invoices');
 assert (doc->>'count')::integer=2,'Receipt list had hidden or missing bills';
 doc:=public.solar_customer_movement(-422501,42250101);
 assert doc->>'type'='invoice' and doc#>>'{invoice,items,0,product_name}'='بطارية الاختبار'
  and doc#>>'{movement,creatorName}'='صاحب الوصل الأصلي' and doc#>>'{invoice,operationalOwnerId}'='00000000-0000-0000-0000-000000422503','Original document, author or custodian lost';
 assert not(doc->'invoice' ? 'profit') and not(doc#>'{invoice,items,0}' ? 'cost') and not(doc->'invoice' ? 'invoice_account')
  and (doc#>>'{invoice,expenses}')::numeric=0 and doc#>>'{invoice,assignedReceipt}'='true','Delegation exposed private account, uncharged expenses or item cost';
 doc:=public.solar_customer_movement(-422501,42250102);
 assert (doc#>>'{invoice,expenses}')::numeric=0,'Wholesale cost-only expense disclosed';
 assert public.solar_statement_sale_for_edit(-422501,42250101) is null,'Recipient can open financial editor for another issuer';
 begin perform public.solar_customer_movement(-422501,42250103);raise exception 'Unselected receipt opened';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_movement(-422501,42250104);raise exception 'Previous owner payment opened';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_movement(-422502,42250101);raise exception 'Cross-customer document opened';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422502',true);
do $$begin
 begin perform public.solar_customer_statement(-422501);raise exception 'Previous owner retained statement';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422501',true);
do $$declare payload jsonb;result jsonb;begin
 assert (public.solar_customer_movement(-422501,42250101)->'invoice' ? 'invoice_account') and (public.solar_customer_movement(-422501,42250101)#>>'{invoice,expenses}')::numeric=500,'Admin lost original invoice data';
 assert public.solar_statement_sale_for_edit(-422501,42250101)->>'operationalOwnerId'='00000000-0000-0000-0000-000000422503','Authorized editor lacks current expense owner';
 payload:=pg_temp.payload('00000000-0000-0000-0000-000000422503','[42250103]');
 result:=public.solar_customer_save('transfer_owner',gen_random_uuid(),payload);
 assert result->>'receiptCount'='1' and result->>'ownerId'='00000000-0000-0000-0000-000000422503','Cannot attach missed legacy receipt to current owner';
 begin perform public.solar_customer_save('transfer_owner',gen_random_uuid(),pg_temp.payload('00000000-0000-0000-0000-000000422503','[42250103]'));raise exception 'Reassignment to same custodian accepted';exception when invalid_parameter_value then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422503',true);
do $$begin assert public.solar_customer_movement(-422501,42250103)->>'type'='invoice','Missed legacy receipt is still restricted';end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422501',true);
select public.solar_customer_save('transfer_owner',gen_random_uuid(),pg_temp.payload('00000000-0000-0000-0000-000000422504','[42250101]'))->>'receiptCount';
do $$begin
 begin perform public.solar_customer_save('transfer_owner',request_id,payload) from transfer;raise exception 'Obsolete transfer replay accepted';exception when sqlstate 'PT409' then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422504',true);
do $$declare doc jsonb:=public.solar_customer_documents(-422501);begin
 assert doc->>'count'='1' and doc#>>'{rows,0,invoice,id}'='42250101','Next owner gained previous custodian receipts';
end$$;
reset role;
do $$begin
 assert (select count(*) from solar_private.customer_receipt_responsibility where customer_id=-422501)=3,'Duplicate or unselected receipt responsibilities';
 assert (select r.owner_id from solar_private.customer_receipt_responsibility r where r.transaction_id=42250102)='00000000-0000-0000-0000-000000422503','Omitted receipt moved on later transfer';
 assert (select count(*) from solar_private.customer_changes where customer_id=-422501 and action='transfer_owner')=3,'Missing or duplicate audit';
 assert exists(select 1 from solar_private.customer_changes c join transfer t using(request_id)
  where c.actor_id='00000000-0000-0000-0000-000000422501' and jsonb_array_length(c.before_customer->'receiptOwners')=2 and c.after_customer->'receiptIds'=t.payload->'receiptIds'),'Audit missing selected receipts/previous custodians';
 assert pg_temp.financial_snapshot()=(select financial from original),'Transfer changed original receipt, item/stock cost, ledger or cashbox';
 assert not has_function_privilege('anon','public.solar_customer_transfer_receipts(bigint)','execute')
  and not has_function_privilege('authenticated','solar_private.assigned_customer_receipt(bigint,bigint)','execute')
  and not has_table_privilege('authenticated','solar_private.customer_receipt_responsibility','select,insert,update,delete'),'Delegation bypasses protected RPCs';
end$$;
-- Moving the account back alone must not give its original seller the other
-- employee's expense editor. Their own historical sale editor still works.
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422501',true);
select public.solar_customer_save('transfer_owner',gen_random_uuid(),
 pg_temp.payload('00000000-0000-0000-0000-000000422502','[]')-'receiptToken'-'receiptIds')->>'ownerId';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000422502',true);
do $$declare original_editor jsonb:=public.solar_statement_sale_for_edit(-422501,42250101);begin
 assert original_editor->>'created_by'='00000000-0000-0000-0000-000000422502'
  and original_editor->>'operationalOwnerId'='00000000-0000-0000-0000-000000422504'
  and original_editor ? 'invoice_account' and not(original_editor ? 'assignedReceipt'),
  'Original seller confused with current operational owner after account-only transfer';
end$$;
reset role;
set constraints all immediate;
rollback;
