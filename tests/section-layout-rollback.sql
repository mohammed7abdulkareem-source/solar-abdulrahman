\set ON_ERROR_STOP on
begin;
insert into profiles(id,display_name,username,is_admin,user_type,permissions) values
('00000000-0000-0000-0000-000000003470','Layout Admin','layout_admin',true,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003471','Layout Staff','layout_staff',false,'admin_staff','{"layoutCustomize":true,"sale":true}'),
('00000000-0000-0000-0000-000000003472','No Layout','layout_other',false,'admin_staff','{}'),
('00000000-0000-0000-0000-000000003473','Layout Warehouse','layout_stock',false,'warehouse','{"layoutCustomize":true,"profit":true}');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003471',true);
do $$declare r jsonb;begin
 r:=public.solar_section_layout();if r->>'mobileColumns'<>'3' then raise exception 'default columns';end if;
 r:=public.solar_section_layout('save','{"mobileColumns":7,"desktopColumns":1,"order":["cash","sale","system"],"expectedRevision":0}');if r->>'revision'<>'1' or r->'order'->>0<>'cash' then raise exception 'order not saved';end if;
 if public.solar_section_layout() is distinct from r then raise exception 'persisted preferences';end if;
 begin perform public.solar_section_layout('save','{"mobileColumns":2,"desktopColumns":7,"order":[],"expectedRevision":0}');raise exception 'stale revision accepted';exception when serialization_failure or sqlstate 'PT409' then null;end;
 begin perform public.solar_section_layout('save','{"mobileColumns":8,"desktopColumns":7,"order":[],"expectedRevision":1}');raise exception 'invalid grid accepted';exception when raise_exception then if sqlerrm='invalid grid accepted' then raise;end if;end;
 begin perform public.solar_section_layout('save','{"mobileColumns":2,"desktopColumns":7,"order":["sale","sale"],"expectedRevision":1}');raise exception 'duplicate order accepted';exception when raise_exception then if sqlerrm='duplicate order accepted' then raise;end if;end;
end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003472',true);
do $$begin if public.solar_section_layout()->>'revision'<>'0' then raise exception 'another user layout leaked';end if;begin perform public.solar_section_layout('save','{"mobileColumns":2,"desktopColumns":7,"order":["cash"],"expectedRevision":0}');raise exception 'permission bypass';exception when insufficient_privilege then null;end;end $$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000003473',true);
do $$begin perform public.solar_section_layout('save','{"mobileColumns":1,"desktopColumns":7,"order":["warehouse","stock"],"expectedRevision":0}');end $$;
reset role;
do $$begin if exists(select 1 from profiles where id='00000000-0000-0000-0000-000000003473' and (permissions->>'profit')='true') then raise exception 'warehouse financial permission bypass';end if;if has_function_privilege('anon','public.solar_section_layout(text,jsonb)','execute') then raise exception 'anonymous layout access';end if;raise notice 'PASS columns 1–7, persisted personal order, concurrent edit protection, revoked/missing permission, warehouse layout without financial permissions, no anonymous access';end $$;
rollback;
