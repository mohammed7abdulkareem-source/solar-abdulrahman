\set ON_ERROR_STOP on
load 'safeupdate';
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000414001','مدير مصاريف الاختبار',true,'admin_staff','07700414001',true,'{}'),
('00000000-0000-0000-0000-000000414002','بائع مصاريف الاختبار',false,'admin_staff','07700414002',true,'{"sale":true,"purchase":true,"profit":true,"warehouse":true,"salesDeleteOwn":true}'),
('00000000-0000-0000-0000-000000414003','مستخدم آخر',false,'admin_staff','07700414003',true,'{"sale":true}');
insert into public.customers(id,name,customer_type,owner_id)values(-414002,'عميل توزيع المصاريف','wholesale','00000000-0000-0000-0000-000000414002');
insert into public.products(id,code,name,qty,cost)values(-414001,'EXPENSE-A','مادة مصاريف',1000,600),(-414002,'EXPENSE-B','مادة إضافية',1000,400);
insert into public.solar_cash_entries(owner_id,actor_id,delta,entry_type)values('00000000-0000-0000-0000-000000414002','00000000-0000-0000-0000-000000414001',100000,'transfer_in');
update solar_private.wholesale_pricing_control set enabled=false where id;
-- A historical raw sale retains its NULL legacy policy and exact amounts.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000414002',true);
insert into public.transactions(id,kind,party_id,party_name,subtotal,total,expenses,cost,profit,cash,payment_mode,created_by,cashbox_user_id)
values(-414090,'sale',-414002,'عميل توزيع المصاريف',1000,1100,100,600,400,false,'credit',auth.uid(),auth.uid());
insert into public.transaction_items(transaction_id,product_id,product_name,qty,price,cost)values(-414090,-414001,'مادة مصاريف',1,1000,600);
update public.products set qty=qty-1 where id=-414001;

create function pg_temp.expense_payload(payer boolean default true,invoice_id bigint default null,mode text default 'credit',expense numeric default 200,price numeric default 1000)returns jsonb language plpgsql security definer set search_path='' as $$
declare t public.transactions;begin
 if invoice_id is not null then select * into t from public.transactions where id=invoice_id;end if;
 return jsonb_build_object('kind','sale','mode',mode,'party','عميل توزيع المصاريف','partyId',-414002,'expenses',expense,'expensesOnCustomer',payer,
 'items',jsonb_build_array(jsonb_build_object('id',-414001,'qty',2,'price',price)))||case when invoice_id is null then '{}'::jsonb else jsonb_build_object('invoiceId',invoice_id,'expectedRevision',t.pricing_revision,'warehouseId',t.warehouse_id)end;
