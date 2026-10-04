begin;
select set_config('cash_test.sender',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1),true);
select set_config('cash_test.receiver',(select id::text from public.profiles where active and not is_admin and user_type='admin_staff' and id<>current_setting('cash_test.sender')::uuid order by created_at limit 1),true);
select set_config('cash_test.admin',(select id::text from public.profiles where active and is_admin and user_type<>'installer' limit 1),true);
select set_config('cash_test.engineer',(select id::text from public.profiles where active and user_type='installer' limit 1),true);
update public.profiles set permissions='{"cashTransferSend":true,"installationsAll":true}' where id=current_setting('cash_test.sender')::uuid;
update public.profiles set permissions='{"financeReceive":true,"installations":true}' where id=current_setting('cash_test.receiver')::uuid;
insert into public.transactions(id,kind,cash,total,created_by,cashbox_user_id) values
 (-931001,'cash_income',true,1000,current_setting('cash_test.sender')::uuid,current_setting('cash_test.sender')::uuid),
 (-931002,'cash_income',true,1000,current_setting('cash_test.receiver')::uuid,current_setting('cash_test.receiver')::uuid);
insert into public.transactions(id,kind,cash,total,cost,created_by,cashbox_user_id,installer_id,installation_status,installation_report)
 values(-931003,'system',false,2000,500,current_setting('cash_test.receiver')::uuid,current_setting('cash_test.receiver')::uuid,current_setting('cash_test.engineer')::uuid,'completed','{"expenseTotal":100}');
select set_config('cash_test.sender_balance',solar_private.cash_balance(current_setting('cash_test.sender')::uuid)::text,true);
select set_config('cash_test.receiver_balance',solar_private.cash_balance(current_setting('cash_test.receiver')::uuid)::text,true);
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('cash_test.sender'),true);
do $$ declare b numeric; begin
 -- Closing another user's job charges this caller, not the invoice creator.
 perform public.solar_installation_action(-931003,0,'close','{"amount":100}');
 b:=(public.solar_cash_transfer_overview()->>'balance')::numeric;
 if b<>current_setting('cash_test.sender_balance')::numeric-100 then raise exception 'FAIL closer cash debit';end if;
 perform public.solar_installation_action(-931003,1,'reopen');
 perform public.solar_installation_action(-931003,2,'close','{"amount":100}');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>b then raise exception 'FAIL duplicate reclose debit';end if;
 perform public.solar_installation_action(-931003,3,'reopen');
 perform public.solar_installation_action(-931003,4,'close','{"amount":80}');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>b+20 then raise exception 'FAIL expense refund';end if;
 -- Permission and overspend checks.
 begin perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093110',current_setting('cash_test.engineer')::uuid,5);raise exception 'FAIL invalid receiver';exception when insufficient_privilege then null;end;
 begin perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093110',current_setting('cash_test.receiver')::uuid,b+21);raise exception 'FAIL overspend';exception when no_data_found then null;end;
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093111',current_setting('cash_test.receiver')::uuid,500,50,'','test transfer');
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093111',current_setting('cash_test.receiver')::uuid,500,50,'','test transfer');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>b+20-550 then raise exception 'FAIL send idempotency';end if;
 begin perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093111','accepted');raise exception 'FAIL self approval';exception when insufficient_privilege then null;end;
 begin insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id) values(auth.uid(),1,'installation_refund',-931003,auth.uid());raise exception 'FAIL direct ledger write';exception when insufficient_privilege then null;end;
 if exists(select 1 from public.solar_cash_entries where owner_id is distinct from auth.uid()) then raise exception 'FAIL ledger privacy';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('cash_test.receiver'),true);
do $$ begin
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>current_setting('cash_test.receiver_balance')::numeric then raise exception 'FAIL recipient credited before approval';end if;
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093111','accepted');
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093111','accepted');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>current_setting('cash_test.receiver_balance')::numeric+500 then raise exception 'FAIL approval duplicate';end if;
 begin perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093112',current_setting('cash_test.admin')::uuid,5);raise exception 'FAIL receive permission grants send';exception when insufficient_privilege then null;end;
 -- A different closer refund goes to the original payer, not themselves.
 perform public.solar_installation_action(-931003,5,'reopen');
 perform public.solar_installation_action(-931003,6,'close','{"amount":60}');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>current_setting('cash_test.receiver_balance')::numeric+500 then raise exception 'FAIL refund went to wrong payer';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('cash_test.sender'),true);
do $$ declare b numeric; begin
 b:=(public.solar_cash_transfer_overview()->>'balance')::numeric;
 if b<>current_setting('cash_test.sender_balance')::numeric-610 then raise exception 'FAIL payer refunded';end if;
 -- Send all remaining cash after 10 expense: zero sender balance.
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093112',current_setting('cash_test.receiver')::uuid,b-10,10);
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>0 then raise exception 'FAIL full handover not zero';end if;
 perform public.solar_installation_action(-931003,7,'reopen');
 begin perform public.solar_installation_action(-931003,8,'close','{"amount":61}');raise exception 'FAIL unfunded close';exception when no_data_found then null;end;
end $$;
-- Removing receive permission takes effect immediately.
reset role;
update public.profiles set permissions='{}' where id=current_setting('cash_test.receiver')::uuid;
set local role authenticated;
select set_config('request.jwt.claim.sub',current_setting('cash_test.receiver'),true);
do $$ begin
 begin perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093112','accepted');raise exception 'FAIL revoked permission';exception when insufficient_privilege then null;end;
end $$;
reset role;
update public.profiles set permissions='{"financeReceive":true}' where id=current_setting('cash_test.receiver')::uuid;
set local role authenticated;
do $$ begin
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093112','rejected');
end $$;
select set_config('request.jwt.claim.sub',current_setting('cash_test.sender'),true);
do $$ declare b numeric; begin
 b:=(public.solar_cash_transfer_overview()->>'balance')::numeric;
 if b<>current_setting('cash_test.sender_balance')::numeric-620 then raise exception 'FAIL rejection refund or expense reversed';end if;
 perform public.solar_cash_transfer_send('00000000-0000-0000-0000-000000093113',current_setting('cash_test.receiver')::uuid,5);
 perform public.solar_cash_transfer_decide('00000000-0000-0000-0000-000000093113','cancelled');
 if (public.solar_cash_transfer_overview()->>'balance')::numeric<>b then raise exception 'FAIL cancellation';end if;
end $$;
select set_config('request.jwt.claim.sub',current_setting('cash_test.engineer'),true);
do $$ begin
 if exists(select 1 from public.solar_cash_entries) then raise exception 'FAIL engineer cash exposure';end if;
 begin perform public.solar_cash_transfer_overview();raise exception 'FAIL engineer transfers';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if exists(select 1 from public.solar_cash_entries where transfer_id in ('00000000-0000-0000-0000-000000093111','00000000-0000-0000-0000-000000093112','00000000-0000-0000-0000-000000093113') group by transfer_id having sum(delta)<>-sum(case when entry_type='handover_expense' then -delta else 0 end)) then raise exception 'FAIL transfer conservation';end if;
 if has_function_privilege('anon','public.solar_cash_transfer_overview()','execute') or has_table_privilege('authenticated','public.solar_cash_entries','insert') then raise exception 'FAIL grants';end if;
end $$;
select 'PASS: closer debit, reclose delta, original-payer refund, transfer conservation, pending escrow, approval/rejection/cancel, zero cash, overspend, idempotency, revoked rights, engineer isolation, immutable ledger' as verification;
rollback;
