\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000413651','اعتماد تجريبي',true,'admin','{}'),
 ('00000000-0000-0000-0000-000000413652','مرسل تجريبي',false,'admin_staff','{"cash":true,"cashTransferSend":true}'),
 ('00000000-0000-0000-0000-000000413653','مستلم تجريبي',false,'admin_staff','{"cash":true,"financeReceive":true}'),
 ('00000000-0000-0000-0000-000000413654','قاصة أخرى',false,'admin_staff','{"cash":true}');
set local role authenticated;
do $test$
declare
 manager uuid:='00000000-0000-0000-0000-000000413651'; sender uuid:='00000000-0000-0000-0000-000000413652';
 recipient uuid:='00000000-0000-0000-0000-000000413653'; outsider uuid:='00000000-0000-0000-0000-000000413654';
 accepted uuid:=gen_random_uuid(); rejected uuid:=gen_random_uuid(); pending uuid:=gen_random_uuid(); cancelled uuid:=gen_random_uuid();
 result jsonb; incoming jsonb; direct jsonb; same_row jsonb; row_date date:=(now() at time zone 'Asia/Baghdad')::date;
begin
 perform set_config('request.jwt.claim.sub',manager::text,true);
 perform public.solar_cash_save(gen_random_uuid(),jsonb_build_object('ownerId',sender,'mode','deposit','currency','IQD','amount',500000,'note','أموال اختبار'));
 perform public.solar_cash_record('transfer',null,gen_random_uuid(),jsonb_build_object('senderId',sender,'recipientId',recipient,'currency','IQD','amount',50,'note','تسليم مباشر'));
 perform set_config('request.jwt.claim.sub',sender::text,true);
 perform public.solar_cash_transfer_send(accepted,recipient,700);
 perform public.solar_cash_transfer_send(rejected,recipient,400);
 perform public.solar_cash_transfer_send(pending,recipient,300);
 perform public.solar_cash_transfer_send(cancelled,recipient,100);
 perform public.solar_cash_transfer_decide(cancelled,'cancelled');
 perform set_config('request.jwt.claim.sub',recipient::text,true);
 perform public.solar_cash_transfer_decide(accepted,'accepted');
 perform public.solar_cash_transfer_decide(rejected,'rejected');

 result:=public.solar_cash_workspace(jsonb_build_object('query','مرسل تجريبي','direction','in'));
 assert (result->>'count')::int=2;
 select x into strict incoming from jsonb_array_elements(result->'rows') x where x->>'kind'='transfer_in';
 assert incoming#>>'{transfer,sender}'='مرسل تجريبي' and incoming#>>'{transfer,recipient}'='مستلم تجريبي'
    and incoming#>>'{transfer,decidedBy}'='مستلم تجريبي' and incoming#>>'{transfer,status}'='accepted';
 select x into strict direct from jsonb_array_elements(result->'rows') x where x->>'kind'='admin_transfer_in';
 assert direct#>>'{transfer,sender}'='مرسل تجريبي' and direct#>>'{transfer,recipient}'='مستلم تجريبي'
    and direct#>>'{transfer,decidedBy}'='اعتماد تجريبي';
 assert (public.solar_cash_workspace(jsonb_build_object('query','اعتماد تجريبي'))->>'count')::int=1;
 select public.solar_cash_movement_detail(incoming->>'id') into same_row;
 assert same_row#>>'{transfer,sender}'=incoming#>>'{transfer,sender}' and same_row#>>'{transfer,decidedBy}'=incoming#>>'{transfer,decidedBy}';
 result:=public.solar_cash_statement(null,row_date,row_date,'IQD');
 select x into strict same_row from jsonb_array_elements(result->'ledgers') l cross join jsonb_array_elements(l->'rows') x where x->>'id'=incoming->>'id';
 assert same_row->'transfer'=incoming->'transfer';
 select x into strict same_row from jsonb_array_elements(result->'ledgers') l cross join jsonb_array_elements(l->'rows') x where x->>'id'=direct->>'id';
 assert same_row->'transfer'=direct->'transfer';

 perform set_config('request.jwt.claim.sub',sender::text,true);
 result:=public.solar_cash_workspace('{"query":"مستلم تجريبي"}');
 select x into strict same_row from jsonb_array_elements(result->'rows') x where x->>'kind'='transfer_out' and (x->>'delta')::numeric=-300;
 assert same_row#>>'{transfer,status}'='pending' and same_row#>>'{transfer,decidedBy}' is null;
 select x into strict same_row from jsonb_array_elements(result->'rows') x where x->>'kind'='transfer_refund' and (x->>'delta')::numeric=400;
 assert same_row#>>'{transfer,status}'='rejected' and same_row#>>'{transfer,decidedBy}'='مستلم تجريبي';
 select x into strict same_row from jsonb_array_elements(result->'rows') x where x->>'kind'='transfer_refund' and (x->>'delta')::numeric=100;
 assert same_row#>>'{transfer,status}'='cancelled' and same_row#>>'{transfer,decidedBy}'='مرسل تجريبي';

 perform set_config('request.jwt.claim.sub',outsider::text,true);
 assert (public.solar_cash_workspace('{"query":"مرسل تجريبي"}')->>'count')::int=0;
 assert not has_function_privilege('authenticated','solar_private.cash_transfer_parties(text,text,uuid)','EXECUTE');
end $test$;
rollback;