end$$;
create function pg_temp.expense_hash()returns text language sql security definer set search_path='' as $$select md5(jsonb_build_array(
 (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.products t),
 (select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
 (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
 (select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_requests t))::text)$$;
create function pg_temp.expense_metrics()returns jsonb language sql security definer set search_path='' as $$select jsonb_build_object(
 'cash',solar_private.cash_balance(auth.uid()),'profit',solar_private.retained_profit(auth.uid()),
 'customer',(select coalesce(sum((x->>'effect')::numeric),0)from jsonb_array_elements(solar_private.customer_ledger(-414002))x),
 'entries',(select count(*)from public.solar_cash_entries where owner_id=auth.uid()))$$;
create function pg_temp.expense_token(id bigint)returns text language sql security definer set search_path='' as $$select solar_private.warehouse_token(id)$$;
create function pg_temp.expense_checkpoint(id bigint)returns void language plpgsql security definer set search_path='' as $$
declare settlement uuid:=gen_random_uuid();begin
 insert into solar_private.profit_settlements(id,owner_id,snapshot,profit,status,date_to,share,receipt)values(settlement,auth.uid(),'[]',800,'approved',(now()at time zone'Asia/Baghdad')::date,0,'{}');
 insert into solar_private.profit_checkpoints(owner_id,source_key,value,row_data,settlement_id)values(auth.uid(),'tx:'||id,800,jsonb_build_object('date',now(),'kind','sale','value',800),settlement);
end
$$;
create function pg_temp.expense_profit_row(id bigint)returns jsonb language sql security definer set search_path='' as $$select x from jsonb_array_elements(solar_private.profit_rows(auth.uid()))x where x->>'key'='tx:'||id$$;

set local role authenticated;
-- All four cash/credit combinations: one stored invoice, no extra expense entry.
do $$
#variable_conflict use_variable
declare payer boolean;mode text;payload jsonb;r jsonb;before_state jsonb;after_state jsonb;id bigint;begin
 foreach payer in array array[true,false]loop foreach mode in array array['cash','credit']loop
  before_state:=pg_temp.expense_metrics();payload:=pg_temp.expense_payload(payer,null,mode);r:=public.solar_invoice_save(gen_random_uuid(),payload);id:=(r->>'id')::bigint;
  assert(r->>'total')::numeric=case when payer then 2200 else 2000 end;
  assert(r->>'cost')::numeric=1200 and(r->>'profit')::numeric=case when payer then 800 else 600 end;
  assert(r->>'expensesOnCustomer')::boolean=payer;
  after_state:=pg_temp.expense_metrics();
  assert(after_state->>'profit')::numeric-(before_state->>'profit')::numeric=case when payer then 800 else 600 end;
  assert(after_state->>'cash')::numeric-(before_state->>'cash')::numeric=case when mode='cash' then(r->>'total')::numeric else 0 end;
  assert(after_state->>'customer')::numeric-(before_state->>'customer')::numeric=case when mode='credit' then(r->>'total')::numeric else 0 end;
  assert after_state->'entries'=before_state->'entries','Manual invoice expenses posted twice';
  perform set_config('test.expense.'||mode||case when payer then '_customer' else '_company' end,id::text,true);
 end loop;end loop;
end$$;
-- Zero expenses preserve choice, and omitted field defaults true for old clients.
do $$
#variable_conflict use_variable
declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,null,'credit',0));assert(r->>'total')::numeric=2000 and(r->>'profit')::numeric=800 and(r->>'expensesOnCustomer')::boolean=false;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(true)-'expensesOnCustomer');assert(r->>'total')::numeric=2200 and(r->>'expensesOnCustomer')::boolean;
end$$;
-- Preserve the existing unscaled numeric expense contract, including legacy edits.
do $$
#variable_conflict use_variable
declare r jsonb;t public.transactions;payer boolean;before_state jsonb;after_state jsonb;begin
 foreach payer in array array[true,false]loop
  before_state:=pg_temp.expense_metrics();r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(payer,null,'credit',0.005));
  assert(r->>'total')::numeric=case when payer then 2000.005 else 2000 end;
  assert(r->>'profit')::numeric=case when payer then 800 else 799.995 end;
  after_state:=pg_temp.expense_metrics();assert(after_state->>'profit')::numeric-(before_state->>'profit')::numeric=case when payer then 800 else 799.995 end;
  r:=public.solar_invoice_save(gen_random_uuid(),(pg_temp.expense_payload(payer,(r->>'id')::bigint,'credit',0.005)-'expensesOnCustomer')||'{"notes":"نفس المصاريف الكسرية"}');
  select * into t from public.transactions where transactions.id=(r->>'id')::bigint;assert t.expenses=0.005 and t.expenses_on_customer=payer;
 end loop;
end$$;
-- Exact retry/recovery is idempotent; changing payer under same nonce is rejected.
do $$
#variable_conflict use_variable
declare nonce uuid:=gen_random_uuid();payload jsonb:=pg_temp.expense_payload(false);r jsonb;h text;begin
 r:=public.solar_invoice_save(nonce,payload);h:=pg_temp.expense_hash();
 assert public.solar_invoice_save(nonce,payload)=r;
 assert(public.solar_invoice_attempt_resolve(nonce,payload)->'invoice'->>'total')::numeric=2000;
 assert pg_temp.expense_hash()=h;
 begin perform public.solar_invoice_save(nonce,payload||'{"expensesOnCustomer":true}');raise exception 'Changed retry accepted';exception when insufficient_privilege then null;end;
 assert pg_temp.expense_hash()=h;
