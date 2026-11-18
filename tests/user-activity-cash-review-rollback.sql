-- Use a disposable database. Simulate incomplete postings and confirm the report
-- distinguishes them from legitimate money in transit and approved returns.
\set ON_ERROR_STOP on
begin;
do $test$
declare a uuid:=gen_random_uuid();b uuid:=gen_random_uuid(); transfer uuid:=gen_random_uuid();direct_id uuid:=gen_random_uuid();j jsonb;
begin
 insert into public.profiles(id,user_type,active,is_admin,display_name) values (a,'admin_staff',true,false,'طرف أ'),(b,'admin_staff',true,false,'طرف ب');
 insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount) values(transfer,a,b,100);
 insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id) values(a,-100,'transfer_out',transfer,a),(null,100,'transfer_transit',transfer,a);
 j:=solar_private.user_activity_review(a,null,null);
 if j->>'checkedTransfers'<>'1' or j->>'differenceCount'<>'0' then raise exception 'Balanced pending transfer flagged'; end if;
 update solar_private.cash_transfers set status='accepted',decided_at=now(),decided_by=b where id=transfer;
 insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id) values(null,-100,'transfer_transit',transfer,b);
 j:=solar_private.user_activity_review(a,null,null);
 if j->>'differenceCount'<>'1' or j#>>'{differences,0,kind}'<>'transfer_in' or (j#>>'{differences,0,expected}')::numeric<>100 or (j#>>'{differences,0,posted}')::numeric<>0 then raise exception 'Missing receipt not identified';end if;
 insert into public.solar_cash_entries(owner_id,delta,entry_type,transfer_id,actor_id) values(b,100,'transfer_in',transfer,b);
 if solar_private.user_activity_review(a,null,null)->>'differenceCount'<>'0' then raise exception 'Balanced receipt flagged'; end if;
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)
 values(direct_id,a,'admin_cash_transfer','{}',jsonb_build_object('amount',7.25,'currency','USD','senderId',a,'recipientId',b,'date',now(),'receiptNo',13));
 insert into solar_private.wallet_fx_entries(owner_id,currency,delta,book_delta,rate,gain,entry_type,note,finance_request_id)
 values(a,'USD',-7.25,-10875,1500,0,'admin_transfer_out','تسليم',direct_id),(b,'USD',7,10500,1500,0,'admin_transfer_in','استلام',direct_id);
 j:=solar_private.user_activity_review(b,null,null);
 if j->>'differenceCount'<>'1' or j#>>'{differences,0,kind}'<>'admin_transfer_in' or j#>>'{differences,0,currency}'<>'USD'
   or (j#>>'{differences,0,expected}')::numeric<>7.25 or (j#>>'{differences,0,posted}')::numeric<>7 then raise exception 'Incorrect USD receipt comparison';end if;
 if solar_private.user_activity_review(b,null,current_date-3)->>'checkedTransfers'<>'0' then raise exception 'Date filter ignored';end if;
 if has_function_privilege('authenticated','solar_private.user_activity_review(uuid,date,date)','execute')
    or has_function_privilege('anon','solar_private.user_activity_review(uuid,date,date)','execute') then raise exception 'Public exposure';end if;
end $test$;
rollback;
