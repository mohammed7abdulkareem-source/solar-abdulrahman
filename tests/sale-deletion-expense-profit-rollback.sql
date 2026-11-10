\set ON_ERROR_STOP on
-- Isolated database only. No permanent changes: every scenario rolls back.
begin;
do $$begin
 if current_database() !~ '^solar_[a-z0-9_]+$' then raise exception 'Use an isolated local test database';end if;
end$$;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000310100','مدير اختبار إلغاء المصاريف',true,'admin_staff','{}','07700310100'),
('00000000-0000-0000-0000-000000310101','صاحب فواتير إلغاء المصاريف',false,'admin_staff','{"sale":true,"system":true,"installations":true,"systemPayment":true,"cash":true,"cashExpense":true,"profit":true,"profitSettlement":true}','07700310101'),
('00000000-0000-0000-0000-000000310102','مستخدم مستقل عن الفواتير',false,'admin_staff','{"cash":true,"profit":true}','07700310102'),
('00000000-0000-0000-0000-000000310103','مهندس اختبار الإلغاء',false,'installer','{}','07700310103');
insert into customers(id,name,customer_type,owner_id)values
(-310101,'زبون جملة اختبار المصاريف','wholesale','00000000-0000-0000-0000-000000310101'),
(-310102,'زبون منظومة اختبار المصاريف','system','00000000-0000-0000-0000-000000310101');
insert into products(id,code,name,qty,cost)values(-310101,'VOID-EXP-3101','مادة اختبار إلغاء المصاريف',100,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,-310101,100)
on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,created_at)values
('00000000-0000-0000-0000-000000310100','00000000-0000-0000-0000-000000310100',2000000,'transfer_in','2026-09-30T12:00Z'),
('00000000-0000-0000-0000-000000310101','00000000-0000-0000-0000-000000310100',2000000,'transfer_in','2026-09-30T12:00Z');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310100',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId','00000000-0000-0000-0000-000000310101','mode','expense','currency','IQD','amount',20000,'note','مصروف تشغيل مستقل لا يلغى مع الفواتير'));
 perform set_config('test.expense_delete.independent',r->>'id',true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"cash","partyId":-310101,"party":"زبون جملة اختبار المصاريف","expenses":40000,"items":[{"id":-310101,"qty":2,"price":200000}]}');
 perform set_config('test.expense_delete.cash_sale',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-310101,"party":"زبون جملة اختبار المصاريف","expenses":15000,"items":[{"id":-310101,"qty":1,"price":300000}]}');
 perform set_config('test.expense_delete.credit_sale',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-310102,"party":"زبون منظومة اختبار المصاريف","total":1000000,"customerAddress":"عنوان اختبار","installerId":"00000000-0000-0000-0000-000000310103","items":[{"id":-310101,"qty":1,"price":0}]}');
 perform set_config('test.expense_delete.system',r->>'id',true);
end$$;
reset role;
update transactions set warehouse_status='ready'where id=current_setting('test.expense_delete.system')::bigint;
set local role authenticated;
do $$declare j transactions;r jsonb;begin
 select * into j from transactions where id=current_setting('test.expense_delete.system')::bigint;
 perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":300000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310100',true);
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":450000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
 r:=public.solar_system_payment_context(-310102);
 r:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-310102,'invoiceId',j.id,'amount',100000,'mode','payment','expectedToken',r->>'token'));
 perform set_config('test.expense_delete.payment',r->>'id',true);
end$$;
reset role;
-- Payout dates precede deletion so historical-period totals must remain intact.
update solar_cash_entries set created_at='2026-10-01T12:00Z'where job_id=current_setting('test.expense_delete.system')::bigint;
-- END SHARED FIXTURE SETUP

create function pg_temp.expense_delete_hash()returns text language sql security definer as $$
 select md5(jsonb_build_array(
  (select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
  (select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
  (select jsonb_agg(to_jsonb(t)order by id)from public.products t),
  (select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
  (select jsonb_agg(to_jsonb(t)order by invoice_id)from solar_private.deleted_sales t),
  (select jsonb_agg(to_jsonb(t)order by owner_id,source_key)from solar_private.profit_checkpoints t))::text)
$$;
create function pg_temp.expense_delete_profit(uid uuid)returns numeric language sql security definer as $$select solar_private.retained_profit(uid)$$;
create function pg_temp.approve_expense_fixture(invoice_id bigint)returns uuid language plpgsql as $$
declare c jsonb;r jsonb;d jsonb;fingerprint text;begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
 fingerprint:=pg_temp.expense_delete_hash();
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 assert c->>'blockedReason' is null,c::text;
 r:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',invoice_id,'expectedToken',c->>'token'));
 assert pg_temp.expense_delete_hash()=fingerprint,'Request changed cash, profits, stock or archives';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310102',true);
 begin perform public.solar_receipt_delete_requests('get',(r->>'id')::uuid);raise exception 'Foreign request exposed';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
 begin perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,'{}');raise exception 'Owner self approved';exception when insufficient_privilege then null;end;
 assert pg_temp.expense_delete_hash()=fingerprint,'Denied access changed accounting';
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310100',true);
 d:=public.solar_receipt_delete_requests('get',(r->>'id')::uuid);
 perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));
 fingerprint:=pg_temp.expense_delete_hash();
 perform public.solar_receipt_delete_requests('approve',(r->>'id')::uuid,jsonb_build_object('expectedToken',d->>'reviewToken'));
 assert pg_temp.expense_delete_hash()=fingerprint,'Retry duplicated deletion/refund/profit effect';
 return(r->>'id')::uuid;
