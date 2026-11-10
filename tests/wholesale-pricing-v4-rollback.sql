\set ON_ERROR_STOP on
-- Isolated fixture only: all financial writes are rolled back.
begin;
insert into public.profiles(id,display_name,is_admin,user_type,phone,active,permissions)values
('00000000-0000-0000-0000-000000410001','مدير تسعير الجملة',true,'admin_staff','07700410001',true,'{}'),
('00000000-0000-0000-0000-000000410002','بائع تسعير الجملة',false,'admin_staff','07700410002',true,'{"sale":true,"warehouse":true}'),
('00000000-0000-0000-0000-000000410003','مسؤول أسعار بلا بيع حر',false,'admin_staff','07700410003',true,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000410004','بائع حر بلا إدارة أسعار',false,'admin_staff','07700410004',true,'{"sale":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000410005','مخزن تسعير الجملة',true,'warehouse','07700410005',true,'{"wholesalePricingManage":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000410006','مهندس تسعير الجملة',true,'installer','07700410006',true,'{"wholesalePricingManage":true,"wholesaleFreePricing":true}'),
('00000000-0000-0000-0000-000000410007','مستخدم غير فعال للتسعير',true,'admin_staff','07700410007',false,'{"sale":true,"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000410008','إدارة أسعار دون بيع',false,'admin_staff','07700410008',true,'{"wholesalePricingManage":true}'),
('00000000-0000-0000-0000-000000410009','بيع حر دون بيع',false,'admin_staff','07700410009',true,'{"wholesaleFreePricing":true}');
insert into public.products(id,code,name,qty,cost)values
(-410001,'WPF-A','مادة محددة السعر',1000,1000),
(-410002,'WPF-B','مادة غير محددة',1000,500),
(-410003,'WPF-C','مادة بسعر فارغ',1000,200),
(-410004,'WPF-D','مادة بسعر كسري',1000,100);
insert into public.customers(id,name,customer_type,owner_id)values
(-410001,'عميل بائع تسعير الجملة','wholesale','00000000-0000-0000-0000-000000410002'),
(-410002,'عميل مسؤول أسعار الجملة','wholesale','00000000-0000-0000-0000-000000410003'),
(-410003,'عميل البيع الحر للجملة','wholesale','00000000-0000-0000-0000-000000410004');
insert into public.solar_push_subscriptions(endpoint,user_id,p256dh,auth_key)values
('https://fcm.googleapis.com/fcm/send/local-wholesale-pricing-seller','00000000-0000-0000-0000-000000410002','local-key','local-auth');

create function pg_temp.wp_invoice(price numeric,invoice_id bigint default null,qty numeric default 1,product_id bigint default -410001)returns jsonb
language sql security definer set search_path=''as $$
 select jsonb_build_object('kind','sale','sourceCurrency','IQD','exchangeRate',1,'mode','credit',
  'party',case auth.uid()when'00000000-0000-0000-0000-000000410003'then'عميل مسؤول أسعار الجملة'when'00000000-0000-0000-0000-000000410004'then'عميل البيع الحر للجملة'else'عميل بائع تسعير الجملة'end,
  'notes','اختبار محلي للتسعير','expenses',0,'items',jsonb_build_array(jsonb_build_object('id',product_id,'qty',qty,'price',price)))
 ||case when invoice_id is null then'{}'::jsonb else jsonb_build_object('invoiceId',invoice_id,'expectedRevision',(select pricing_revision from public.transactions where id=invoice_id),'warehouseId',(select warehouse_id from public.transactions where id=invoice_id))end
$$;
create function pg_temp.wp_product(product_id bigint)returns jsonb language sql as $$
 select value from jsonb_array_elements(public.solar_wholesale_pricing('state')->'products')where(value->>'id')::bigint=product_id
$$;
create function pg_temp.wp_change(product_id bigint,price numeric,enabled boolean)returns jsonb language sql as $$
 select jsonb_build_object('productId',product_id,'minPrice',price,'enabled',enabled,'expectedRevision',pg_temp.wp_product(product_id)->'revision')
$$;
create function pg_temp.wp_financial_fingerprint()returns text language sql security definer set search_path=''as $$
 select md5(jsonb_build_object(
  'tx',(select jsonb_agg(to_jsonb(t)order by id)from public.transactions t),
  'items',(select jsonb_agg(to_jsonb(t)order by id)from public.transaction_items t),
  'products',(select jsonb_agg(jsonb_build_array(id,qty,cost,cost_basis,costing_revision)order by id)from public.products),
  'stock',(select jsonb_agg(to_jsonb(t)order by warehouse_id,product_id)from solar_private.warehouse_stocks t),
  'cash',(select jsonb_agg(to_jsonb(t)order by to_jsonb(t)::text)from public.cash_ledger t),
  'entries',(select jsonb_agg(to_jsonb(t)order by id)from public.solar_cash_entries t),
  'requests',(select jsonb_agg(to_jsonb(t)order by request_id)from solar_private.invoice_requests t))::text)
$$;
create function pg_temp.wp_item_fingerprint(invoice_id bigint)returns text language sql security definer set search_path=''as $$
 select md5(coalesce(jsonb_agg(jsonb_build_array(product_id,qty,price,cost,cost_basis)order by product_id),'[]')::text)from public.transaction_items where transaction_id=invoice_id
$$;
create function pg_temp.wp_warehouse_token(invoice_id bigint)returns text language sql security definer set search_path=''as $$select solar_private.warehouse_token(invoice_id)$$;
create function pg_temp.wp_notice_ids()returns uuid[] language sql security definer set search_path=''as $$select coalesce(array_agg(id),'{}'::uuid[])from public.solar_notifications$$;
create function pg_temp.wp_notice_count(before_ids uuid[])returns bigint language sql security definer set search_path=''as $$select count(*)from public.solar_notifications where id<>all(before_ids)$$;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410002',true);
do $$declare s jsonb;r jsonb;nonce uuid:=gen_random_uuid();begin
 s:=public.solar_wholesale_pricing('state');
 if(s->>'enabled')::boolean then raise exception 'Global wholesale limit is not off by default';end if;
 if(s->>'canManage')::boolean or(s->>'canOverride')::boolean then raise exception 'Plain seller gained pricing privileges';end if;
 if pg_temp.wp_product(-410001)->>'minPrice'is not null or coalesce((pg_temp.wp_product(-410001)->>'enabled')::boolean,false)then raise exception 'New products do not start without restriction';end if;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410001,1250,true))));raise exception 'FAIL seller can manage minimum';exception when insufficient_privilege then null;end;
 begin perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',true,'expectedRevision',s->'revision'));raise exception 'FAIL seller can toggle global minimum';exception when insufficient_privilege then null;end;
 r:=public.solar_invoice_save(nonce,pg_temp.wp_invoice(900));perform set_config('test.wp.legacy',r->>'id',true);perform set_config('test.wp.legacyNonce',nonce::text,true);perform set_config('test.wp.legacyResult',r::text,true);
 perform set_config('test.wp.legacyItems',pg_temp.wp_item_fingerprint((r->>'id')::bigint),true);
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(900));perform set_config('test.wp.warehouseLegacy',r->>'id',true);
end$$;
set constraints all immediate;
set constraints all deferred;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410003',true);
do $$declare s jsonb;r jsonb;b jsonb;nonce uuid:=gen_random_uuid();before_hash text:=pg_temp.wp_financial_fingerprint();begin
 s:=public.solar_wholesale_pricing('state');
 if not(s->>'canManage')::boolean or(s->>'canOverride')::boolean then raise exception 'Manage permission implies free pricing or is missing';end if;
 b:=jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410001,1250,true),pg_temp.wp_change(-410002,1500,false),pg_temp.wp_change(-410003,null,false),pg_temp.wp_change(-410004,100.01,true)));
 r:=public.solar_wholesale_pricing('save',nonce,b);
 if public.solar_wholesale_pricing('save',nonce,b)<>r then raise exception 'Policy save replay differs';end if;
 if(pg_temp.wp_product(-410001)->>'minPrice')::numeric<>1250 or not(pg_temp.wp_product(-410001)->>'enabled')::boolean then raise exception 'Checked minimum not saved';end if;
 if(pg_temp.wp_product(-410002)->>'minPrice')::numeric<>1500 or(pg_temp.wp_product(-410002)->>'enabled')::boolean then raise exception 'Unchecked minimum lost or unexpectedly enabled';end if;
 if pg_temp.wp_product(-410003)->>'minPrice'is not null or(pg_temp.wp_product(-410003)->>'enabled')::boolean then raise exception 'Blank minimum did not remain unset';end if;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),b);raise exception 'FAIL stale product revision';exception when sqlstate'PT409'then null;end;
 begin perform public.solar_wholesale_pricing('save',nonce,jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410001,1350,true))));raise exception 'FAIL nonce permits changed settings';exception when sqlstate'PT409'then null;end;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,null,true))));raise exception 'FAIL checked blank minimum';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,0,true))));raise exception 'FAIL checked zero minimum';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,1,false)||jsonb_build_object('productId',-410003.25))));raise exception 'FAIL fractional product id';exception when sqlstate'22023'then null;end;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,1,false)||jsonb_build_object('expectedRevision',(pg_temp.wp_product(-410003)->>'revision')::numeric+0.25))));raise exception 'FAIL fractional product revision';exception when sqlstate'22023'then null;end;
 begin perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',true,'expectedRevision',(public.solar_wholesale_pricing('state')->>'revision')::numeric+0.25));raise exception 'FAIL fractional global revision';exception when sqlstate'22023'then null;end;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Saving product policy changed historical finance or stock';end if;
