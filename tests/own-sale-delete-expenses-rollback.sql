begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003830','مدير حذف الوصل',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003831','صاحب الوصل',false,'admin_staff','{"system":true,"installations":true,"systemPayment":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003832','مستخدم آخر',false,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003833','مخزن',true,'warehouse','{"salesDeleteOwn":true}','07701234567'),
('00000000-0000-0000-0000-000000003834','مهندس',true,'installer','{"salesDeleteOwn":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values(-383001,'عميل حذف الوصل','system','00000000-0000-0000-0000-000000003831');
insert into products(id,code,name,qty,cost)values(-383001,'VOID-383','مادة الوصل المحذوف',10,100000);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)values(1,-383001,10)on conflict(warehouse_id,product_id)do update set qty=excluded.qty;
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,created_at)values
('00000000-0000-0000-0000-000000003830','00000000-0000-0000-0000-000000003830',2000000,'transfer_in','2026-09-30T12:00Z'),
('00000000-0000-0000-0000-000000003831','00000000-0000-0000-0000-000000003830',1000000,'transfer_in','2026-09-30T12:00Z');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-383001,"party":"عميل حذف الوصل","total":3000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003834","warranty":{"enabled":true,"items":[{"id":-383001,"duration":12,"unit":"months"}],"maintenance":{"duration":0,"unit":"months"}},"items":[{"id":-383001,"qty":2,"price":0}]}');
 perform set_config('test.delete.main',r->>'id',true);
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","partyId":-383001,"party":"عميل حذف الوصل","total":1000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003834","items":[{"id":-383001,"qty":1,"price":0}]}');
 perform set_config('test.delete.orphan',r->>'id',true);
end$$;
reset role;
update transactions set warehouse_status='ready'where id=current_setting('test.delete.main')::bigint;
set local role authenticated;
do $$declare j transactions;c jsonb;begin
 select * into j from transactions where id=current_setting('test.delete.main')::bigint;
 perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":479000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003830',true);
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":600000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003831',true);
 c:=public.solar_system_payment_context(-383001);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-383001,'invoiceId',j.id,'amount',100000,'mode','payment','expectedToken',c->>'token'));
end$$;
reset role;
update solar_cash_entries set created_at=case when owner_id='00000000-0000-0000-0000-000000003831'then '2026-10-01T12:00Z'::timestamptz else '2026-10-02T12:00Z'::timestamptz end where job_id=current_setting('test.delete.main')::bigint;
update profiles set permissions='{"cash":true,"systemPayment":true,"salesDeleteOwn":false}'where id='00000000-0000-0000-0000-000000003831';
insert into transactions(id,kind,party_name,total,created_by)values(-383999,'sale','وصل المستخدم الآخر',500,'00000000-0000-0000-0000-000000003832');
-- Browser fixtures commit this setup section; SQL scenarios always roll back.
create function pg_temp.reject_fixture_delete()returns trigger language plpgsql as $$begin if old.id=current_setting('test.delete.main')::bigint then raise exception 'fixture downstream failure';end if;return old;end$$;
create trigger reject_fixture_delete before delete on transactions for each row execute function pg_temp.reject_fixture_delete();
set local role authenticated;
do $$declare p jsonb;b numeric;begin
 b:=solar_private.cash_balance(auth.uid());p:=public.solar_sale_delete_preview(current_setting('test.delete.main')::bigint);
 begin perform public.solar_sale_delete(current_setting('test.delete.main')::bigint,p->>'token');raise exception 'Rollback fixture did not fail';exception when raise_exception then if sqlerrm<>'fixture downstream failure' then raise;end if;end;
 assert solar_private.cash_balance(auth.uid())=b;
 assert exists(select 1 from transactions where id=current_setting('test.delete.main')::bigint);
 assert exists(select 1 from transactions where system_invoice_id=current_setting('test.delete.main')::bigint);
