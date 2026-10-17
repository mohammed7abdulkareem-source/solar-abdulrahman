begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003410','مدير اختبار المنظومات',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003411','مستلم المنظومات',false,'{"systemPayment":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003412','مستلم آخر',false,'{"systemPayment":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003413','دون صلاحية',false,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003414','مهندس',true,'{}','installer');
insert into public.customers(id,name,phone,customer_type,owner_id) values
 (-341001,'كوبا كافي الاختبار','07701112223','system','00000000-0000-0000-0000-000000003411'),
 (-341002,'زبون لديه منظومتان','07801112223','system','00000000-0000-0000-0000-000000003411'),
 (-341003,'زبون لمستخدم آخر','','system','00000000-0000-0000-0000-000000003412'),
 (-341004,'زبون جملة','','wholesale','00000000-0000-0000-0000-000000003411');
insert into public.transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values
 (-341001,'system_payment',-341001,'كوبا كافي الاختبار',-18000000,false,'opening_balance','00000000-0000-0000-0000-000000003410','00000000-0000-0000-0000-000000003410'),
 (-341002,'system',-341002,'اسم الزبون قبل التعديل',3000000,false,'credit','00000000-0000-0000-0000-000000003410','00000000-0000-0000-0000-000000003410'),
 (-341003,'system',-341002,'زبون لديه منظومتان',2000000,false,'credit','00000000-0000-0000-0000-000000003411','00000000-0000-0000-0000-000000003411'),
 (-341004,'system',-341003,'زبون لمستخدم آخر',2000000,false,'credit','00000000-0000-0000-0000-000000003412','00000000-0000-0000-0000-000000003412');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003411',true);
do $$declare a jsonb;p jsonb;r jsonb;r2 jsonb;req uuid:=gen_random_uuid();tid bigint;begin
 a:=public.solar_system_payment_context();
 if jsonb_array_length(a->'customers')<>2 then raise exception 'FAIL permission-scoped directory';end if;
 a:=public.solar_system_payment_context(-341001);
 if(a->>'balance')::numeric<>18000000 or jsonb_array_length(a->'systems')<>0 then raise exception 'FAIL opening-only context';end if;
 p:=jsonb_build_object('customerId',-341001,'invoiceId',null,'amount',1500000,'mode','payment','notes','بيد المستلم','expectedToken',a->>'token');
 r:=public.solar_system_payment_save(req,p);tid:=(r->>'id')::bigint;
 if(r->>'remaining')::numeric<>16500000 or(r->>'cashAfter')::numeric<>1500000 or r->>'systemInvoiceId' is not null or r->>'receiptNo' is null then raise exception 'FAIL opening payment and cash: %',r;end if;
 r2:=public.solar_system_payment_save(req,p);if r<>r2 or(public.solar_system_payment_context(-341001)->>'cashBalance')::numeric<>1500000 then raise exception 'FAIL exact retry duplicates';end if;
 begin perform public.solar_system_payment_save(gen_random_uuid(),p);raise exception 'FAIL stale balance token';exception when serialization_failure then null;end;
 begin update public.transactions set total=1 where id=tid;raise exception 'FAIL raw payment update';exception when insufficient_privilege then null;end;
 begin delete from public.transactions where id=tid;raise exception 'FAIL raw payment delete';exception when insufficient_privilege then null;end;
 a:=public.solar_system_payment_context(-341001);
 p:=jsonb_build_object('customerId',-341001,'invoiceId',null,'amount',250000,'mode','charge_old_balance','notes','إضافة قديمة موثقة','expectedToken',a->>'token');
 r:=public.solar_system_payment_save(gen_random_uuid(),p);
 if(r->>'remaining')::numeric<>16750000 or(r->>'cashAfter')::numeric<>1500000 or(r->>'cash')::boolean then raise exception 'FAIL noncash charge';end if;
 a:=public.solar_system_payment_context(-341002);
 if jsonb_array_length(a->'systems')<>2 then raise exception 'FAIL another creator or renamed customer invoice hidden';end if;
 p:=jsonb_build_object('customerId',-341002,'invoiceId',-341002,'amount',1000000,'mode','payment','notes','','expectedToken',a->>'token');
 r:=public.solar_system_payment_save(gen_random_uuid(),p);
 if(r->>'invoiceBefore')::numeric<>3000000 or(r->>'invoiceAfter')::numeric<>2000000 or(r->>'remaining')::numeric<>4000000 then raise exception 'FAIL invoice allocation';end if;
 a:=public.solar_system_payment_context(-341002);
 if not exists(select 1 from jsonb_array_elements(a->'systems') x where x->>'id'='-341002' and(x->>'paid')::numeric=1000000 and(x->>'remaining')::numeric=2000000) then raise exception 'FAIL persistent allocation after reload';end if;
 begin perform public.solar_system_payment_save(gen_random_uuid(),p||jsonb_build_object('amount',2500000,'expectedToken',a->>'token'));raise exception 'FAIL invoice overpayment';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_system_payment_save(gen_random_uuid(),p||jsonb_build_object('invoiceId',-341004,'expectedToken',a->>'token'));raise exception 'FAIL foreign invoice';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_system_payment_save(gen_random_uuid(),p||jsonb_build_object('amount',0.001,'expectedToken',a->>'token'));raise exception 'FAIL fractional amount';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_system_payment_save(gen_random_uuid(),p||jsonb_build_object('mode','charge_other','expectedToken',a->>'token'));raise exception 'FAIL charge without notes';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_system_payment_context(-341003);raise exception 'FAIL foreign customer';exception when insufficient_privilege then null;end;
 begin perform public.solar_system_payment_context(-341004);raise exception 'FAIL wrong category';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003413',true);
do $$begin begin perform public.solar_system_payment_context();raise exception 'FAIL missing permission';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003414',true);
do $$begin begin perform public.solar_system_payment_context();raise exception 'FAIL installer admin flag';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$declare l jsonb;begin
 if(select count(*) from solar_private.system_payment_requests)<>3 then raise exception 'FAIL receipt/audit count';end if;
 if not exists(select 1 from public.transactions where system_invoice_id=-341002 and kind='system_payment' and total=1000000 and party_id=-341002) then raise exception 'FAIL stored customer/invoice IDs';end if;
 l:=solar_private.customer_ledger(-341002);
 if not exists(select 1 from jsonb_array_elements(l) x where x->>'systemInvoiceId'='-341002' and x->>'systemReceiptNo' is not null) then raise exception 'FAIL statement allocation label';end if;
 if has_function_privilege('anon','public.solar_system_payment_save(uuid,jsonb)','execute') or has_table_privilege('authenticated','solar_private.system_payment_requests','insert') then raise exception 'FAIL RPC grants';end if;
end $$;
-- The existing reset deletes transactions in one statement; optional self-FKs
-- must allow that statement while rejecting deletion of just a paid invoice.
delete from public.transactions;
do $$begin if exists(select 1 from public.transactions) then raise exception 'FAIL clearing allocated receipts with invoices';end if;end $$;
select 'PASS opening-only payments, invoice allocation/reload, cash, charges, exact retry, stale/overpayment and permissions' result;
rollback;