end$$;

-- Wholesale expenses are part of the invoice total. They must not survive as
-- an independent deduction or be refunded twice when a cash sale is cancelled.
set local role authenticated;
do $$declare owner_id uuid:='00000000-0000-0000-0000-000000310101';admin_id uuid:='00000000-0000-0000-0000-000000310100';before_cash numeric;before_profit numeric;invoice_id bigint;begin
 assert pg_temp.expense_delete_profit(owner_id)=830000,'Unexpected initial profit (200000+200000+450000-20000)';
 assert pg_temp.expense_delete_profit(admin_id)=0,'Installation payer was charged the invoice owner profit';
 invoice_id:=current_setting('test.expense_delete.cash_sale')::bigint;
 before_cash:=solar_private.cash_balance(owner_id);before_profit:=pg_temp.expense_delete_profit(owner_id);
 perform pg_temp.approve_expense_fixture(invoice_id);
 assert solar_private.cash_balance(owner_id)=before_cash-440000,'Cash sale reversal must include its 40000 invoice expense exactly once';
 assert pg_temp.expense_delete_profit(owner_id)=before_profit-200000,'Wholesale invoice expense left a profit deduction';
 invoice_id:=current_setting('test.expense_delete.credit_sale')::bigint;
 before_cash:=solar_private.cash_balance(owner_id);before_profit:=pg_temp.expense_delete_profit(owner_id);
 perform pg_temp.approve_expense_fixture(invoice_id);
 assert solar_private.cash_balance(owner_id)=before_cash,'Credit sale expense invented a cash refund';
 assert pg_temp.expense_delete_profit(owner_id)=before_profit-200000,'Credit sale expense left a profit deduction';
end$$;
reset role;

-- A downstream failure must roll back the invoice, both payers' refunds and
-- the archive together. The same approved workflow can then safely retry.
create function pg_temp.reject_expense_delete()returns trigger language plpgsql as $$begin
 if old.id=current_setting('test.expense_delete.system')::bigint then raise exception 'fixture expense deletion failure';end if;return old;
end$$;
create trigger reject_expense_delete before delete on transactions for each row execute function pg_temp.reject_expense_delete();
set local role authenticated;
do $$declare fingerprint text:=pg_temp.expense_delete_hash();begin
 begin perform pg_temp.approve_expense_fixture(current_setting('test.expense_delete.system')::bigint);raise exception 'Expected downstream failure';
 exception when raise_exception then if sqlerrm<>'fixture expense deletion failure'then raise;end if;end;
 assert pg_temp.expense_delete_hash()=fingerprint,'Failed cancellation left partial accounting changes';
end$$;
reset role;
drop trigger reject_expense_delete on transactions;

set local role authenticated;
do $$declare owner_id uuid:='00000000-0000-0000-0000-000000310101';admin_id uuid:='00000000-0000-0000-0000-000000310100';invoice_id bigint:=current_setting('test.expense_delete.system')::bigint;owner_cash numeric;admin_cash numeric;profit_before numeric;statement jsonb;past_closing numeric;r jsonb;begin
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 owner_cash:=solar_private.cash_balance(owner_id);admin_cash:=solar_private.cash_balance(admin_id);profit_before:=pg_temp.expense_delete_profit(owner_id);
 r:=public.solar_sale_delete_preview(invoice_id);
 assert(r->>'expenseRefund')::numeric=450000 and jsonb_array_length(r->'expenseRefunds')=2,'Two original payers missing from refund preview';
 statement:=public.solar_cash_statement(owner_id,'2026-10-01','2026-10-31','IQD');past_closing:=(statement->'ledgers'->0->>'closing')::numeric;
 perform pg_temp.approve_expense_fixture(invoice_id);
 assert solar_private.cash_balance(owner_id)=owner_cash+300000,'Owner original installation payment not reversed';
 assert solar_private.cash_balance(admin_id)=admin_cash+150000,'Administrator original installation payment not reversed';
 assert pg_temp.expense_delete_profit(owner_id)=profit_before-450000,'Deleted system retained expenses or counted cash refund as new profit';
 assert pg_temp.expense_delete_profit(owner_id)=-20000,'Independent operating expense disappeared';
 assert pg_temp.expense_delete_profit(admin_id)=0,'Refund was counted as administrator income';
 statement:=public.solar_cash_statement(owner_id,'2026-10-01','2026-10-31','IQD');
 assert(statement->'ledgers'->0->>'closing')::numeric=past_closing,'Cancellation rewrote historical cash period';
 perform set_config('request.jwt.claim.sub',owner_id::text,true);
 r:=public.solar_profit_workspace('balance',null,'{}');
 assert(r->>'remaining')::numeric=-20000 and(r->'period'->>'earned')::numeric=-20000,'Public profit report retained a linked expense';
 assert jsonb_array_length(r->'rows')=1,'Unexpected residual profit movement after all test invoices cancelled';
 r:=public.solar_system_payment_context(-310102);
 assert(r->>'balance')::numeric=-100000,'Linked customer payment was deleted with invoice instead of remaining on account';