end$$;
reset role;
drop trigger reject_fixture_delete on transactions;
do $$begin assert not exists(select 1 from solar_private.deleted_sales where invoice_id=current_setting('test.delete.main')::bigint);end$$;
set local role authenticated;
do $$declare p jsonb;c jsonb;j transactions;before_cash numeric;admin_cash numeric;before_stock numeric;entry_id text;detail jsonb;statement jsonb;token text;begin
 select * into j from transactions where id=current_setting('test.delete.main')::bigint;
 assert solar_private.can_delete_sale(auth.uid());assert not solar_private.can_delete_sale('00000000-0000-0000-0000-000000003832');
 p:=public.solar_sales_history_by_user(null);assert(p->>'count')::integer=2;assert not exists(select 1 from jsonb_array_elements(p->'rows')x where x->>'canDelete'<>'true');
 assert(public.solar_sales_period_by_user(null)->'summary'->>'invoiceCount')::integer=2;
 begin perform public.solar_sale_delete_preview(-383999);raise exception 'Cross-owner preview';exception when insufficient_privilege then null;end;
 begin delete from transactions where id=j.id;raise exception 'Raw deletion accepted';exception when insufficient_privilege then null;end;
 p:=public.solar_sale_delete_preview(j.id);assert p->>'blockedReason' is null,p::text;
 assert(p->>'expenseRefund')::numeric=600000 and jsonb_array_length(p->'expenseRefunds')=2;
 assert(p->>'retainedPayments')::integer=1;
 -- A new linked receipt invalidates an already-confirmed deletion preview.
 c:=public.solar_system_payment_context(-383001);
 perform public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-383001,'invoiceId',j.id,'amount',10000,'mode','payment','expectedToken',c->>'token'));
 begin perform public.solar_sale_delete(j.id,p->>'token');raise exception 'Stale preview accepted';exception when sqlstate 'PT409' then null;end;
 before_cash:=solar_private.cash_balance(auth.uid());admin_cash:=solar_private.cash_balance('00000000-0000-0000-0000-000000003830');
 select qty into before_stock from products where id=-383001;
 statement:=public.solar_cash_statement(auth.uid(),'2026-10-01','2026-10-27','IQD');
 perform set_config('test.delete.pastClosing',statement->'ledgers'->0->>'closing',true);
 select 'entry:'||id into entry_id from solar_cash_entries where job_id=j.id and owner_id=auth.uid();
 token:=j.warranty_token::text;
 p:=public.solar_sale_delete_preview(j.id);perform public.solar_sale_delete(j.id,p->>'token');perform public.solar_sale_delete(j.id,p->>'token');
 assert not exists(select 1 from transactions where id=j.id);
 assert not exists(select 1 from transaction_items where transaction_id=j.id);
 assert solar_private.cash_balance(auth.uid())=before_cash+479000;
 assert solar_private.cash_balance('00000000-0000-0000-0000-000000003830')=admin_cash+121000;
 assert(select count(*)from transactions where kind='system_payment'and party_id=-383001)=2;
 assert not exists(select 1 from transactions where system_invoice_id=j.id);
 c:=public.solar_system_payment_context(-383001);assert(c->>'balance')::numeric=890000;
 assert(select sum(delta)from solar_cash_entries where deleted_job_id=j.id)=0;
 assert(select count(*)from solar_cash_entries where deleted_job_id=j.id)=2;
 detail:=public.solar_cash_movement_detail(entry_id);assert(detail->'document'->>'deleted')::boolean;assert(detail->>'party')='عميل حذف الوصل';assert(detail->>'receiptNo')::bigint=j.receipt_no;
 statement:=public.solar_cash_statement(auth.uid(),'2026-10-01','2026-10-27','IQD');assert(statement->'ledgers'->0->>'closing')=current_setting('test.delete.pastClosing'),'Past period changed';
 statement:=public.solar_cash_statement(auth.uid(),'2026-10-01','2026-10-29','IQD');
 assert exists(select 1 from jsonb_array_elements(statement->'ledgers'->0->'rows')r where(r->>'invoice_deleted')::boolean and(r->>'current_paid')::numeric=0 and(r->>'current_expenses')::numeric=0);
 assert(public.solar_warranty_verify(token::uuid)->>'voided')::boolean;
 perform set_config('test.delete.receipt',j.receipt_no::text,true);
