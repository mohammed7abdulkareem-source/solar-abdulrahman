begin;
select set_config('v314.admin',(select id::text from public.profiles where active and is_admin and user_type<>'installer' limit 1),true);
select set_config('v314.purchase',coalesce((select last_number from solar_private.receipt_counters where kind='purchase'),0)::text,true);
select set_config('v314.payment',coalesce((select last_number from solar_private.receipt_counters where kind='customer_payment'),0)::text,true);
insert into public.transactions(id,kind,receipt_no,total,created_by,cashbox_user_id) values(-963001,'purchase',999,10,current_setting('v314.admin')::uuid,current_setting('v314.admin')::uuid),(-963002,'customer_payment',999,10,current_setting('v314.admin')::uuid,current_setting('v314.admin')::uuid);
do $$ begin
 if (select receipt_no from public.transactions where id=-963001)<>current_setting('v314.purchase')::bigint+1 then raise exception 'FAIL purchase numbering';end if;
 if (select receipt_no from public.transactions where id=-963002)<>current_setting('v314.payment')::bigint+1 then raise exception 'FAIL separate payment numbering';end if;
end $$;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v314.admin'),true);
do $$ declare response jsonb; begin
 response:=public.solar_save_rows_with_receipts(jsonb_build_array(jsonb_build_object('table','transactions','rows',jsonb_build_array(jsonb_build_object('id',-963001,'kind','purchase','total',20,'receipt_no',999,'created_by',auth.uid(),'cashbox_user_id',auth.uid())))));
 if (response->0->>'receiptNo')::bigint<>current_setting('v314.purchase')::bigint+1 then raise exception 'FAIL upsert changed number or no returned receipt';end if;
 if not exists(select 1 from public.transactions where id=-963001 and total=20) then raise exception 'FAIL saved edit';end if;
end $$;
reset role;
delete from public.transactions where id=-963001;
insert into public.transactions(id,kind,total) values(-963003,'purchase',30);
do $$ begin
 if (select receipt_no from public.transactions where id=-963003)<>current_setting('v314.purchase')::bigint+2 then raise exception 'FAIL deleted number reused or edit skipped number';end if;
end $$;
insert into solar_private.reset_record_ids(table_name,record_id) values('transactions',-963009);
do $$ begin
 begin insert into public.transactions(id,kind,total) values(-963009,'purchase',10);raise exception 'FAIL stale reset row returned';exception when serialization_failure then null;end;
end $$;
rollback;