end$$;
-- Management does not require sale permission, and clearing a saved value is
-- distinct from merely unchecking a product while retaining its saved price.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410008',true);
do $$declare s jsonb;begin
 s:=public.solar_wholesale_pricing('state');if not(s->>'canManage')::boolean or(s->>'canOverride')::boolean then raise exception 'Manager-only permission unusable';end if;
 perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,450,false))));
 if(pg_temp.wp_product(-410003)->>'minPrice')::numeric<>450 then raise exception 'Unchecked stored value missing';end if;
 perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410003,null,false))));
 if pg_temp.wp_product(-410003)->>'minPrice'is not null then raise exception 'Clearing existing minimum failed';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));raise exception 'FAIL manager-only permission grants sale';exception when insufficient_privilege then null;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410009',true);
do $$begin
 begin perform public.solar_wholesale_pricing('state');raise exception 'FAIL free-only permission grants catalogue access';exception when insufficient_privilege then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));raise exception 'FAIL free-only permission grants sale';exception when insufficient_privilege then null;end;
end$$;
-- A configured product remains unrestricted until the global switch is on.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410002',true);
do $$declare r jsonb;begin r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(800));if(r->>'total')::numeric<>800 then raise exception 'Product checkbox ignored global off switch';end if;end$$;
set constraints all immediate;
set constraints all deferred;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410003',true);
do $$declare s jsonb;r jsonb;b jsonb;nonce uuid:=gen_random_uuid();n bigint;before_ids uuid[]:=pg_temp.wp_notice_ids();before_hash text:=pg_temp.wp_financial_fingerprint();begin
 s:=public.solar_wholesale_pricing('state');b:=jsonb_build_object('enabled',true,'expectedRevision',s->'revision');
 r:=public.solar_wholesale_pricing('toggle',nonce,b);n:=pg_temp.wp_notice_count(before_ids);
 if not(public.solar_wholesale_pricing('state')->>'enabled')::boolean then raise exception 'Global limit not enabled';end if;
 if n=0 then raise exception 'Global activation issued no notification';end if;
 if public.solar_wholesale_pricing('toggle',nonce,b)<>r or pg_temp.wp_notice_count(before_ids)<>n then raise exception 'Activation replay duplicated notices or changed response';end if;
 begin perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),b);raise exception 'FAIL stale global revision';exception when sqlstate'PT409'then null;end;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Global activation changed historical finance or stock';end if;
 perform set_config('test.wp.activationNoticeAfter',before_ids::text,true);
 perform set_config('test.wp.activationNoticeUntil',pg_temp.wp_notice_ids()::text,true);