end$$;
reset role;
do $$begin assert(select qty from products where id=-383001)=9;assert(select qty from solar_private.warehouse_stocks where warehouse_id=1 and product_id=-383001)=9;assert(select count(*)from solar_cash_entries where deleted_job_id=current_setting('test.delete.main')::bigint)=4;end$$;
-- Correct legacy approved=0 / paid>0 records when the owner deletes the invoice.
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,job_id)values('00000000-0000-0000-0000-000000003831','00000000-0000-0000-0000-000000003830',-250000,'installation_payout',current_setting('test.delete.orphan')::bigint);
set local role authenticated;
do $$declare p jsonb;before_cash numeric;begin
 before_cash:=solar_private.cash_balance(auth.uid());p:=public.solar_sale_delete_preview(current_setting('test.delete.orphan')::bigint);assert(p->>'expenseRefund')::numeric=250000;
 perform public.solar_sale_delete(current_setting('test.delete.orphan')::bigint,p->>'token');
 assert solar_private.cash_balance(auth.uid())=before_cash+250000;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003832',true);
do $$begin begin perform public.solar_sale_delete(current_setting('test.delete.main')::bigint,'ignored');raise exception 'Cross-owner archived deletion';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003833',true);
do $$begin begin perform public.solar_sale_delete_preview(-383999);raise exception 'Warehouse permission leak';exception when insufficient_privilege then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003834',true);
do $$begin begin perform public.solar_sale_delete_preview(-383999);raise exception 'Engineer permission leak';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin assert(select qty from products where id=-383001)=10;end$$;
-- An actual cash receipt reversal may make the owner's box negative.
update transactions set total=500000,subtotal=500000,cash=true where id=-383999;
insert into transactions(id,kind,total,cash,created_by,cashbox_user_id)values(-383998,'cash_expense',1000000,true,'00000000-0000-0000-0000-000000003832','00000000-0000-0000-0000-000000003832');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003832',true);
set local role authenticated;
do $$declare p jsonb;begin
 assert solar_private.cash_balance(auth.uid())=-500000;
 p:=public.solar_sale_delete_preview(-383999);assert p->>'blockedReason' is null;
 perform public.solar_sale_delete(-383999,p->>'token');assert solar_private.cash_balance(auth.uid())=-1000000;
end$$;
reset role;
-- Distributed profits must be reviewed before their invoice can be deleted.
insert into transactions(id,kind,total,created_by)values(-383997,'sale',100000,'00000000-0000-0000-0000-000000003832');
insert into solar_private.profit_settlements(id,owner_id,date_to,snapshot,profit,status,share,receipt)values('00000000-0000-0000-0000-000000003830','00000000-0000-0000-0000-000000003832','2026-10-28','{}',50000,'approved',50000,'{}');
update transactions set profit_supplier_settlement_id='00000000-0000-0000-0000-000000003830'where id=-383997;
set local role authenticated;
do $$declare p jsonb;begin
 p:=public.solar_sale_delete_preview(-383997);assert p->>'blockedReason' is not null;
 begin perform public.solar_sale_delete(-383997,p->>'token');raise exception 'Settled deletion accepted';exception when raise_exception then if sqlerrm='Settled deletion accepted' then raise;end if;end;
 assert exists(select 1 from transactions where id=-383997);
end$$;
reset role;
set constraints all immediate;
\echo PASS universal own-only deletion, original-payer expense refunds, ledger audit and period history, linked collections retained, warranty void, stale/replay protection, legacy orphan correction and role isolation
rollback;
