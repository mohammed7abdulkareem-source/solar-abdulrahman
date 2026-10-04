begin;
select set_config('v312.staff',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('v312.other',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' and id<>current_setting('v312.staff')::uuid order by created_at limit 1),true);
select set_config('v312.engineer',(select id::text from public.profiles where active and user_type='installer' limit 1),true);
update public.profiles set permissions='{"salesDeleteOwn":true,"cashTransferSend":true,"financeReceive":true}' where id=current_setting('v312.staff')::uuid;
update public.profiles set permissions='{"financeReceive":true}' where id=current_setting('v312.other')::uuid;
insert into public.products(id,code,name,qty,cost) values(-941001,'TEST-DELETE-941001','TEST STOCK',10,20);
insert into public.transactions(id,kind,party_name,cash,total,created_by,cashbox_user_id,installer_id,installation_status) values
 (-941001,'sale','TEST CUSTOMER',true,100,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid,null,'none'),
 (-941002,'sale','OTHER CUSTOMER',false,100,current_setting('v312.other')::uuid,current_setting('v312.other')::uuid,null,'none'),
 (-941003,'system','TEST SYSTEM',false,500,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid,current_setting('v312.engineer')::uuid,'pending'),
 (-941004,'cash_income',null,true,1000,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid,null,'none'),
 (-941005,'customer_payment','TEST CUSTOMER',true,50,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid,null,'none');
insert into public.transaction_items(id,transaction_id,product_id,product_name,qty) values(-941001,-941001,-941001,'TEST STOCK',2),(-941003,-941003,-941001,'TEST STOCK',3);
select set_config('v312.balance',solar_private.cash_balance(current_setting('v312.staff')::uuid)::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v312.staff'),true);
do $$ declare p jsonb; begin
 if not exists(select 1 from jsonb_array_elements(public.solar_sales_history(search_text=>'-941001')->'rows') x where x->>'canDelete'='true') then raise exception 'FAIL permission missing in history';end if;
 begin perform public.solar_sale_delete_preview(-941002);raise exception 'FAIL other invoice accessible';exception when insufficient_privilege then null;end;
 begin delete from public.transactions where id=-941001;raise exception 'FAIL direct delete';exception when insufficient_privilege then null;end;
 begin update public.transactions set kind='cash_income' where id=-941001;raise exception 'FAIL kind bypass';exception when insufficient_privilege then null;end;
 p:=public.solar_sale_delete_preview(-941001);
 update public.transactions set notes='edited after preview' where id=-941001;
 begin perform public.solar_sale_delete(-941001,p->>'token');raise exception 'FAIL stale delete';exception when serialization_failure then null;end;
 p:=public.solar_sale_delete_preview(-941001);
 perform public.solar_sale_delete(-941001,p->>'token');
 perform public.solar_sale_delete(-941001,p->>'token');
 if exists(select 1 from public.transactions where id=-941001) or exists(select 1 from public.transaction_items where transaction_id=-941001) then raise exception 'FAIL active invoice remains';end if;
 if (select qty from public.products where id=-941001)<>12 then raise exception 'FAIL duplicate/missing stock reversal';end if;
 if not exists(select 1 from public.transactions where id=-941005) then raise exception 'FAIL payment deleted';end if;
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>current_setting('v312.balance')::numeric-100 then raise exception 'FAIL cash reversal';end if;
 begin insert into public.transactions(id,kind,created_by,cashbox_user_id) values(-941001,'sale',auth.uid(),auth.uid());raise exception 'FAIL deleted id resurrected';exception when serialization_failure then null;end;
 p:=public.solar_sale_delete_preview(-941003);perform public.solar_sale_delete(-941003,p->>'token');
 if (select qty from public.products where id=-941001)<>15 then raise exception 'FAIL system stock reversal';end if;
 begin perform 1 from solar_private.deleted_sales;raise exception 'FAIL audit exposure';exception when insufficient_privilege then null;end;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v312.engineer'),true);
do $$ begin
 begin perform public.solar_sale_delete_preview(-941002);raise exception 'FAIL engineer deletion';exception when insufficient_privilege then null;end;
 if not exists(select 1 from public.solar_notifications where event='invoice_deleted' and body like '%-941003%') then raise exception 'FAIL cancelled task notice';end if;
end $$;
reset role;
do $$ begin
 if (select count(*) from solar_private.deleted_sales where invoice_id in (-941001,-941003))<>2 then raise exception 'FAIL audit snapshot';end if;
end $$;
update public.profiles set permissions=permissions||'{"salesDeleteAll":true}' where id=current_setting('v312.staff')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('v312.staff'),true);
do $$ declare p jsonb; begin p:=public.solar_sale_delete_preview(-941002);perform public.solar_sale_delete(-941002,p->>'token');end $$;
reset role;
-- A real payment movement keeps the invoice protected from destructive deletion.
insert into public.transactions(id,kind,total,created_by,cashbox_user_id,installation_expenses,installation_status) values(-941006,'system',500,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid,20,'closed');
insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id) values(current_setting('v312.staff')::uuid,-20,'installation_payout',-941006,current_setting('v312.staff')::uuid);
set local role authenticated;
do $$ declare p jsonb; begin
 p:=public.solar_sale_delete_preview(-941006);if p->>'blockedReason' is null then raise exception 'FAIL paid expense unprotected';end if;
 begin perform public.solar_sale_delete(-941006,p->>'token');raise exception 'FAIL paid expense deleted';exception when raise_exception then if sqlerrm like 'FAIL%' then raise;end if;end;
end $$;
reset role;
-- Force a drained cashbox without touching any permanent balance.
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-941007,'sale',100,true,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid);
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) select -941008,'cash_expense',solar_private.cash_balance(current_setting('v312.staff')::uuid),true,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid;
set local role authenticated;
do $$ declare p jsonb; begin p:=public.solar_sale_delete_preview(-941007);if p->>'blockedReason' is null then raise exception 'FAIL drained cashbox';end if;end $$;
reset role;
insert into public.transactions(id,kind,total,cash,created_by,cashbox_user_id) values(-941009,'cash_income',1000,true,current_setting('v312.staff')::uuid,current_setting('v312.staff')::uuid);
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key) values
 ('https://fcm.googleapis.com/fcm/send/v312-staff',current_setting('v312.staff')::uuid,repeat('A',87),repeat('B',22)),
 ('https://fcm.googleapis.com/fcm/send/v312-other',current_setting('v312.other')::uuid,repeat('A',87),repeat('B',22));