end$$;
reset role;
do $$declare recipient uuid;begin
 foreach recipient in array array['00000000-0000-0000-0000-000000410002','00000000-0000-0000-0000-000000410003','00000000-0000-0000-0000-000000410004','00000000-0000-0000-0000-000000410008']::uuid[]loop
  if not exists(select 1 from public.solar_notifications where user_id=recipient and id<>all(current_setting('test.wp.activationNoticeAfter')::uuid[]) and id=any(current_setting('test.wp.activationNoticeUntil')::uuid[]))then raise exception 'Eligible pricing recipient missing: %',recipient;end if;
 end loop;
 if exists(select 1 from public.solar_notifications where id<>all(current_setting('test.wp.activationNoticeAfter')::uuid[]) and id=any(current_setting('test.wp.activationNoticeUntil')::uuid[]) and(user_id in('00000000-0000-0000-0000-000000410005','00000000-0000-0000-0000-000000410006','00000000-0000-0000-0000-000000410007','00000000-0000-0000-0000-000000410009')or(title||' '||coalesce(body,''))~'(1250|1,250|1500|1,500|100\.01)'))then raise exception 'Pricing notices exposed amounts or reached restricted/inactive roles';end if;
 if exists(select 1 from public.solar_notifications where id<>all(current_setting('test.wp.activationNoticeAfter')::uuid[])and id=any(current_setting('test.wp.activationNoticeUntil')::uuid[])and position('مسؤول أسعار بلا بيع حر'in coalesce(body,''))=0)then raise exception 'Toggle notification omitted actor name';end if;
 if not exists(select 1 from solar_private.push_deliveries d join public.solar_notifications n on n.id=d.notification_id where n.id<>all(current_setting('test.wp.activationNoticeAfter')::uuid[]) and n.id=any(current_setting('test.wp.activationNoticeUntil')::uuid[]) and n.user_id='00000000-0000-0000-0000-000000410002')then raise exception 'Activation push not queued';end if;
