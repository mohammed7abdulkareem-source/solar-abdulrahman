\set ON_ERROR_STOP on
begin;

insert into public.profiles(id,display_name,is_admin,user_type,permissions) values
 ('00000000-0000-0000-0000-000000413601','مدير تجربة الرصيد',true,'admin_staff','{}'),
 ('00000000-0000-0000-0000-000000413602','قاصة أولى',false,'admin_staff','{"cash":true}'),
 ('00000000-0000-0000-0000-000000413603','قاصة ثانية',false,'admin_staff','{"cash":true}');

insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type,note,created_at)
 overriding system value values
 (-413601,'00000000-0000-0000-0000-000000413602','IQD',100,100,1,'capital_deposit','','2001-01-01T10:00Z'),
 (-413602,'00000000-0000-0000-0000-000000413603','IQD',1000,1000,1,'capital_deposit','','2001-01-01T10:01Z'),
 (-413603,'00000000-0000-0000-0000-000000413602','USD',3.25,4875,1500,'capital_deposit','','2001-01-01T10:02Z'),
 (-413604,'00000000-0000-0000-0000-000000413602','IQD',25,25,1,'capital_deposit','مرجع مميز','2001-01-02T10:00Z'),
 (-413605,'00000000-0000-0000-0000-000000413602','IQD',-125,-125,1,'capital_withdraw','مرجع مميز','2001-01-02T10:00Z');
-- Owned cash is visible even when the underlying sale belongs to a different creator.
insert into public.transactions(id,kind,party_name,total,subtotal,fx_pricing,cash,payment_mode,created_by,cashbox_user_id,created_at)
 values(-413606,'sale','عميل خاص',7,7,true,true,'cash','00000000-0000-0000-0000-000000413603','00000000-0000-0000-0000-000000413602','2001-01-02T10:01Z');

insert into solar_private.cash_transfers(id,sender_id,recipient_id,amount,status) values
 ('00000000-0000-0000-0000-000000413610','00000000-0000-0000-0000-000000413603','00000000-0000-0000-0000-000000413602',50,'pending');
insert into public.solar_cash_entries(id,owner_id,actor_id,delta,entry_type,transfer_id,created_at) values
 ('00000000-0000-0000-0000-000000413611','00000000-0000-0000-0000-000000413603','00000000-0000-0000-0000-000000413603',-50,'transfer_out','00000000-0000-0000-0000-000000413610','2001-01-02T10:02Z'),
 ('00000000-0000-0000-0000-000000413612',null,'00000000-0000-0000-0000-000000413603',50,'transfer_transit','00000000-0000-0000-0000-000000413610','2001-01-02T10:02Z');

-- Legacy reconciliations can share a posting timestamp. Their saved result is
-- authoritative even when id order puts them before another original event.
insert into solar_private.finance_requests(request_id,actor_id,action,payload,response)
 values('00000000-0000-0000-0000-000000413609','00000000-0000-0000-0000-000000413601','cash_reconcile',
 '{"mode":"set","currency":"IQD","target":20}','{"rows":[{"ownerId":"00000000-0000-0000-0000-000000413602","afterIQD":20}]}');
insert into solar_private.wallet_fx_entries(id,owner_id,currency,delta,book_delta,rate,entry_type,note,created_at,finance_request_id)
 overriding system value values
 (-413607,'00000000-0000-0000-0000-000000413602','IQD',-10,-10,1,'cash_reconcile','','2001-01-02T11:00Z','00000000-0000-0000-0000-000000413609'),
 (-413608,'00000000-0000-0000-0000-000000413602','IQD',23,23,1,'capital_deposit','','2001-01-02T11:00Z',null);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413601',true);
do $test$
declare r jsonb; row_data jsonb; detail jsonb;
begin
 -- The later page retains other dates and movements in the balance, and does
 -- not count the 1,000 IQD in the second cashbox or 3.25 USD in this one.
 r:=public.solar_cash_workspace('{"from":"2001-01-02","to":"2001-01-02","currency":"IQD","query":"مرجع مميز","limit":1,"offset":1}');
 assert (r->>'count')::int=2;
 row_data:=r#>'{rows,0}';
 assert row_data->>'id'='fx:-413604' and (row_data->>'ownerBalance')::numeric=125;
 assert (row_data->>'balance')::numeric<>(row_data->>'ownerBalance')::numeric;
 r:=public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000413602","currency":"IQD","query":"مرجع مميز","direction":"out"}');
 assert (r->>'count')::int=1 and (r#>>'{rows,0,ownerBalance}')::numeric=0;
 r:=public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000413602","currency":"USD"}');
 assert (r#>>'{rows,0,ownerBalance}')::numeric=3.25;
 r:=public.solar_cash_workspace('{"from":"2001-01-02","to":"2001-01-02","currency":"IQD"}');
 select el into strict row_data from jsonb_array_elements(r->'rows') el where el->>'id'='entry:00000000-0000-0000-0000-000000413612';
 detail:=public.solar_cash_movement_detail(row_data->>'id');
 assert (detail->>'after')::numeric=50 and row_data->>'ownerBalance'=detail->>'ownerBalance';
 select el into strict row_data from jsonb_array_elements(r->'rows') el where el->>'id'='entry:00000000-0000-0000-0000-000000413611';
 assert (row_data->>'ownerBalance')::numeric=950;
 detail:=public.solar_cash_movement_detail('fx:-413607');
 assert (detail->>'after')::numeric=20 and (detail->>'ownerBalance')::numeric=20;
 r:=public.solar_cash_workspace('{"ownerId":"00000000-0000-0000-0000-000000413602"}');
 select el into strict row_data from jsonb_array_elements(r->'rows') el where el->>'id'='fx:-413607';
 assert row_data->>'ownerBalance'=detail->>'ownerBalance' and (row_data#>>'{reconciliation,afterIQD}')::numeric=20;
end $test$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000413602',true);
do $test$
declare r jsonb; row_data jsonb; detail jsonb;
begin
 r:=public.solar_cash_workspace('{}');
 assert not exists(select 1 from jsonb_array_elements(r->'rows') el where el->>'owner_id' is distinct from auth.uid()::text);
 select el into strict row_data from jsonb_array_elements(r->'rows') el where (el->>'receiptRestricted')::boolean;
 assert (row_data->>'ownerBalance')::numeric=7 and row_data::text not like '%عميل خاص%';
 detail:=public.solar_cash_movement_detail('tx:-413606');
 assert (detail->>'ownerBalance')::numeric=7 and (detail->>'before')::numeric=0;
end $test$;
rollback;
