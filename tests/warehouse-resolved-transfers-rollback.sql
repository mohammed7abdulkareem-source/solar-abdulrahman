\set ON_ERROR_STOP on
begin;
do $test$
declare
 source_id bigint; destination_id bigint; worker uuid:=gen_random_uuid();
 marker text:='queue-'||gen_random_uuid()::text;
 request jsonb; page_one jsonb; page_two jsonb; response jsonb;
begin
 insert into solar_private.warehouses(name,code) values(marker||'-source',marker||'-s') returning id into source_id;
 insert into solar_private.warehouses(name,code) values(marker||'-destination',marker||'-d') returning id into destination_id;
 insert into public.profiles(id,username,display_name,user_type,is_admin,active)
 values(worker,marker,'Warehouse queue test','warehouse',false,true);
 insert into solar_private.warehouse_access(user_id,warehouse_ids) values(worker,array[source_id]);
 insert into solar_private.stock_transfers(id,from_id,to_id,from_name,to_name,actor_id,actor_name,status,items)
 select gen_random_uuid(),source_id,destination_id,'Test source','Test destination',worker,marker,
  (array['pending','posted','cancelled','reversed'])[1+i%4],'[{"name":"Test item","qty":1}]'::jsonb
 from generate_series(0,43) i;
 -- The worker cannot see the destination warehouse's outgoing request.
 insert into solar_private.stock_transfers(id,from_id,to_id,from_name,to_name,actor_id,actor_name,status,items)
 values(gen_random_uuid(),destination_id,source_id,'Test destination','Test source',worker,marker,'cancelled','[]');

 perform set_config('request.jwt.claim.sub',worker::text,true);
 request:=jsonb_build_object('search',marker,'state','resolved');
 page_one:=public.solar_inventory('transfer_queue',null,request);
 page_two:=public.solar_inventory('transfer_queue',null,request||'{"offset":30}'::jsonb);
 if (page_one->'statusCounts')<>'{"all":44,"pending":11,"resolved":33,"posted":11,"cancelled":11,"reversed":11}'::jsonb
 or (page_one->>'count')::integer<>33 or jsonb_array_length(page_one->'rows')<>30 or jsonb_array_length(page_two->'rows')<>3 then
  raise exception 'Incorrect scoped counts or pagination for resolved transfers';
 end if;
 if (select count(distinct x->>'id') from jsonb_array_elements((page_one->'rows')||(page_two->'rows')) x)<>33
 or exists(select 1 from jsonb_array_elements((page_one->'rows')||(page_two->'rows')) x where x->>'status'='pending' or (x->>'canPrepare')::boolean) then
  raise exception 'Duplicated page or actionable resolved transfer';
 end if;
 response:=public.solar_inventory('transfer_queue',null,request||'{"state":"posted"}'::jsonb);
 if (response->>'count')::integer<>11 then raise exception 'Posted filter must retain original meaning';end if;
 response:=public.solar_inventory('transfer_queue',null,request||'{"state":"pending"}'::jsonb);
 if (response->>'count')::integer<>11 or exists(select 1 from jsonb_array_elements(response->'rows') x where x->>'status'<>'pending') then
  raise exception 'Incorrect actionable queue';
 end if;
 response:=public.solar_inventory('transfer_queue',null,request||jsonb_build_object('search',marker||'-missing'));
 if (response->'statusCounts'->>'resolved')::integer<>0 or (response->>'count')::integer<>0 then raise exception 'Search scope lost';end if;
end
$test$;
rollback;
