-- Mixed pricing, installation expense and beneficiary transfer on one signed system.
\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,username,display_name,user_type,permissions,is_admin,phone) values
 ('00000000-0000-0000-0000-000000412551','basis_job_manager','مدير التقرير','admin_staff','{}',true,'07700000000'),
 ('00000000-0000-0000-0000-000000412552','basis_job_seller','بائع التجربة','admin_staff','{"system":true,"installations":true,"profit":true,"profitUsesWholesalePrice":true}',false,'07700000000'),
 ('00000000-0000-0000-0000-000000412553','basis_job_receiver','مستلم الربح','admin_staff','{"profit":true}',false,'07700000000'),
 ('00000000-0000-0000-0000-000000412554','basis_job_engineer','مهندس التجربة','installer','{}',false,'07700000000');
insert into public.customers(id,name,customer_type,owner_id) values(-412551,'زبون تقرير تجريبي','system','00000000-0000-0000-0000-000000412552');
insert into public.products(id,code,name,qty,cost) values(-412551,'PBP-A','لوح فحص',20,100),(-412552,'PBP-B','بطارية فحص',20,180);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty) values(1,-412551,20),(1,-412552,20)
 on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
insert into solar_private.wholesale_product_prices(product_id,enabled,minimum_price) values(-412551,true,140),(-412552,false,400);
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412552',true);
select set_config('test.system_basis_receipt',public.solar_invoice_save(gen_random_uuid(),
 '{"kind":"system","mode":"credit","partyId":-412551,"party":"زبون تقرير تجريبي","warehouseId":1,"installerId":"00000000-0000-0000-0000-000000412554","customerAddress":"موقع تجريبي","total":900,"items":[{"id":-412551,"qty":2,"price":0},{"id":-412552,"qty":1,"price":0}]}')->>'id',true);
do $$declare r jsonb;begin
 select x into strict r from jsonb_array_elements(public.solar_pending_systems()->'rows') x where x->>'id'=current_setting('test.system_basis_receipt');
 assert (r->>'provisionalProfit')::numeric=440 and (r->>'costHidden')::boolean and r->'materialCost'='null'::jsonb;
end $$;
reset role;
update public.transactions set warehouse_status='ready' where id=current_setting('test.system_basis_receipt')::bigint;
set local role authenticated;
do $$declare
 receipt bigint:=current_setting('test.system_basis_receipt')::bigint;
 manager constant uuid:='00000000-0000-0000-0000-000000412551';
 seller constant uuid:='00000000-0000-0000-0000-000000412552';
 beneficiary constant uuid:='00000000-0000-0000-0000-000000412553';
 b jsonb; command jsonb; preview jsonb;
begin
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412554',true);
 perform public.solar_installation_action(receipt,0,'start');
 perform public.solar_installation_action(receipt,1,'complete','{"checks":{"materials":true,"tested":true,"handover":true},"notes":"تم تسليم المواد","expenses":[]}');
 perform set_config('request.jwt.claim.sub',seller::text,true);
 perform public.solar_installation_action(receipt,2,'close','{"amount":60}');
 b:=public.solar_profit_detail('tx:'||receipt);
 assert b->'invoice'='null'::jsonb and (b#>>'{breakdown,costHidden}')::boolean;
 assert (b#>>'{breakdown,netProfit}')::numeric=380 and (b#>>'{breakdown,installationExpenses}')::numeric=60;
 assert b#>'{breakdown,materialsCost}'='null'::jsonb and b#>'{breakdown,grossProfit}'='null'::jsonb;
 assert exists(select from jsonb_array_elements(b#>'{breakdown,items}') x where x->>'productId'='-412551' and (x->>'unitCost')::numeric=140);
 assert exists(select from jsonb_array_elements(b#>'{breakdown,items}') x where x->>'productId'='-412552' and x->'unitCost'='null'::jsonb and x->'lineCost'='null'::jsonb);
 begin perform public.solar_company_profit_detail('tx:'||receipt,seller);
  raise exception 'Employee received company detail';exception when insufficient_privilege then null;end;
 perform set_config('request.jwt.claim.sub',manager::text,true);
 b:=public.solar_company_profit_detail('tx:'||receipt,seller)->'breakdown';
 assert (b->>'netProfit')::numeric=460 and (b->>'materialsCost')::numeric=380;
 command:=jsonb_build_object('invoiceIds',jsonb_build_array(receipt),'ownerId',beneficiary);
 preview:=public.solar_profit_transfer('preview',null,command);
 assert (preview->>'total')::numeric=380 and (preview#>>'{rows,0,profit}')::numeric=380;
 perform public.solar_profit_transfer('apply',gen_random_uuid(),command||jsonb_build_object('expectedToken',preview->>'token'));
 perform set_config('request.jwt.claim.sub',beneficiary::text,true);
 assert (public.solar_profit_workspace('overview')->>'available')::numeric=380,'unselected recipient received a different amount';
 perform set_config('request.jwt.claim.sub',seller::text,true);
 assert (public.solar_profit_workspace('overview')->>'available')::numeric=0,'seller kept the transferred margin';
end $$;
reset role;
do $$declare receipt bigint:=current_setting('test.system_basis_receipt')::bigint;begin
 assert(select profit=380 from solar_private.invoice_profit_owner_audit where invoice_id=receipt),'transfer audit stored a different amount';
 assert(select profit=460 and cost=380 and installation_expenses=60 from public.transactions where id=receipt),'company expense or margin changed on transfer';
end $$;
rollback;
