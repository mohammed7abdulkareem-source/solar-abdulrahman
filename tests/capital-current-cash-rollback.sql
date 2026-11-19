-- Synthetic accounts and handovers. A populated local fixture is supported.
\set ON_ERROR_STOP on
begin;
do $test$
declare
 admin_id uuid:=gen_random_uuid(); sender uuid:=gen_random_uuid(); receiver uuid:=gen_random_uuid();
 archived uuid:=gen_random_uuid(); denied uuid:=gen_random_uuid(); installer uuid:=gen_random_uuid();
 untouched uuid:=gen_random_uuid(); open_id uuid:=gen_random_uuid(); other_id uuid:=gen_random_uuid();
 accepted uuid:=gen_random_uuid(); rejected uuid:=gen_random_uuid(); cancelled uuid:=gen_random_uuid();
 snapshot jsonb; legacy jsonb; cash jsonb; row_data jsonb; before_cash jsonb; amount numeric;
begin
 insert into public.profiles(id,display_name,is_admin,active,user_type,permissions) values
 (admin_id,'كشف الإدارة',true,true,'admin','{}'),
 (sender,'اسم متكرر',false,true,'admin_staff','{"capital":true,"cashTransferSend":true}'),
 (receiver,'مستلم الكشف',false,true,'admin_staff','{"capital":true,"financeReceive":true}'),
 (archived,'اسم متكرر',false,false,'admin_staff','{}'),
 (untouched,'رصيد صفري',false,true,'admin_staff','{"capital":true}'),
 (denied,'مستخدم مالي',false,true,'admin_staff','{"cashTransferSend":true}'),
 (installer,'منصّب',true,true,'installer','{"capital":true}');
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 before_cash:=public.solar_capital_current_snapshot()->'cash';
 insert into public.transactions(id,kind,created_by,cashbox_user_id,total,cash) values
 (-19100501,'cash_income',sender,sender,1200,true),
 (-19100502,'cash_expense',sender,archived,25,true),
 (-19100503,'cash_income',null,null,14.6,true),
 (-19100504,'cash_income',denied,denied,30,true);
 insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type) overriding system value values
 (-19100501,sender,'USD',10,15300,1530,'deposit'),
 (-19100502,sender,'USD',1,1600,1600,'deposit');
 perform set_config('request.jwt.claim.sub',sender::text,true);
 perform public.solar_cash_transfer_send(open_id,receiver,120);
 perform public.solar_cash_transfer_send(accepted,receiver,30);
 perform public.solar_cash_transfer_send(rejected,receiver,10);
 perform public.solar_cash_transfer_send(cancelled,receiver,7);
 perform public.solar_cash_transfer_decide(cancelled,'cancelled');
 perform set_config('request.jwt.claim.sub',receiver::text,true);
 perform public.solar_cash_transfer_decide(accepted,'accepted');
 perform public.solar_cash_transfer_decide(rejected,'rejected');
 perform set_config('request.jwt.claim.sub',denied::text,true);
 perform public.solar_cash_transfer_send(other_id,admin_id,8);
 perform set_config('request.jwt.claim.sub',admin_id::text,true);
 snapshot:=public.solar_capital_current_snapshot();
 legacy:=public.solar_capital_snapshot();
 cash:=snapshot->'cash';
 assert not(cash?'rows') and jsonb_typeof(legacy#>'{cash,rows}')='array';
 assert (cash-array['allocations','pendingHandovers'])=((legacy->'cash')-'rows');
 assert snapshot-'cash'=legacy-'cash';
 assert (cash->>'iqd')::numeric-(before_cash->>'iqd')::numeric=1219.6;
 assert (cash->>'usd')::numeric-(before_cash->>'usd')::numeric=11;
 assert (cash->>'usdBook')::numeric-(before_cash->>'usdBook')::numeric=16900;
 select v into row_data from jsonb_array_elements(cash->'allocations') v where v->>'ownerId'=sender::text;
 assert row_data->>'kind'='owner' and (row_data->>'iqd')::numeric=1050 and (row_data->>'usd')::numeric=11 and (row_data->>'usdBook')::numeric=16900;
 select v into row_data from jsonb_array_elements(cash->'allocations') v where v->>'ownerId'=archived::text;
 assert (row_data->>'iqd')::numeric=-25 and row_data->>'ownerName'='اسم متكرر';
 assert not exists(select 1 from jsonb_array_elements(cash->'allocations') v where v->>'ownerId'=untouched::text);
 select coalesce(sum((v->>'iqd')::numeric),0) into amount from jsonb_array_elements(before_cash->'allocations') v where v->>'kind'='transit';
 assert (select (v->>'iqd')::numeric from jsonb_array_elements(cash->'allocations') v where v->>'kind'='transit')-amount=128;
 select coalesce(sum((v->>'iqd')::numeric),0) into amount from jsonb_array_elements(before_cash->'allocations') v where v->>'kind'='unassigned';
 assert (select (v->>'iqd')::numeric from jsonb_array_elements(cash->'allocations') v where v->>'kind'='unassigned')-amount=14.6;
 assert (select round(sum((v->>'iqd')::numeric),2) from jsonb_array_elements(cash->'allocations') v)=(cash->>'iqd')::numeric;
 assert not exists(select 1 from jsonb_array_elements(cash->'pendingHandovers') v where (v->>'id')::uuid in(accepted,rejected,cancelled));
 select v into row_data from jsonb_array_elements(cash->'pendingHandovers') v where v->>'id'=open_id::text;
 assert row_data->>'senderName'='اسم متكرر' and row_data->>'recipientName'='مستلم الكشف' and row_data->>'currency'='IQD' and (row_data->>'amount')::numeric=120;
 assert not(row_data?|array['notes','receiptNo','expense','expense_note']);
 perform set_config('request.jwt.claim.sub',receiver::text,true);
 snapshot:=public.solar_capital_current_snapshot();
 cash:=snapshot->'cash';
 assert snapshot->>'scope'='own' and (cash->>'iqd')::numeric=30 and (cash->>'usd')::numeric=0;
 assert jsonb_array_length(cash->'allocations')=1 and cash#>>'{allocations,0,ownerId}'=receiver::text;
 assert jsonb_array_length(cash->'pendingHandovers')=1 and cash#>>'{pendingHandovers,0,id}'=open_id::text;
 perform set_config('request.jwt.claim.sub',sender::text,true);
 cash:=public.solar_capital_current_snapshot()->'cash';
 assert (cash->>'iqd')::numeric=1050 and jsonb_array_length(cash->'pendingHandovers')=1 and cash#>>'{pendingHandovers,0,id}'=open_id::text;
 perform set_config('request.jwt.claim.sub',untouched::text,true);
 cash:=public.solar_capital_current_snapshot()->'cash';
 assert cash->'allocations'='[]' and cash->'pendingHandovers'='[]' and (cash->>'iqd')::numeric=0;
 foreach denied in array array[denied,installer,archived] loop
  perform set_config('request.jwt.claim.sub',denied::text,true);
  begin perform public.solar_capital_current_snapshot();raise exception 'Unauthorized capital report';
  exception when insufficient_privilege then null;end;
 end loop;
 assert not has_function_privilege('anon','public.solar_capital_current_snapshot()','execute')
  and not has_function_privilege('anon','solar_private.capital_snapshot(boolean)','execute');
end$test$;
rollback;
\echo PASS scoped current cash allocations, open handovers, legacy compatibility and capital reconciliation.