end$$;
-- Explicit edits, stale revisions, and old clients preserve a saved false policy.
do $$
#variable_conflict use_variable
declare id bigint:=current_setting('test.expense.cash_customer')::bigint;payload jsonb;r jsonb;before_state jsonb;after_state jsonb;h text;begin
 before_state:=pg_temp.expense_metrics();payload:=pg_temp.expense_payload(false,id,'cash');r:=public.solar_invoice_save(gen_random_uuid(),payload);
 after_state:=pg_temp.expense_metrics();assert(r->>'total')::numeric=2000 and(r->>'profit')::numeric=600;
 assert(after_state->>'cash')::numeric=(before_state->>'cash')::numeric-200;
 assert(after_state->>'profit')::numeric=(before_state->>'profit')::numeric-200;
 h:=pg_temp.expense_hash();begin perform public.solar_invoice_save(gen_random_uuid(),payload);raise exception 'Stale edit accepted';exception when sqlstate'PT409'then null;end;assert pg_temp.expense_hash()=h;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,id,'cash')-'expensesOnCustomer');assert(r->>'expensesOnCustomer')::boolean=false and(r->>'total')::numeric=2000;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(true,id,'cash'));assert(r->>'total')::numeric=2200 and(r->>'profit')::numeric=800;
end$$;
-- Historical legacy sale is untouched until explicit edit, then becomes protected.
do $$
#variable_conflict use_variable
declare r jsonb;t public.transactions;begin
 select * into t from public.transactions where id=-414090;assert t.expenses_on_customer is null and not t.fx_pricing and t.total=1100 and t.profit=400;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,-414090,'credit',100));
 select * into t from public.transactions where id=-414090;assert t.fx_pricing and t.expenses_on_customer=false and t.total=2000 and t.profit=700;
end$$;
-- Approved checkpoint remains immutable; only the current available delta changes.
do $$
#variable_conflict use_variable
declare id bigint:=current_setting('test.expense.credit_customer')::bigint;r jsonb;p jsonb;begin
 perform pg_temp.expense_checkpoint(id);r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,id));p:=pg_temp.expense_profit_row(id);
 assert(p->>'value')::numeric=600 and(p->>'settled')::numeric=800 and(p->>'available')::numeric=-200;
 assert public.solar_sale_delete_preview(id)->>'blockedReason' is not null;
end$$;
-- Strong input and raw-write enforcement, no other invoice kind gains new semantics.
do $$
#variable_conflict use_variable
declare bad jsonb;h text:=pg_temp.expense_hash();begin
 foreach bad in array array['null'::jsonb,'"false"'::jsonb,'0'::jsonb,'{}'::jsonb]loop
  begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(true)||jsonb_build_object('expensesOnCustomer',bad));raise exception 'Invalid policy accepted';exception when invalid_parameter_value then null;end;
 end loop;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false)||'{"kind":"purchase"}');raise exception 'Purchase false accepted';exception when invalid_parameter_value then null;end;
 begin update public.transactions set expenses_on_customer=true where id=current_setting('test.expense.credit_company')::bigint;raise exception 'Raw field update accepted';exception when insufficient_privilege then null;end;
 assert pg_temp.expense_hash()=h;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000414003',true);
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,current_setting('test.expense.credit_company')::bigint));raise exception 'Foreign edit accepted';exception when insufficient_privilege then null;end;
 assert pg_temp.expense_hash()=h;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000414002',true);
end$$;
reset role;
do $$begin
 begin update public.transactions set fx_pricing=false where id=current_setting('test.expense.credit_company')::bigint;raise exception 'Company expense entered legacy profit branch';exception when check_violation then null;end;
 assert not has_function_privilege('authenticated','solar_private.invoice_save_v333(uuid,jsonb)','EXECUTE');