end$$;
reset role;
do $$declare deleted_invoice_id bigint:=current_setting('test.expense_delete.system')::bigint;begin
 assert(select count(*)from solar_cash_entries where deleted_job_id=deleted_invoice_id)=4,'Original payouts/refunds not retained';
 assert not exists(select 1 from solar_cash_entries where deleted_job_id=deleted_invoice_id group by owner_id having sum(delta)<>0),'Archived expense net must be zero per payer';
 assert not exists(select 1 from solar_cash_entries where job_id=deleted_invoice_id),'Cash entries still point to deleted invoice';
 assert(select jsonb_array_length(invoice->'_cashEntriesBeforeDeletion')from solar_private.deleted_sales where invoice_id=deleted_invoice_id)=2,'Original cash audit missing';
 assert exists(select 1 from transactions where id=current_setting('test.expense_delete.independent')::bigint and total=20000),'Independent expense deleted';
 assert exists(select 1 from transactions where kind='system_payment'and party_id=-310102 and total=100000 and system_invoice_id is null),'Collection audit changed';
 assert(select qty from products where id=-310101)=100,'Inventory was not restored exactly once';
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000310101')=2080000,'Owner final box must preserve deposit, independent expense and customer collection';
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000310100')=2000000,'Original payer final box differs from starting balance';
end$$;

-- A pre-existing paid installation with approved_expenses=0 is repaired using
-- its explicit job_id and actual signed ledger, never a matching name/amount.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-310102,"party":"زبون منظومة اختبار المصاريف","total":1000000,"customerAddress":"قديم","installerId":"00000000-0000-0000-0000-000000310103","items":[{"id":-310101,"qty":1,"price":0}]}');
 perform set_config('test.expense_delete.legacy',r->>'id',true);
end$$;
reset role;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,job_id)values
('00000000-0000-0000-0000-000000310101','00000000-0000-0000-0000-000000310100',-50000,'installation_payout',current_setting('test.expense_delete.legacy')::bigint);
set local role authenticated;
do $$declare owner_id uuid:='00000000-0000-0000-0000-000000310101';before_cash numeric:=solar_private.cash_balance(owner_id);before_profit numeric:=pg_temp.expense_delete_profit(owner_id);begin
 perform pg_temp.approve_expense_fixture(current_setting('test.expense_delete.legacy')::bigint);
 assert solar_private.cash_balance(owner_id)=before_cash+50000,'Legacy paid expense was not refunded';
 assert pg_temp.expense_delete_profit(owner_id)=before_profit,'Legacy expense refund invented profit';
end$$;
reset role;

-- Approved settlements keep their financial history: cancellation must stop
-- before erasing a source whose profit was already distributed.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310101',true);
set local role authenticated;
do $$declare r jsonb;c jsonb;request_id uuid:=gen_random_uuid();invoice_id bigint;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"sale","mode":"credit","partyId":-310101,"party":"زبون جملة اختبار المصاريف","expenses":20000,"items":[{"id":-310101,"qty":1,"price":500000}]}');
 invoice_id:=(r->>'id')::bigint;perform set_config('test.expense_delete.settled',invoice_id::text,true);
 c:=public.solar_profit_workspace('overview',null,'{}');assert(c->>'available')::numeric=380000;
 r:=public.solar_profit_workspace('request',request_id,jsonb_build_object('expectedToken',c->>'token'));
 perform set_config('test.expense_delete.settlement',request_id::text,true);
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000310100',true);
 c:=public.solar_profit_workspace('overview',null,jsonb_build_object('ownerId','00000000-0000-0000-0000-000000310101'));
 select x into r from jsonb_array_elements(c->'requests')x where x->>'id'=request_id::text;
 perform public.solar_profit_workspace('approve',gen_random_uuid(),jsonb_build_object('id',request_id,'expectedToken',r->>'token','share',380000,'collectionConfirmed',true,'settlementModel','owner_debit_supplier_charge'));
 c:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',invoice_id));
 assert c->>'blockedReason' is not null,'Approved profit source lost its deletion guard';
 begin perform public.solar_receipt_delete_requests('delete_direct',gen_random_uuid(),jsonb_build_object('invoiceId',invoice_id,'expectedToken',c->>'token'));raise exception 'Settled invoice deleted';
 exception when sqlstate 'PT409'then null;end;
 assert exists(select 1 from transactions where id=invoice_id),'Blocked settlement deletion changed invoice';
end$$;
reset role;
set constraints all immediate;
rollback;
\echo PASS cash/credit invoice expenses, multi-payer installation cancellation, profit/cash separation, independent expenses and collections retained, audit/history, failure rollback, duplicate approval, role isolation, legacy paid-ledger correction and settled-source guard
