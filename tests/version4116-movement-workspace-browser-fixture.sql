-- Apply only to the isolated browser database after the V415 material fixtures.
begin;
do $$ begin
 if current_database() !~ '^solar_.*_browser$' then raise exception 'Local browser database required'; end if;
end $$;

insert into public.products(id,code,name,qty,cost,brand_id,category) values
 (-411601,'V4116-TWIN-A','انفيرتر توأم 15KW',30,100,-415501,'انفيرتر'),
 (-411602,'V4116-TWIN-B','انفيرتر توأم 15KW',40,200,-415502,'انفيرتر');
-- Represent imported same-name customers predating the duplicate guard.
alter table public.customers disable trigger solar_customer_guard;
insert into public.customers(id,name,customer_type,owner_id) values
 (-411601,'زبون كشف التوأم','wholesale','00000000-0000-0000-0000-000000415502'),
 (-411602,'زبون كشف التوأم','wholesale','00000000-0000-0000-0000-000000415501');
alter table public.customers enable trigger solar_customer_guard;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415502',true);
do $$
declare
 sale jsonb := jsonb_build_object('kind','sale','mode','credit','warehouseId',solar_private.primary_warehouse(),'party','زبون كشف التوأم');
 sale_id bigint;
begin
 perform public.solar_invoice_save(gen_random_uuid(),sale||jsonb_build_object('partyId',-411601,'notes','V4116 ONE A','items','[{"id":-411601,"qty":2,"price":500}]'::jsonb));
 perform public.solar_invoice_save(gen_random_uuid(),sale||jsonb_build_object('partyId',-411601,'notes','V4116 ONE B','items','[{"id":-411602,"qty":3,"price":600}]'::jsonb));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000415501',true);
 perform public.solar_invoice_save(gen_random_uuid(),sale||jsonb_build_object('partyId',-411602,'notes','V4116 TWO A','items','[{"id":-411601,"qty":5,"price":500}]'::jsonb));
 sale_id := (public.solar_invoice_save(gen_random_uuid(),sale||jsonb_build_object('partyId',-411602,'notes','V4116 AMBIGUOUS','items','[{"id":-411601,"qty":1,"price":500}]'::jsonb))->>'id')::bigint;
 update public.transactions set party_id=null where id=sale_id;
end $$;
-- A pre-link sale with a unique customer name can still be identified.
update public.transactions t set party_id=null
 where t.kind='sale' and t.party_id=-415501
 and exists(select 1 from public.transaction_items line where line.transaction_id=t.id and line.product_id=-415502);
commit;
