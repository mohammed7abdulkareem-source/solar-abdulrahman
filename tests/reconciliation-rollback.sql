begin;
do $$declare actor uuid; other_actor uuid;begin
 select id into actor from public.profiles where active and not is_admin and user_type='admin_staff' order by created_at limit 1;
 select id into other_actor from public.profiles where active and id<>actor order by created_at limit 1;
 if actor is null or other_actor is null then raise exception 'Need two profiles';end if;
 perform set_config('reconcile_test.actor',actor::text,true);perform set_config('reconcile_test.other',other_actor::text,true);
 update public.profiles set permissions='{"customers":true,"customerStatement":true,"customerReconcile":true,"stockAdjust":true,"stockMovement":true,"customerDebts":true}' where id=actor;
 insert into public.products(id,code,name,qty,cost) values(-932801,'TEST328','TEST STOCK',10,125);
 insert into public.customers(id,name,customer_type,owner_id) values(-932802,'TEST OTHER','wholesale',other_actor);
end $$;
set local role authenticated;
do $$declare r jsonb; x jsonb; ledger jsonb; req uuid=gen_random_uuid(); stock_req uuid=gen_random_uuid(); payload jsonb;begin
 perform set_config('request.jwt.claim.sub',current_setting('reconcile_test.actor'),true);
 payload:=jsonb_build_object('id',-932801,'name','TEST OPENING','customerType','wholesale','openingBalance',1000);
 r:=public.solar_reconcile('create_customer',req,payload);
 x:=public.solar_reconcile('create_customer',req,payload);
 if x<>r then raise exception 'FAIL retry';end if;
 ledger:=public.solar_customer_statement(-932801);
 if (ledger->>'balance')::numeric<>1000 or jsonb_array_length(ledger->'rows')<>1 or ledger->'rows'->0->>'mode'<>'opening_balance' then raise exception 'FAIL opening ledger';end if;
 begin perform public.solar_reconcile('create_customer',req,payload||'{"openingBalance":2000}');raise exception 'FAIL changed retry';exception when serialization_failure then null;end;
 begin perform public.solar_customer_statement(-932802);raise exception 'FAIL other ledger';exception when insufficient_privilege then null;end;
 begin perform public.solar_reconcile('customer_balance',gen_random_uuid(),'{"customerId":-932802,"actual":0}');raise exception 'FAIL other match';exception when insufficient_privilege then null;end;
 r:=public.solar_reconcile('customer_balance',gen_random_uuid(),jsonb_build_object('customerId',-932801,'actual',-50,'token',ledger->>'token','note','TEST matching'));
 if (r->>'delta')::numeric<>-1050 then raise exception 'FAIL match difference';end if;
 begin perform public.solar_reconcile('customer_balance',gen_random_uuid(),jsonb_build_object('customerId',-932801,'actual',0,'token',ledger->>'token','note','TEST stale'));raise exception 'FAIL stale ledger';exception when serialization_failure then null;end;
 ledger:=public.solar_customer_statement(-932801);
 if (ledger->>'balance')::numeric<>-50 then raise exception 'FAIL matched balance';end if;
 select value into x from jsonb_array_elements(public.solar_party_balances('customers',(now() at time zone 'Asia/Baghdad')::date)->'rows') where value->>'id'='-932801';
 if (x->>'balance')::numeric<>-50 or x->>'last_payment' is not null then raise exception 'FAIL debtor total/last payment';end if;
 if exists(select 1 from public.transactions where party_id=-932801 and (cash or cost<>0 or profit<>0)) then raise exception 'FAIL cash/profit impact';end if;
 begin update public.transactions set total=0 where party_id=-932801;raise exception 'FAIL direct update';exception when insufficient_privilege then null;end;
 r:=public.solar_reconcile('stock_balance',stock_req,'{"productId":-932801,"expected":10,"actual":7,"note":"TEST physical count"}');
 x:=public.solar_reconcile('stock_balance',stock_req,'{"productId":-932801,"expected":10,"actual":7,"note":"TEST physical count"}');
 if x<>r or (r->>'delta')::numeric<>-3 then raise exception 'FAIL stock retry';end if;
 x:=public.solar_stock_movements(-932801);
 if jsonb_array_length(x)<>1 or (x->0->>'balance')::numeric<>7 or (x->0->>'outQty')::numeric<>3 or x->0->>'kind'<>'stock_adjustment' then raise exception 'FAIL stock journal';end if;
 begin perform public.solar_reconcile('stock_balance',gen_random_uuid(),'{"productId":-932801,"expected":10,"actual":5,"note":"stale"}');raise exception 'FAIL stale stock';exception when serialization_failure then null;end;
 begin perform public.solar_reconcile('stock_balance',gen_random_uuid(),'{"productId":-932801,"expected":7,"actual":-1,"note":"invalid"}');raise exception 'FAIL negative stock';exception when raise_exception then if sqlerrm='FAIL negative stock' then raise;end if;end;
 r:=public.solar_reconcile('stock_balance',gen_random_uuid(),'{"productId":-932801,"expected":7,"actual":12,"note":"TEST increase"}');
 x:=public.solar_stock_movements(-932801);
 if (x->1->>'balance')::numeric<>12 or (x->1->>'inQty')::numeric<>5 then raise exception 'FAIL increase';end if;
 r:=public.solar_reconcile('create_customer',gen_random_uuid(),'{"id":-932803,"name":"TEST NO OPENING","customerType":"system","openingBalance":null}');
 ledger:=public.solar_customer_statement(-932803);
 if jsonb_array_length(ledger->'rows')<>0 then raise exception 'FAIL unchecked opening';end if;
end $$;
reset role;
do $$declare ledger jsonb;begin
 -- Receipt by a different operator still appears in the assigned customer's ledger.
 insert into public.transactions(id,kind,party_id,party_name,total,cash,created_by) values
 (-932801,'sale',-932801,'OLD NAME',900,true,current_setting('reconcile_test.other')::uuid),
 (-932802,'customer_payment',-932801,'OLD NAME',25,true,current_setting('reconcile_test.other')::uuid);
 perform set_config('request.jwt.claim.sub',current_setting('reconcile_test.actor'),true);
 ledger:=public.solar_customer_statement(-932801);
 if (ledger->>'balance')::numeric<>-75 or jsonb_array_length(ledger->'rows')<>4 then raise exception 'FAIL full customer scope or cash sale';end if;
 if (select qty from public.products where id=-932801)<>12 or (select cost from public.products where id=-932801)<>125 then raise exception 'FAIL stock update/cost';end if;
 if not(solar_private.reset_snapshot() ? 'solar_private.stock_adjustments') or not(solar_private.reset_snapshot() ? 'solar_private.reconciliation_requests') then raise exception 'FAIL reset coverage';end if;
 update public.profiles set permissions='{}' where id=current_setting('reconcile_test.actor')::uuid;
end $$;
set local role authenticated;
do $$begin
 begin perform public.solar_reconcile('stock_balance',gen_random_uuid(),'{"productId":-932801,"expected":12,"actual":5,"note":"denied"}');raise exception 'FAIL denied stock';exception when insufficient_privilege then null;end;
 begin perform public.solar_reconcile('create_customer',gen_random_uuid(),'{"id":-932804,"name":"DENIED","customerType":"system"}');raise exception 'FAIL denied create';exception when insufficient_privilege then null;end;
 begin perform public.solar_customer_statement(-932801);raise exception 'FAIL denied statement';exception when insufficient_privilege then null;end;
end $$;
reset role;
rollback;
