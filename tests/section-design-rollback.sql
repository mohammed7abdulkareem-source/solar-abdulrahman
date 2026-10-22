\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003550','Design Admin','design_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003551','Design Staff','design_staff',false,'admin_staff','{"layoutCustomize":true,"sale":true}'),
('00000000-0000-0000-0000-000000003552','Design Viewer','design_viewer',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003553','Design Warehouse','design_warehouse',false,'warehouse','{}'),
('00000000-0000-0000-0000-000000003554','Design Installer','design_installer',false,'installer','{}');
insert into solar_private.section_layouts(user_id,mobile_columns,desktop_columns,section_order,revision) values('00000000-0000-0000-0000-000000003551',7,2,array['sale','cash'],4);
create temporary table financial_before as select md5(solar_private.reset_snapshot()::text) hash;
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003551',true);
do $$declare r jsonb;begin
 r:=public.solar_section_layout();if r->>'mode'<>'groups' or r->>'mobileColumns'<>'7' then raise exception 'legacy defaults not preserved';end if;
 r:=public.solar_section_layout('view','{"mode":"columns","expectedRevision":4}');
 if r->>'mode'<>'columns' or r->>'revision'<>'5' or r->>'desktopColumns'<>'2' or r->'order'<> '["sale","cash"]' then raise exception 'view changed order/columns';end if;
 if public.solar_section_layout('view','{"mode":"columns","expectedRevision":4}')<>r then raise exception 'retry not idempotent';end if;
 r:=public.solar_section_layout('save','{"mobileColumns":3,"desktopColumns":6,"order":["cash","sale"],"expectedRevision":5}');
 if r->>'mode'<>'columns' or r->>'revision'<>'6' then raise exception 'column save lost view';end if;
 begin perform public.solar_section_layout('view','{"mode":"groups","expectedRevision":5}');raise exception 'stale view overwritten';exception when sqlstate 'PT409' then null;end;
 r:=public.solar_section_layout('view','{"mode":"groups","expectedRevision":6}');
 if public.solar_section_layout()<>r or r->>'mobileColumns'<>'3' or r->'order'<> '["cash","sale"]' then raise exception 'cross-device state not persisted';end if;
 r:=public.solar_section_layout('view','{"mode":"premium","expectedRevision":7}');
 if r->>'mode'<>'premium' or r->>'mobileColumns'<>'3' or r->'order'<>'["cash","sale"]' then raise exception 'premium lost column preferences';end if;
 r:=public.solar_section_layout('view','{"mode":"desk","expectedRevision":8}');
 if r->>'mode'<>'desk' then raise exception 'desk not saved';end if;
 r:=public.solar_section_layout('view','{"mode":"solar","expectedRevision":9}');
 if r->>'mode'<>'solar' or r->>'mobileColumns'<>'3' or r->'order'<>'["cash","sale"]' then raise exception 'solar design lost columns/order';end if;
 r:=public.solar_section_layout('view','{"mode":"groups","expectedRevision":10}');

end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003552',true);
do $$declare r jsonb;begin
 r:=public.solar_section_layout('view','{"mode":"columns","expectedRevision":0,"userId":"00000000-0000-0000-0000-000000003551","mobileColumns":1,"order":["users"]}');
 if r->>'mode'<>'columns' or r->>'mobileColumns'<>'3' or r->'order'<>'[]' then raise exception 'view escalated customization';end if;
 begin perform public.solar_section_layout('save','{"mobileColumns":1,"desktopColumns":7,"order":[],"expectedRevision":1}');raise exception 'customization bypass';exception when insufficient_privilege then null;end;
 begin perform public.solar_section_layout('view','{"mode":"bad","expectedRevision":1}');raise exception 'invalid accepted';exception when raise_exception then if sqlerrm='invalid accepted' then raise;end if;end;
end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003553',true);
do $$begin perform public.solar_section_layout('view','{"mode":"columns","expectedRevision":0}');end$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003554',true);
do $$begin perform public.solar_section_layout('view','{"mode":"columns","expectedRevision":0}');end$$;
reset role;
update profiles set active=false where id='00000000-0000-0000-0000-000000003554';
set local role authenticated;
do $$begin begin perform public.solar_section_layout('view','{"mode":"groups","expectedRevision":1}');raise exception 'inactive accepted';exception when insufficient_privilege then null;end;end$$;
reset role;
do $$begin
 if(select display_mode from solar_private.section_layouts where user_id='00000000-0000-0000-0000-000000003551')<>'groups' then raise exception 'foreign view changed';end if;
 if md5(solar_private.reset_snapshot()::text)<>(select hash from financial_before) then raise exception 'presentation changed financial data';end if;
 if has_function_privilege('anon','public.solar_section_layout(text,jsonb)','execute') or has_table_privilege('authenticated','solar_private.section_layouts','update') then raise exception 'unsafe direct access';end if;
 raise notice 'PASS mode persistence, independent user settings, preserved columns/order, safe retry, optimistic locking, restricted customization, inactive denial, no financial changes';
end$$;
rollback;
