\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,permissions) values
('00000000-0000-0000-0000-000000003380','مدير اختبار التعديل','edit_admin',true,'{}'),
('00000000-0000-0000-0000-000000003381','موظف اختبار التعديل','edit_staff',false,'{"customerPayment":true,"customerStatement":true,"sale":true,"cash":true}'),
('00000000-0000-0000-0000-000000003382','مستخدم آخر','edit_other',false,'{"customerPayment":true,"sale":true}');
insert into products(id,code,name,qty,cost) values(-338001,'EDIT-1','لوح تعديل',100,100);
insert into customers(id,name,customer_type,owner_id) values(-338001,'زبون تعديل','wholesale','00000000-0000-0000-0000-000000003381');
insert into transactions(id,kind,party_id,party_name,total,cash,payment_mode,created_by,cashbox_user_id) values(-338001,'customer_payment',-338001,'زبون تعديل',-1000,false,'opening_balance','00000000-0000-0000-0000-000000003381','00000000-0000-0000-0000-000000003381');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003380',true);
select public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003381","mode":"deposit","currency":"IQD","amount":500,"note":"رصيد اختبار"}');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003381',true);
do $$declare inv jsonb;pay jsonb;a jsonb;r jsonb;edit jsonb;body jsonb;invbody jsonb;rid uuid:=gen_random_uuid();editid uuid:=gen_random_uuid();delid uuid:=gen_random_uuid();paybody jsonb;beforeqty numeric;beforecost numeric;beforeprofit numeric;begin
 invbody:='{"kind":"sale","party":"زبون تعديل","mode":"credit","items":[{"id":-338001,"qty":2,"price":250}],"notes":"فاتورة تعديل","sourceCurrency":"IQD","exchangeRate":1,"expenses":0}';
 inv:=public.solar_invoice_save(gen_random_uuid(),invbody);
 select qty into beforeqty from products where id=-338001;
 select cost,profit into beforecost,beforeprofit from transactions where id=(inv->>'id')::bigint;
 a:=public.solar_customer_payment_context(-338001);if (a->>'balance')::numeric<>1500 then raise exception 'initial account';end if;
 paybody:=jsonb_build_object('customerId',-338001,'amount',200,'mode','payment','notes','تسديد قابل للتعديل','expectedToken',a->>'token');pay:=public.solar_customer_payment_save(rid,paybody);
 r:=public.solar_customer_payment_manage('list',null,'{"query":"زبون تعديل"}');if jsonb_array_length(r->'rows')<>1 then raise exception 'receipt missing from search';end if;
 a:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',pay->'id'));
 if (a->>'balance')::numeric<>1300 or (a->>'cashBalance')::numeric<>700 then raise exception 'receipt effects';end if;
 body:=jsonb_build_object('id',pay->'id','expectedToken',a->>'token','amount',100,'notes','تعديل إلى مئة');
 edit:=public.solar_customer_payment_manage('update',editid,body);
 if (edit->>'remaining')::numeric<>1400 or(edit->>'cashAfter')::numeric<>600 then raise exception 'edit effects';end if;
 if public.solar_customer_payment_manage('update',editid,body)<>edit then raise exception 'update retry';end if;
 begin perform public.solar_customer_payment_manage('update',gen_random_uuid(),body);raise exception 'stale edit accepted';exception when serialization_failure or sqlstate 'PT409' then null;end;
 a:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',pay->'id'));
 body:=jsonb_build_object('id',pay->'id','expectedToken',a->>'token');
 r:=public.solar_customer_payment_manage('delete',delid,body);
 if (r->>'remaining')::numeric<>1500 or(r->>'cashAfter')::numeric<>500 then raise exception 'delete effects';end if;
 if public.solar_customer_payment_manage('delete',delid,body)<>r then raise exception 'delete retry';end if;
 begin perform public.solar_customer_payment_save(rid,paybody);raise exception 'stale create replay accepted';exception when serialization_failure or sqlstate 'PT409' then null;end;
 begin perform public.solar_customer_payment_manage('get',null,'{"id":-338001}');raise exception 'opening can edit';exception when serialization_failure or sqlstate 'PT409' then null;end;
 -- Credit → cash → credit: original cash owner and frozen quantities/costs/profit.
 invbody:=invbody||jsonb_build_object('invoiceId',inv->'id','expectedRevision',inv->'pricingRevision','mode','cash');inv:=public.solar_invoice_save(gen_random_uuid(),invbody);
 a:=public.solar_customer_payment_context(-338001);if(a->>'balance')::numeric<>1000 or(a->>'cashBalance')::numeric<>1000 then raise exception 'credit to cash';end if;
 if(select not cash or payment_mode<>'cash' from transactions where id=(inv->>'id')::bigint) then raise exception 'mode not saved';end if;
 invbody:=invbody||jsonb_build_object('expectedRevision',inv->'pricingRevision','mode','credit');inv:=public.solar_invoice_save(gen_random_uuid(),invbody);
 a:=public.solar_customer_payment_context(-338001);if(a->>'balance')::numeric<>1500 or(a->>'cashBalance')::numeric<>500 then raise exception 'cash to credit';end if;
 if(select qty<>beforeqty from products where id=-338001) or(select cost<>beforecost or profit<>beforeprofit or cash from transactions where id=(inv->>'id')::bigint) then raise exception 'stock/profit changed';end if;
 -- Other staff cannot read/edit another account's receipt or invoice.
 pay:=public.solar_customer_payment_save(gen_random_uuid(),jsonb_build_object('customerId',-338001,'amount',200,'mode','payment','expectedToken',a->>'token'));
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003382',true);
 begin perform public.solar_customer_payment_manage('get',null,jsonb_build_object('id',pay->'id'));raise exception 'other staff read';exception when insufficient_privilege then null;end;
 r:=public.solar_customer_payment_manage('list');if jsonb_array_length(r->'rows')<>0 then raise exception 'other staff listing';end if;
 begin perform public.solar_invoice_save(gen_random_uuid(),invbody||jsonb_build_object('expectedRevision',inv->'pricingRevision','mode','cash'));raise exception 'other staff invoice';exception when insufficient_privilege then null;end;
 -- Administrator edits staff receipt; changes remain in staff's cashbox.
 perform set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003380',true);
 a:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',pay->'id'));
 r:=public.solar_customer_payment_manage('update',gen_random_uuid(),jsonb_build_object('id',pay->'id','expectedToken',a->>'token','amount',150,'notes','تعديل المدير'));
 if(r->>'cashAfter')::numeric<>650 then raise exception 'wrong admin cash owner';end if;
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003381","mode":"expense","currency":"IQD","amount":600,"note":"اختبار عدم كفاية الرصيد"}');
 a:=public.solar_customer_payment_manage('get',null,jsonb_build_object('id',pay->'id'));
 begin perform public.solar_customer_payment_manage('delete',gen_random_uuid(),jsonb_build_object('id',pay->'id','expectedToken',a->>'token'));raise exception 'negative cash delete';exception when sqlstate 'P0002' then null;end;
 begin perform public.solar_customer_payment_manage('update',gen_random_uuid(),jsonb_build_object('id',pay->'id','expectedToken',a->>'token','amount',10));raise exception 'negative cash edit';exception when sqlstate 'P0002' then null;end;
 -- Change to cash adds 500; spending it blocks reversal back to credit.
 invbody:=invbody||jsonb_build_object('expectedRevision',inv->'pricingRevision','mode','cash');inv:=public.solar_invoice_save(gen_random_uuid(),invbody);
 perform public.solar_cash_save(gen_random_uuid(),'{"ownerId":"00000000-0000-0000-0000-000000003381","mode":"expense","currency":"IQD","amount":100,"note":"صرف بعد البيع"}');
 begin perform public.solar_invoice_save(gen_random_uuid(),invbody||jsonb_build_object('expectedRevision',inv->'pricingRevision','mode','credit'));raise exception 'negative cash conversion';exception when sqlstate 'P0002' then null;end;
 raise notice 'PASS receipt update/delete/retry/stale tokens/scope, cash↔credit, preserved stock and profit, original cashbox and insufficient funds';
end $$;
reset role;
do $$begin if(select count(*) from solar_private.receipt_change_audit)<>6 then raise exception 'audit count';end if;end$$;
rollback;
