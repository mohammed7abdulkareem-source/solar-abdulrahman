begin;
insert into public.profiles(id,display_name,is_admin,permissions,user_type) values
 ('00000000-0000-0000-0000-000000003340','مدير المورد',true,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003341','موظف المورد',false,'{"supplierPayment":true,"supplierStatement":true,"supplierBalances":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003342','موظف ثان',false,'{"supplierPayment":true}','admin_staff'),
 ('00000000-0000-0000-0000-000000003343','بلا صلاحيات',false,'{}','admin_staff'),
 ('00000000-0000-0000-0000-000000003344','مخزن',true,'{}','warehouse');
insert into public.suppliers(id,name) values(-334001,'مورد الإضافات');
insert into public.transactions(id,kind,party_type,party_id,party_name,total,cash,created_by,cashbox_user_id)
 values(-334001,'purchase','supplier',-334001,'مورد الإضافات',100000,false,'00000000-0000-0000-0000-000000003341','00000000-0000-0000-0000-000000003341');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003341',true);
do $$declare r jsonb;a jsonb;token text;begin
 a:=public.solar_supplier_account(-334001);
 if (a->>'cashBalance')::numeric<>0 or (a->>'balance')::numeric<>100000 then raise exception 'FAIL initial account';end if;
 r:=public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334001',-334002,-334001,20000,'charge_old_balance','حساب قديم');
 if (r->>'total')::numeric<>-20000 or (r->>'cash')::boolean or (r->>'afterBalance')::numeric<>120000 or (r->>'cashAfter')::numeric<>0 then raise exception 'FAIL zero-cash non-cash charge';end if;
 if r->>'receiptNo' is null then raise exception 'FAIL missing charge receipt';end if;
 a:=public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334001',-334002,-334001,20000,'charge_old_balance','حساب قديم');
 if a is distinct from r or (public.solar_supplier_account(-334001)->>'balance')::numeric<>120000 then raise exception 'FAIL duplicate charge retry';end if;
 token:=r->>'token';
 r:=public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334002',-334002,-334001,30000,'charge_extra_expense','تصحيح المصروف',token);
 if (r->>'afterBalance')::numeric<>130000 or (public.solar_supplier_account(-334001)->>'cashBalance')::numeric<>0 then raise exception 'FAIL charge edit';end if;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334003',-334002,-334001,40000,'charge_other','تعديل قديم',token);raise exception 'FAIL stale charge edit';exception when serialization_failure then null;end;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334004',-334003,-334001,1000,'cash','');raise exception 'FAIL cash payment with empty cashbox';exception when no_data_found then null;end;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334005',-334004,-334001,1000,'charge_other','');raise exception 'FAIL missing charge reason';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334006',-334004,-334001,-1000,'charge_other','سبب');raise exception 'FAIL negative input';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334007',-334004,-334001,1.001,'charge_other','سبب');raise exception 'FAIL fractional precision';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 begin update public.transactions set total=-100000 where id=-334002;raise exception 'FAIL raw charge update';exception when insufficient_privilege then null;end;
end $$;
reset role;
insert into public.solar_cash_entries(owner_id,delta,entry_type,actor_id) values('00000000-0000-0000-0000-000000003341',50000,'test_funding','00000000-0000-0000-0000-000000003340');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003341',true);
do $$declare r jsonb;a jsonb;begin
 r:=public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334008',-334005,-334001,10000,'cash','تسديد نقدي');
 if not(r->>'cash')::boolean or (r->>'total')::numeric<>10000 then raise exception 'FAIL normal cash payment';end if;
 a:=public.solar_supplier_account(-334001);
 if (a->>'balance')::numeric<>120000 or (a->>'cashBalance')::numeric<>40000 then raise exception 'FAIL payment debt/cash effects';end if;
 begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334009',-334005,-334001,10000,'charge_other','تحويل ممنوع',r->>'token');raise exception 'FAIL changing receipt direction';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 r:=public.solar_supplier_payment_get(-334002);
 begin perform public.solar_supplier_payment_save('00000000-0000-0000-0000-000000334010',-334002,-334001,1000,'واجهة قديمة',r->>'token');raise exception 'FAIL old cash API converting charge';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
 a:=public.solar_party_balances('suppliers',(now() at time zone 'Asia/Baghdad')::date);
 if (a->'rows'->0->>'balance')::numeric<>120000 or (a->'rows'->0->>'last_payment')::numeric<>10000 then raise exception 'FAIL supplier report charge/payment effects';end if;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003342',true);
do $$begin
 if (public.solar_supplier_account(-334001)->>'balance')::numeric<>0 then raise exception 'FAIL supplier owner scope';end if;
 begin perform public.solar_supplier_payment_get(-334002);raise exception 'FAIL another owner charge access';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003343',true);
do $$begin begin perform public.solar_supplier_movement_save('00000000-0000-0000-0000-000000334011',-334006,-334001,1000,'charge_other','سبب');raise exception 'FAIL missing permission';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003344',true);
do $$begin begin perform public.solar_supplier_account(-334001);raise exception 'FAIL warehouse account';exception when insufficient_privilege then null;end;end $$;
reset role;
do $$begin
 if (select count(*) from solar_private.supplier_payment_requests)<>3 then raise exception 'FAIL immutable audit request count';end if;
 if not exists(select 1 from solar_private.supplier_payment_requests where before_row->>'total'='-20000') then raise exception 'FAIL edit audit';end if;
 if has_function_privilege('anon','public.solar_supplier_movement_save(uuid,bigint,bigint,numeric,text,text,text)','EXECUTE') then raise exception 'FAIL anonymous access';end if;
end $$;
select 'PASS supplier charges, zero cashbox, cash payments, audit, edit/retry/stale protection and permissions' as result;
rollback;