end$$;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410002',true);
do $$declare r jsonb;nonce uuid:=gen_random_uuid();before_hash text:=pg_temp.wp_financial_fingerprint();id bigint:=current_setting('test.wp.legacy')::bigint;begin
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1249.99));set constraints all immediate;raise exception 'FAIL below floor accepted';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1200)||'{"expenses":10000}');set constraints all immediate;raise exception 'FAIL fees subsidize below-floor product';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1000)||'{"wholesaleFreePricing":true,"override":true,"minPrice":0}');set constraints all immediate;raise exception 'FAIL forged client override';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1250)||'{"items":[{"id":-410001,"qty":1,"price":1200},{"id":-410002,"qty":1,"price":5000}]}');set constraints all immediate;raise exception 'FAIL another line subsidizes below-floor product';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1)||'{"exchangeRate":2000,"marketRate":2000}');set constraints all immediate;raise exception 'FAIL client rate bypassed IQD floor';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1250)||'{"wholesalePricingRevision":-1}');set constraints all immediate;raise exception 'FAIL stale invoice pricing revision';exception when sqlstate'PT409'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(1)||'{"sourceCurrency":"USD","exchangeRate":2000}');raise exception 'FAIL unsupported wholesale currency accepted';exception when raise_exception then if sqlerrm='FAIL unsupported wholesale currency accepted'then raise;end if;end;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Rejected sale left stock, accounting, or nonce effects';end if;
 r:=public.solar_invoice_save(nonce,pg_temp.wp_invoice(1250));perform set_config('test.wp.bound',r->>'id',true);perform set_config('test.wp.boundNonce',nonce::text,true);perform set_config('test.wp.boundResult',r::text,true);
 if(r->>'total')::numeric<>1250 or(r->>'cost')::numeric<>1000 or(r->>'profit')::numeric<>250 then raise exception 'Exact floor changed financial calculation %',r;end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(2000));if(r->>'total')::numeric<>2000 then raise exception 'Higher price not preserved';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100,null,1,-410002));if(r->>'total')::numeric<>100 then raise exception 'Unchecked product got floor';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(50,null,1,-410003));if(r->>'total')::numeric<>50 then raise exception 'Blank product got floor';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100,null,1,-410004));set constraints all immediate;raise exception 'FAIL fractional floor rounded down';exception when sqlstate'PT422'then null;end;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100.01,null,1,-410004));if(r->>'total')::numeric<>100.01 then raise exception 'Exact fractional floor rejected or rounded';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(900,id)||'{"notes":"تعديل ملاحظة تاريخية فقط"}');
 if(r->>'total')::numeric<>900 or pg_temp.wp_item_fingerprint(id)<>current_setting('test.wp.legacyItems')then raise exception 'Historical metadata edit repriced or recosted lines';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(950,id));set constraints all immediate;raise exception 'FAIL economic price edit grandfathered';exception when sqlstate'PT422'then null;end;
 begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(900,id,2));set constraints all immediate;raise exception 'FAIL quantity edit grandfathered';exception when sqlstate'PT422'then null;end;
 if public.solar_invoice_save(current_setting('test.wp.legacyNonce')::uuid,pg_temp.wp_invoice(900))<>current_setting('test.wp.legacyResult')::jsonb then raise exception 'Original pre-policy retry repriced historical response';end if;
