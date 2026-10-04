begin;
select set_config('v313.staff',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('v313.other',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' and id<>current_setting('v313.staff')::uuid order by created_at limit 1),true);
select set_config('v313.admin',(select id::text from public.profiles where active and is_admin and user_type<>'installer' limit 1),true);
select set_config('v313.engineer',(select id::text from public.profiles where active and user_type='installer' limit 1),true);
update public.profiles set permissions='{"supplierPayment":true,"supplierStatement":true,"cashTransferSend":true}' where id=current_setting('v313.staff')::uuid;
update public.profiles set permissions='{"supplierPayment":true,"supplierStatement":true}' where id=current_setting('v313.other')::uuid;
insert into public.suppliers(id,name) values(-951001,'TEST SUPPLIER 313');
insert into public.transactions(id,kind,total,cash) values(-951009,'supplier_payment',10,true);
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-951001,'cash_income',5000-solar_private.cash_balance(current_setting('v313.staff')::uuid),true,current_setting('v313.staff')::uuid,current_setting('v313.staff')::uuid);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v313.staff'),true);
do $$ declare r jsonb; updated jsonb; begin
 r:=public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095101',-951002,-951001,1000,'');
 if r->>'party'<>'TEST SUPPLIER 313' or (r->>'total')::numeric<>1000 then raise exception 'FAIL receipt';end if;
 perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095101',-951002,-951001,1000,'');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>4000 then raise exception 'FAIL duplicate debit';end if;
 updated:=public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095102',-951002,-951001,600,'edited',r->>'token');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>4400 then raise exception 'FAIL edited cash';end if;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095103',-951002,-951001,700,'',r->>'token');raise exception 'FAIL stale edit';exception when serialization_failure then null;end;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095104',-951002,-951001,6000,'',updated->>'token');raise exception 'FAIL overspend';exception when no_data_found then null;end;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095105',-951003,-951001,-10,'');raise exception 'FAIL negative amount';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin update public.transactions set total=0 where id=-951002;raise exception 'FAIL direct update';exception when insufficient_privilege then null;end;
 begin delete from public.transactions where id=-951002;raise exception 'FAIL direct delete';exception when insufficient_privilege then null;end;
 begin insert into public.transactions(id,kind,total,created_by,cashbox_user_id) values(-951003,'supplier_payment',10,auth.uid(),auth.uid());raise exception 'FAIL direct insert';exception when insufficient_privilege then null;end;
 begin perform 1 from solar_private.supplier_payment_requests;raise exception 'FAIL audit readable';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v313.other'),true);
do $$ begin
 begin perform public.solar_supplier_payment_get(-951002);raise exception 'FAIL other owner read';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_get(-951009);raise exception 'FAIL ownerless receipt read';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095106',-951002,-951001,500,'','fake');raise exception 'FAIL other owner edit';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v313.engineer'),true);
do $$ begin
 begin perform public.solar_supplier_payment_get(-951002);raise exception 'FAIL engineer read';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095107',-951003,-951001,100,'');raise exception 'FAIL engineer pay';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set permissions='{}' where id=current_setting('v313.staff')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v313.staff'),true);
do $$ begin
 begin perform public.solar_supplier_payment_get(-951002);raise exception 'FAIL missing permission read';exception when insufficient_privilege then null;end;
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095108',-951003,-951001,100,'');raise exception 'FAIL missing permission pay';exception when insufficient_privilege then null;end;
end $$;
reset role;
select set_config('v313.admin_balance',solar_private.cash_balance(current_setting('v313.admin')::uuid)::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v313.admin'),true);
do $$ declare r jsonb; begin
 r:=public.solar_supplier_payment_get(-951002);
 perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000095109',-951002,-951001,800,'admin edit',r->>'token');
end $$;
reset role;
do $$ begin
 if solar_private.cash_balance(current_setting('v313.staff')::uuid)<>4200 then raise exception 'FAIL wrong payer';end if;
 if solar_private.cash_balance(current_setting('v313.admin')::uuid)<>current_setting('v313.admin_balance')::numeric then raise exception 'FAIL admin cash changed';end if;
 if (select count(*) from solar_private.supplier_payment_requests where request_id::text like '%09510%')<>3 then raise exception 'FAIL audit count';end if;
 if (select created_by from public.transactions where id=-951002)<>current_setting('v313.staff')::uuid then raise exception 'FAIL owner overwritten';end if;
end $$;
rollback;
