begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000002131','مستلم',false,'{"systemPayment":true,"deletionRequests":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000002132','مستلم آخر',false,'{"systemPayment":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000002133','أدمن',true,'{}','admin_staff');
insert into public.customers(id,name,customer_type,owner_id) values
 (-213101,'حساب اختبار التصحيح','system','00000000-0000-0000-0000-000000002131');
insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values
 (-213101,'system','customer',-213101,'حساب اختبار التصحيح',650,false,'credit','00000000-0000-0000-0000-000000002131','00000000-0000-0000-0000-000000002131'),
 (-213102,'system_payment','customer',-213101,'حساب اختبار التصحيح',-400,false,'opening_balance','00000000-0000-0000-0000-000000002131','00000000-0000-0000-0000-000000002131'),
 (-213104,'system_payment','customer',-213101,'حساب اختبار التصحيح',25,true,'payment','00000000-0000-0000-0000-000000002132','00000000-0000-0000-0000-000000002131');
insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id,system_invoice_id) values
 (-213105,'system','customer',-213101,'حساب اختبار التصحيح',200,false,'credit','00000000-0000-0000-0000-000000002133','00000000-0000-0000-0000-000000002133',null),
 (-213106,'system_payment','customer',-213101,'حساب اختبار التصحيح',30,true,'payment','00000000-0000-0000-0000-000000002131','00000000-0000-0000-0000-000000002131',-213105);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002131',true);
do $$
declare account jsonb; creation jsonb; payload jsonb; saved jsonb; ctx jsonb; revised jsonb; req uuid:=gen_random_uuid(); create_id uuid:=gen_random_uuid(); tid bigint; linked bigint:=-213101;
 before_cash numeric; before_balance numeric; charge jsonb; charge_context jsonb; linked_before numeric; delete_context jsonb; decision jsonb;
begin
 account:=public.solar_system_payment_context(linked);
 creation:=jsonb_build_object('customerId',linked,'invoiceId',linked,'mode','payment','amount',110,'expectedToken',account->>'token');
 saved:=public.solar_system_payment_save(create_id,creation);
 tid:=(saved->>'id')::bigint;
 ctx:=public.solar_statement_system_payment('get',null,jsonb_build_object('id',tid));
 before_cash:=(ctx->>'cashBalance')::numeric; before_balance:=(ctx->>'balance')::numeric;
 payload:=jsonb_build_object('id',tid,'amount',145,'expectedToken',ctx->>'token','notes','تصحيح');
 revised:=public.solar_statement_system_payment('update',req,payload);
 if revised is distinct from public.solar_statement_system_payment('update',req,payload)
  or (revised->>'remaining')::numeric<>before_balance-35 or (revised->>'cashAfter')::numeric<>before_cash+35 then
  raise exception 'wrong cash/receivable/deduplication';
 end if;
 ctx:=public.solar_statement_system_payment('get',null,jsonb_build_object('id',tid));
 if ctx->>'notes'<>'تصحيح' or ctx->>'date' is distinct from saved->>'date' or ctx->>'receiptNo' is distinct from saved->>'receiptNo' then raise exception 'receipt identity changed'; end if;
 begin perform public.solar_system_payment_save(create_id,creation);raise exception 'accepted stale creation receipt';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_statement_system_payment('update',gen_random_uuid(),payload);raise exception 'accepted stale account';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_statement_system_payment('get',null,'{"id":-213104}');raise exception 'foreign receipt shown to cashier';exception when insufficient_privilege then null;end;
 begin perform public.solar_receipt_delete_requests('context',null,'{"invoiceId":-213104}');raise exception 'delete preview exposed foreign receipt';exception when insufficient_privilege then null;end;
 delete_context:=public.solar_receipt_delete_requests('context',null,'{"invoiceId":-213106}');
 if delete_context#>>'{invoice,system_invoice_id}' is not null then raise exception 'delete preview exposed foreign allocation';end if;
 decision:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',-213106,'expectedToken',delete_context->>'token'));
 delete_context:=public.solar_receipt_delete_requests('get',(decision->>'id')::uuid,'{}');
 if delete_context#>>'{snapshot,invoice,system_invoice_id}' is not null or delete_context#>>'{current,invoice,system_invoice_id}' is not null then raise exception 'delete request exposed foreign allocation';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002133',true);
 delete_context:=public.solar_receipt_delete_requests('get',(decision->>'id')::uuid,'{}');
 if delete_context#>>'{snapshot,invoice,system_invoice_id}' is distinct from '-213105' then raise exception 'missing original audit allocation';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002131',true);
 begin perform public.solar_statement_system_payment('get',null,'{"id":-213102}');raise exception 'opening balance editable';exception when insufficient_privilege then null;end;
 begin
  perform public.solar_statement_system_payment('update',gen_random_uuid(),payload||jsonb_build_object('amount',750,'expectedToken',ctx->>'token'));
  raise exception 'accepted overpaid linked invoice';
 exception when raise_exception then if sqlerrm not like '%المنظومة المرتبطة%' then raise; end if; end;
 account:=public.solar_system_payment_context(linked);
 select (x->>'remaining')::numeric into linked_before from jsonb_array_elements(account->'systems') x where (x->>'id')::bigint=linked;
 if linked_before<>505 then raise exception 'invoice allocation changed';end if;
 charge:=public.solar_system_payment_save(gen_random_uuid(),jsonb_build_object('customerId',linked,'mode','charge_other','amount',90,'notes','نقل','expectedToken',account->>'token'));
 charge_context:=public.solar_statement_system_payment('get',null,jsonb_build_object('id',(charge->>'id')::bigint));
 revised:=public.solar_statement_system_payment('update',gen_random_uuid(),jsonb_build_object('id',(charge->>'id')::bigint,'expectedToken',charge_context->>'token','amount',70,'notes','نقل'));
 if (revised->>'cashAfter')::numeric<>(charge_context->>'cashBalance')::numeric or (revised->>'remaining')::numeric<>(charge_context->>'balance')::numeric-20 then raise exception 'noncash charge posted cash';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002132',true);
 begin perform public.solar_statement_system_payment('update',req,payload);raise exception 'replayed foreign request';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002131',true);
 delete_context:=public.solar_receipt_delete_requests('context',null,jsonb_build_object('invoiceId',tid));
 decision:=public.solar_receipt_delete_requests('request',gen_random_uuid(),jsonb_build_object('invoiceId',tid,'expectedToken',delete_context->>'token'));
 if decision->>'status' is distinct from 'pending' or (public.solar_statement_system_payment('get',null,jsonb_build_object('id',tid))->>'total')::numeric<>145 then raise exception 'deletion request changed receipt before approval';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002133',true);
 delete_context:=public.solar_receipt_delete_requests('get',(decision->>'id')::uuid,'{}');
 decision:=public.solar_receipt_delete_requests('approve',(decision->>'id')::uuid,jsonb_build_object('expectedToken',delete_context->>'reviewToken'));
 if decision->>'status' is distinct from 'approved' then raise exception 'payment approval failed';end if;
 account:=public.solar_system_payment_context(linked);
 select (x->>'remaining')::numeric into linked_before from jsonb_array_elements(account->'systems') x where (x->>'id')::bigint=linked;
 if linked_before<>650 or (account->>'balance')::numeric<>(revised->>'remaining')::numeric+145 then raise exception 'delete did not restore invoice allocation and account balance';end if;
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000002131',true);
 if (public.solar_system_payment_context(linked)->>'cashBalance')::numeric<>before_cash-110 then raise exception 'delete did not restore original cashier';end if;
end $$;
reset role;
do $$begin
 if (select count(*) from solar_private.receipt_change_audit where action='system_payment_update' and actor_id='00000000-0000-0000-0000-000000002131')<>2 then raise exception 'wrong audit count';end if;
 if has_function_privilege('anon','public.solar_statement_system_payment(text,uuid,jsonb)','execute') or has_function_privilege('authenticated','solar_private.statement_payment_editable(public.transactions,public.customers,public.profiles)','execute') then raise exception 'unexpected grant';end if;
end $$;
rollback;