end$$;
set constraints all immediate;
set constraints all deferred;

-- Editing through warehouse quantity API must not bypass the same price floor.
do $$declare invoice_id bigint:=current_setting('test.wp.warehouseLegacy')::bigint;lines jsonb;before_hash text:=pg_temp.wp_financial_fingerprint();begin
 select jsonb_agg(jsonb_build_object('lineId',i.id,'productId',i.product_id,'qty',i.qty+1))into lines from public.transaction_items i where i.transaction_id=invoice_id;
 begin perform public.solar_warehouse_action(invoice_id,pg_temp.wp_warehouse_token(invoice_id),'save',lines,'تعديل كمية محلي');set constraints all immediate;raise exception 'FAIL warehouse quantity bypass';exception when sqlstate'PT422'then null;end;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Rejected warehouse amendment changed stock/accounts';end if;
end$$;
-- Direct protected RPC-table writes are forbidden independently of the floor.
do $$begin
 begin update public.transaction_items set price=1 where transaction_id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL direct authenticated financial write';exception when insufficient_privilege then null;end;
 begin update public.transactions set kind='purchase'where id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL direct authenticated sale kind rewrite';exception when insufficient_privilege then null;end;
end$$;

-- Trigger-level protection also covers trusted legacy writers that do not use
-- solar_invoice_save. Keep the seller's JWT while using the local fixture owner.
reset role;
set constraints all immediate;
do $$declare before_hash text:=pg_temp.wp_financial_fingerprint();begin
 begin update public.transactions set subtotal=1000,total=1000,profit=0 where id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL legacy header discount bypass';exception when sqlstate'PT422'then null;end;
 begin update public.transaction_items set price=500 where transaction_id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL legacy line price bypass';exception when sqlstate'PT422'then null;end;
 begin update public.transaction_items set price='NaN'::numeric where transaction_id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL NaN legacy unit price';exception when sqlstate'PT422'then null;end;
 begin update public.transactions set subtotal='NaN'::numeric,total='NaN'::numeric where id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL NaN legacy total';exception when sqlstate'PT422'then null;end;
 begin update public.transactions set source_currency='USD'where id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL legacy wholesale currency rewrite';exception when sqlstate'PT422'then null;end;
 begin update public.transactions set exchange_rate=2000 where id=current_setting('test.wp.bound')::bigint;raise exception 'FAIL legacy wholesale exchange-rate rewrite';exception when sqlstate'PT422'then null;end;
 begin set constraints all deferred;update public.transaction_items set product_id=null where transaction_id=current_setting('test.wp.legacy')::bigint;set constraints solar_wholesale_item_pricing_check immediate;raise exception 'FAIL legacy removes checked product identity';exception when sqlstate'PT422'then null;end;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Rejected legacy price mutation survived';end if;
