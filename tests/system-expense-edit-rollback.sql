begin;
insert into profiles(id,display_name,is_admin,user_type,permissions,phone)values
('00000000-0000-0000-0000-000000003790','مدير تصحيح المصاريف',true,'admin_staff','{}','07701234567'),
('00000000-0000-0000-0000-000000003791','صاحب المنظومة',false,'admin_staff','{"system":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003792','مستخدم آخر',false,'admin_staff','{"system":true,"installations":true,"cash":true}','07701234567'),
('00000000-0000-0000-0000-000000003793','مهندس',false,'installer','{"installations":true}','07701234567');
insert into customers(id,name,customer_type,owner_id)values(-379101,'عميل تصحيح المصاريف','system','00000000-0000-0000-0000-000000003791');
insert into products(id,code,name,qty,cost)values(-379101,'EXP-379-A','مادة أ',10,100000),(-379102,'EXP-379-B','مادة ب',10,200000);
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type)values('00000000-0000-0000-0000-000000003790','00000000-0000-0000-0000-000000003790',2000000,'transfer_in'),('00000000-0000-0000-0000-000000003791','00000000-0000-0000-0000-000000003790',1000000,'transfer_in');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003791',true);
set local role authenticated;
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),'{"kind":"system","mode":"credit","party":"عميل تصحيح المصاريف","total":2000000,"customerAddress":"بغداد","installerId":"00000000-0000-0000-0000-000000003793","items":[{"id":-379101,"qty":1,"price":0}]}');perform set_config('test.expense_invoice',r->>'id',true);
end$$;
reset role;
update transactions set warehouse_status='ready' where id=current_setting('test.expense_invoice')::bigint;
set local role authenticated;
do $$declare j transactions;begin
 select * into j from transactions where id=current_setting('test.expense_invoice')::bigint;perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":479000}');
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003790',true);
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'close','{"amount":600000}');
 select * into j from transactions where id=j.id;perform public.solar_installation_action(j.id,j.installation_revision,'reopen');
end$$;
-- Only this user's own invoices can be edited, even when an amount is supplied.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003792',true);
do $$declare j transactions;begin
 begin perform public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','invoiceId',current_setting('test.expense_invoice')::bigint,'approvedInstallationExpenses',0,'items','[{"id":-379101,"qty":1,"price":0}]'::jsonb));raise exception 'Cross-owner expense edit';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003790',true);
do $$declare j transactions;p jsonb;r jsonb;nonce uuid:=gen_random_uuid();balance_before numeric;hash_before text;begin
 select * into j from transactions where id=current_setting('test.expense_invoice')::bigint;
 p:=jsonb_build_object('kind','system','mode','credit','invoiceId',j.id,'expectedRevision',j.pricing_revision,'expectedInstallationRevision',j.installation_revision,'party','عميل تصحيح المصاريف','customerAddress','بغداد','installerId',j.installer_id,'total',2500000,'approvedInstallationExpenses',100000,'items','[{"id":-379101,"qty":2,"price":0},{"id":-379102,"qty":1,"price":0}]'::jsonb);
 r:=public.solar_invoice_save(nonce,p);assert public.solar_invoice_save(nonce,p)=r,'Replay response mismatch';
 select * into j from transactions where id=j.id;
 assert j.installation_expenses=100000 and j.profit=2000000,j::text;
 assert (r->>'profit')::numeric=j.profit and (r->>'installationExpenses')::numeric=100000;
 assert (select -sum(delta)from solar_cash_entries where job_id=j.id and owner_id='00000000-0000-0000-0000-000000003791')=100000;
 assert (select sum(delta)from solar_cash_entries where job_id=j.id and owner_id='00000000-0000-0000-0000-000000003790')=0;
 assert (select qty from products where id=-379101)=8 and (select qty from products where id=-379102)=9;
 assert (select count(*)from transactions where party_id=-379101)=1;
 perform set_config('test.expense_edit_nonce',nonce::text,true);
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'Stale edit accepted';exception when sqlstate 'PT409' then null;end;
 -- A failed cash increase must roll back items, total, balances and request cache.
 p:=p||jsonb_build_object('expectedRevision',j.pricing_revision,'expectedInstallationRevision',j.installation_revision,'total',3000000,'approvedInstallationExpenses',9000000);
 begin perform public.solar_invoice_save(gen_random_uuid(),p);raise exception 'Insufficient cash accepted';exception when sqlstate 'P0002' then null;end;
 assert (select total from transactions where id=j.id)=2500000;
 assert (select qty from products where id=-379101)=8;
 assert (select -sum(delta)from solar_cash_entries where job_id=j.id)=100000;
 -- Cancelling expenses doesn't close the installation, and refunds only once.
 perform public.solar_installation_action(j.id,j.installation_revision,'clear_expenses','{"notes":"إلغاء المصاريف للتصحيح"}');
 assert (select installation_expenses from transactions where id=j.id)=0;
 assert (select -sum(delta)from solar_cash_entries where job_id=j.id)=0;
 assert (select profit from transactions where id=j.id)=2100000;
 begin perform public.solar_installation_action(j.id,j.installation_revision,'clear_expenses');raise exception 'Stale cancellation accepted';exception when sqlstate 'PT409' then null;end;
 assert (select -sum(delta)from solar_cash_entries where job_id=j.id)=0;
end$$;
reset role;
do $$begin assert (select (after_row->>'installation_expenses')::numeric from solar_private.receipt_change_audit where request_id=current_setting('test.expense_edit_nonce')::uuid)=100000;end$$;
-- Simulate a legacy cancellation where the approved value was zeroed but
-- its cash effect survived. Even saving zero again must reverse that effect.
insert into solar_cash_entries(owner_id,actor_id,delta,entry_type,job_id,notes)values('00000000-0000-0000-0000-000000003791','00000000-0000-0000-0000-000000003790',-250000,'installation_payout',current_setting('test.expense_invoice')::bigint,'legacy orphan fixture');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003791',true);
do $$declare j transactions;r jsonb;begin
 select * into j from transactions where id=current_setting('test.expense_invoice')::bigint;
 r:=public.solar_invoice_save(gen_random_uuid(),jsonb_build_object('kind','system','mode','credit','invoiceId',j.id,'expectedRevision',j.pricing_revision,'expectedInstallationRevision',j.installation_revision,'party','عميل تصحيح المصاريف','customerAddress','بغداد','installerId',j.installer_id,'total',j.total,'approvedInstallationExpenses',0,'items','[{"id":-379101,"qty":2,"price":0},{"id":-379102,"qty":1,"price":0}]'::jsonb));
 assert (r->>'installationPaidExpenses')::numeric=0;
 assert (select sum(delta)from solar_cash_entries where job_id=j.id)=0;

end$$;
reset role;
do $$begin assert (select qty from products where id=-379101)=8;end$$;
rollback;
