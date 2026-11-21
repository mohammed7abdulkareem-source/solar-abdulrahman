begin;
insert into public.profiles(id,username,display_name,active,is_admin,user_type,permissions,phone) values
 ('00000000-0000-0000-0000-000000412501','personal_basis_admin','أدمن أساس الربح',true,true,'admin','{}','07700000000'),
 ('00000000-0000-0000-0000-000000412502','personal_basis_user','صاحب أساس الربح',true,false,'admin_staff','{"sale":true,"profit":true,"system":true}','07700000000'),
 ('00000000-0000-0000-0000-000000412503','personal_basis_other','موظف مصرح',true,false,'admin_staff','{"sale":true}','07700000000');
insert into public.customers(id,name,customer_type,owner_id) values
 (-412511,'زبون أساس الربح','wholesale','00000000-0000-0000-0000-000000412502');
insert into public.products(id,code,name,qty,cost) values
 (-412511,'BASIS4125A','مادة لها سعر',200,100),(-412512,'BASIS4125B','مادة غير مفعّلة',200,300),(-412513,'BASIS4125C','مادة مضافة',200,400);
insert into solar_private.warehouse_stocks(warehouse_id,product_id,qty)
 values (1,-412511,200),(1,-412512,200),(1,-412513,200)
 on conflict(warehouse_id,product_id) do update set qty=excluded.qty;
insert into solar_private.wholesale_product_prices(product_id,enabled,minimum_price) values
 (-412511,true,140),(-412512,false,700),(-412513,true,900);

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412502',true);
do $t$begin
 if solar_private.viewer_uses_personal_prices() then raise exception 'Staff unexpectedly opted in';end if;
 begin perform public.solar_profit_basis_users('state');raise exception 'Non-admin listed basis users';exception when insufficient_privilege then null;end;
 begin perform public.solar_profit_basis_users('save',gen_random_uuid(),'{}');raise exception 'Non-admin configured other staff';exception when insufficient_privilege then null;end;
end$t$;
select set_config('fixture.post_payload','{"kind":"sale","mode":"credit","partyId":-412511,"party":"زبون أساس الربح","warehouseId":1,"items":[{"id":-412511,"qty":2,"price":250},{"id":-412512,"qty":1,"price":600}]}',true);
select set_config('fixture.old_doc',(public.solar_invoice_save(gen_random_uuid(),current_setting('fixture.post_payload')::jsonb)->>'id'),true);

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412501',true);
do $t$ declare initial jsonb; saved jsonb; cmd jsonb; req uuid:=gen_random_uuid();begin
 initial:=public.solar_profit_basis_users('state');
 cmd:=jsonb_build_object('token',initial->>'token','changes','[{"id":"00000000-0000-0000-0000-000000412502","enabled":true}]'::jsonb);
 saved:=public.solar_profit_basis_users('save',req,cmd);
 if saved->>'token'=initial->>'token' or not exists(select from jsonb_array_elements(saved->'users')x where x->>'id'='00000000-0000-0000-0000-000000412502' and x->>'enabled'='true') then raise exception 'State did not persist patch';end if;
 if public.solar_profit_basis_users('save',req,cmd) is distinct from saved then raise exception 'Identical request replay changed state';end if;
 begin perform public.solar_profit_basis_users('save',gen_random_uuid(),cmd);raise exception 'Stale token accepted';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_profit_basis_users('save',req,jsonb_set(cmd,'{changes,0,enabled}','false'));raise exception 'Different payload reused same key';exception when sqlstate 'PT409' then null;end;
 begin perform public.solar_profit_basis_users('save',gen_random_uuid(),
  jsonb_build_object('token',saved->>'token','changes','[{"id":"00000000-0000-0000-0000-000000412502","enabled":false},{"id":"00000000-0000-0000-0000-000000412501","enabled":true}]'::jsonb));
  raise exception 'Admin subject accepted';exception when invalid_parameter_value then null;end;
end$t$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412502',true);
select set_config('fixture.new_request',gen_random_uuid()::text,true);
select set_config('fixture.new_doc',(public.solar_invoice_save(current_setting('fixture.new_request')::uuid,current_setting('fixture.post_payload')::jsonb)->>'id'),true);
select public.solar_invoice_save(current_setting('fixture.new_request')::uuid,current_setting('fixture.post_payload')::jsonb)->>'id';
reset role;