end$$;
set constraints all deferred;
set local role authenticated;
-- The two new permissions remain independent, and existing admins bypass floors.
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410003',true);
do $$begin begin perform public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));set constraints all immediate;raise exception 'FAIL manager received free price privilege';exception when sqlstate'PT422'then null;end;end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410004',true);
do $$declare s jsonb;r jsonb;begin
 s:=public.solar_wholesale_pricing('state');if(s->>'canManage')::boolean or not(s->>'canOverride')::boolean then raise exception 'Free-price permission does not remain independent';end if;
 begin perform public.solar_wholesale_pricing('save',gen_random_uuid(),jsonb_build_object('items',jsonb_build_array(pg_temp.wp_change(-410001,1,true))));raise exception 'FAIL free seller can configure policy';exception when insufficient_privilege then null;end;
 begin perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',false,'expectedRevision',s->'revision'));raise exception 'FAIL free seller can toggle';exception when insufficient_privilege then null;end;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));if(r->>'total')::numeric<>100 then raise exception 'Free seller could not override';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410001',true);
do $$declare s jsonb;r jsonb;begin
 s:=public.solar_wholesale_pricing('state');if not(s->>'canManage')::boolean or not(s->>'canOverride')::boolean then raise exception 'Admin privilege compatibility lost';end if;
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));if(r->>'total')::numeric<>100 then raise exception 'Admin bypass failed';end if;
end$$;
set constraints all immediate;
set constraints all deferred;
-- Role type and active status still dominate stale permission/admin flags.
do $$declare actor uuid;begin
 foreach actor in array array['00000000-0000-0000-0000-000000410005','00000000-0000-0000-0000-000000410006','00000000-0000-0000-0000-000000410007']::uuid[]loop
  perform set_config('request.jwt.claim.sub',actor::text,true);
  begin perform public.solar_wholesale_pricing('state');raise exception 'FAIL restricted role pricing access';exception when insufficient_privilege then null;end;
  begin perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),'{"enabled":false,"expectedRevision":0}');raise exception 'FAIL restricted role pricing update';exception when insufficient_privilege then null;end;
 end loop;
end$$;

select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410003',true);
do $$declare before_hash text:=pg_temp.wp_financial_fingerprint();rows_before jsonb;begin
 rows_before:=public.solar_wholesale_pricing('state')->'products';
 perform public.solar_wholesale_pricing('toggle',gen_random_uuid(),jsonb_build_object('enabled',false,'expectedRevision',public.solar_wholesale_pricing('state')->'revision'));
 if public.solar_wholesale_pricing('state')->'products'<>rows_before then raise exception 'Global off erased product limits or flags';end if;
 if pg_temp.wp_financial_fingerprint()<>before_hash then raise exception 'Global off mutated historical finance';end if;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000410002',true);
do $$declare r jsonb;begin
 r:=public.solar_invoice_save(gen_random_uuid(),pg_temp.wp_invoice(100));if(r->>'total')::numeric<>100 then raise exception 'Global off did not restore free prices';end if;
 if public.solar_invoice_save(current_setting('test.wp.boundNonce')::uuid,pg_temp.wp_invoice(1250))<>current_setting('test.wp.boundResult')::jsonb then raise exception 'Invoice replay changed after global off';end if;
end$$;
reset role;
do $$begin
 if has_function_privilege('anon','public.solar_wholesale_pricing(text,uuid,jsonb)','execute')then raise exception 'Anonymous wholesale policy access';end if;
 if has_table_privilege('authenticated','solar_private.wholesale_product_prices','select')or has_table_privilege('authenticated','solar_private.wholesale_pricing_control','update')or has_table_privilege('authenticated','solar_private.wholesale_invoice_pricing','select')or has_table_privilege('authenticated','solar_private.wholesale_pricing_audit','select')then raise exception 'Private policy tables exposed';end if;
 if has_function_privilege('authenticated','solar_private.assert_wholesale_pricing(bigint,bigint)','execute')or has_function_privilege('authenticated','solar_private.wholesale_economic_signature(bigint)','execute')then raise exception 'Internal enforcement helper exposed';end if;
 if not exists(select 1 from solar_private.wholesale_pricing_audit where actor_id='00000000-0000-0000-0000-000000410003'and action='toggle')or not exists(select 1 from solar_private.wholesale_pricing_audit where actor_id='00000000-0000-0000-0000-000000410008'and product_id=-410003 and action='product')then raise exception 'Policy audit trail missing';end if;

 raise notice 'PASS default off, checked products, blank limits, independent permissions, revision/replay, private notifications, per-product net floor, historical metadata, warehouse/direct guards and atomic finances';
end$$;
set constraints all immediate;
rollback;