set local role authenticated;
do $$ begin
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000094111',current_setting('v312.other')::uuid,100);
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000094111',current_setting('v312.other')::uuid,100);
 if exists(select 1 from public.solar_notifications where transfer_id='00000000-0000-0000-0000-000000094111') then raise exception 'FAIL sender sees recipient inbox';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v312.other'),true);
do $$ begin
 if (select count(*) from public.solar_notifications where transfer_id='00000000-0000-0000-0000-000000094111' and event='cash_received')<>1 then raise exception 'FAIL new transfer notification';end if;
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000094111','accepted');
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000094111','accepted');
end $$;
select set_config('request.jwt.claim.sub',current_setting('v312.staff'),true);
do $$ begin
 if (select count(*) from public.solar_notifications where transfer_id='00000000-0000-0000-0000-000000094111' and event='cash_accepted')<>1 then raise exception 'FAIL acceptance notification';end if;
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000094112',current_setting('v312.other')::uuid,100);
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000094113',current_setting('v312.other')::uuid,100);
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000094113','cancelled');
end $$;
select set_config('request.jwt.claim.sub',current_setting('v312.other'),true);
do $$ begin
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000094112','rejected');
 if (select count(*) from public.solar_notifications where transfer_id='00000000-0000-0000-0000-000000094113' and event='cash_cancelled')<>1 then raise exception 'FAIL cancellation notification';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('v312.staff'),true);
do $$ begin if (select count(*) from public.solar_notifications where transfer_id='00000000-0000-0000-0000-000000094112' and event='cash_rejected')<>1 then raise exception 'FAIL rejection notice';end if;end $$;
reset role;
do $$ begin
 if (select count(distinct n.id) from public.solar_notifications n join solar_private.push_deliveries d on d.notification_id=n.id where n.transfer_id in ('00000000-0000-0000-0000-000000094111','00000000-0000-0000-0000-000000094112','00000000-0000-0000-0000-000000094113'))<>6 then raise exception 'FAIL durable push outbox';end if;
 if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and tablename='solar_notifications') then raise exception 'FAIL realtime not enabled';end if;
 if has_function_privilege('anon','public.solar_sale_delete(bigint,text)','execute') then raise exception 'FAIL anonymous delete';end if;
end $$;
select 'PASS: own/all deletion rights, no engineer delete, atomic stock/cash/account reversal, payment retained, audit, no double reversal, stale request, resurrection blocked, paid-expense and drained-cash guard, transfer notifications for every state, deduplication, private inbox, push outbox and realtime' as verification;
rollback;