do $t$ declare receipt bigint:=current_setting('fixture.new_doc')::bigint; old_id bigint:=current_setting('fixture.old_doc')::bigint;begin
 if solar_private.personal_receipt_priced(old_id) or not solar_private.personal_receipt_priced(receipt) then raise exception 'Incorrect prospective scope';end if;
 if solar_private.personal_material_cost(receipt,500)<>580 or not solar_private.personal_line_has_price(receipt,-412511)
    or solar_private.personal_line_has_price(receipt,-412512)
    or (select count(*) from solar_private.personal_price_items where invoice_id=receipt)<>2 then raise exception 'Incorrect material fallback or duplicate snapshot';end if;
 if (select cost from public.transactions where id=receipt)<>500 or (select profit from public.transactions where id=receipt)<>600 then raise exception 'Company valuation changed';end if;
 if not((select permissions from public.profiles where id='00000000-0000-0000-0000-000000412502') @> '{"profit":true,"sale":true,"system":true,"profitUsesWholesalePrice":true}') then raise exception 'Other permissions lost';end if;
 if has_function_privilege('authenticated','solar_private.personal_line_cost(bigint,bigint,numeric)','execute') or has_table_privilege('authenticated','solar_private.personal_price_items','select') then raise exception 'Unscoped private pricing access';end if;
end$t$;

-- A wizard that predates the checkbox submits its full list of old keys.
select set_config('fixture.wizard_token',(solar_private.staff_wizard_user('00000000-0000-0000-0000-000000412502')->>'token'),true);
select public.solar_admin_user_wizard('00000000-0000-0000-0000-000000412501','finalize',gen_random_uuid(),
 jsonb_build_object('user_id','00000000-0000-0000-0000-000000412502','token',current_setting('fixture.wizard_token'),'role','user','active',true,
 'permissions','{"sale":true,"profit":true,"system":true}'::jsonb))->'user'->'permissions'->'profitUsesWholesalePrice';
do $t$begin if not solar_private.personal_price_enabled('00000000-0000-0000-0000-000000412502') then raise exception 'Older permission form cleared the policy';end if;end$t$;

-- Change the list and switch off the user. Existing products keep their old
-- reference/fallback when the normal invoice editor replaces every line.
update solar_private.wholesale_product_prices set minimum_price=180 where product_id=-412511;
update solar_private.wholesale_product_prices set enabled=true where product_id=-412512;
select set_config('fixture.revision',(select pricing_revision::text from public.transactions where id=current_setting('fixture.new_doc')::bigint),true);
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412501',true);
set local role authenticated;
select public.solar_profit_basis_users('save',gen_random_uuid(),jsonb_build_object('token',public.solar_profit_basis_users('state')->>'token',
 'changes','[{"id":"00000000-0000-0000-0000-000000412502","enabled":false}]'::jsonb))->>'token';
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412502',true);
select public.solar_invoice_save(gen_random_uuid(),current_setting('fixture.post_payload')::jsonb||
 jsonb_build_object('invoiceId',current_setting('fixture.new_doc')::bigint,'expectedRevision',current_setting('fixture.revision')::bigint,
 'items','[{"id":-412511,"qty":3,"price":250},{"id":-412512,"qty":1,"price":600},{"id":-412513,"qty":1,"price":1000}]'::jsonb))->>'id';
select set_config('fixture.later_doc',(public.solar_invoice_save(gen_random_uuid(),current_setting('fixture.post_payload')::jsonb)->>'id'),true);
reset role;
do $t$declare id bigint:=current_setting('fixture.new_doc')::bigint;begin
 if solar_private.personal_material_cost(id,1000)<>1620 or solar_private.personal_line_has_price(id,-412512) or
 not solar_private.personal_line_has_price(id,-412513) or solar_private.personal_receipt_priced(current_setting('fixture.later_doc')::bigint)
 then raise exception 'Basis changed on edit or later basis flag was ignored';end if;
 if not (solar_private.reset_snapshot() ?& array['solar_private.personal_price_receipts','solar_private.personal_price_items']) then raise exception 'Reset snapshot loses price history';end if;
end$t$;
rollback;