end$$;
-- Warehouse quantity amendment and new-item pricing approval both retain false.
set local role authenticated;
do $$
#variable_conflict use_variable
declare id bigint:=current_setting('test.expense.credit_company')::bigint;lines jsonb;t public.transactions;r jsonb;begin
 select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'qty',3))into lines from public.transaction_items i where transaction_id=id;
 perform public.solar_warehouse_action(id,pg_temp.expense_token(id),'save',lines,'تعديل كمية');
 select * into t from public.transactions where transactions.id=id;assert t.expenses_on_customer=false and t.total=3000 and t.profit=1000;
 select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'qty',i.qty))into lines from public.transaction_items i where transaction_id=id;
 lines:=lines||jsonb_build_array(jsonb_build_object('productId',-414002,'qty',1));
 perform public.solar_warehouse_action(id,pg_temp.expense_token(id),'save',lines,'مادة جديدة');
 r:=public.solar_warehouse_pricing('get',id);assert(r->>'expensesOnCustomer')::boolean=false;
 perform public.solar_warehouse_pricing('approve',id,r->>'token','[{"productId":-414002,"price":1000}]',gen_random_uuid());
 select * into t from public.transactions where transactions.id=id;assert t.expenses_on_customer=false and t.total=4000 and t.profit=1600;
 r:=public.solar_profit_detail('tx:'||id);assert(r->'breakdown'->>'invoiceExpensesOnCustomer')::boolean=false and(r->'breakdown'->>'companyInvoiceExpenses')::numeric=200 and(r->'breakdown'->>'customerInvoiceExpenses')::numeric=0 and(r->'breakdown'->>'netProfit')::numeric=1600;
end$$;
reset role;
-- Company costs are not an item discount; adding reimbursed expenses cannot hide a low price.
update solar_private.wholesale_pricing_control set enabled=true,scope_configured=true,scope_mode='all' where id;
insert into solar_private.wholesale_product_prices(product_id,minimum_price,enabled)values(-414001,1000,true)on conflict(product_id)do update set minimum_price=1000,enabled=true;
set local role authenticated;
do $$
#variable_conflict use_variable
declare r jsonb;h text;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false));assert(r->>'total')::numeric=2000 and(r->>'profit')::numeric=600;
 h:=pg_temp.expense_hash();begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(true,null,'credit',500,900));raise exception 'Customer expense concealed underpriced items';exception when sqlstate'PT422'then null;end;assert pg_temp.expense_hash()=h;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,null,'credit',500,900));raise exception 'Company expense bypassed floor';exception when sqlstate'PT422'then null;end;assert pg_temp.expense_hash()=h;
end$$;
-- Deleting a fresh company-paid sale reverses the actual total/profit once.
do $$
#variable_conflict use_variable
declare r jsonb;c jsonb;payload jsonb;nonce uuid:=gen_random_uuid();id bigint;b jsonb;a jsonb;h text;begin
 b:=pg_temp.expense_metrics();r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.expense_payload(false,null,'cash'));id:=(r->>'id')::bigint;
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',id));assert(c->>'directEligible')::boolean,c::text;
 payload:=jsonb_build_object('invoiceId',id,'expectedToken',c->>'token');r:=public.solar_receipt_delete_requests('delete_direct',nonce,payload);
 a:=pg_temp.expense_metrics();assert a=b,'Deletion did not reverse only the invoice effects';h:=pg_temp.expense_hash();assert public.solar_receipt_delete_requests('delete_direct',nonce,payload)=r;assert pg_temp.expense_hash()=h;
 perform set_config('test.expense.deleted',id::text,true);
end$$;
reset role;
do $$
#variable_conflict use_variable
declare t public.transactions;r jsonb;begin
 select * into t from public.transactions where id=current_setting('test.expense.credit_company')::bigint;
 r:=solar_private.customer_invoice_document(t);assert(r->>'expenses_on_customer')::boolean=false and(r->>'total')::numeric=4000;
 assert(select (invoice->>'expenses_on_customer')::boolean=false from solar_private.deleted_sales where invoice_id=current_setting('test.expense.deleted')::bigint);
 assert not exists(select 1 from public.transactions where created_by='00000000-0000-0000-0000-000000414002'and kind in('profit_expense','cash_expense'));
 assert(select value=800 from solar_private.profit_checkpoints where source_key='tx:'||current_setting('test.expense.credit_customer'));
end$$;
set constraints all immediate;
select 'PASS: expense payer totals/profit, cash/credit, replay, edits, historical fallback, checkpoints, raw guards, warehouse paths, minimum prices, deletion and document metadata';
rollback;
