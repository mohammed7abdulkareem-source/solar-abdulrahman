do $$ declare definition text;begin
 select pg_get_functiondef('solar_private.warehouse_orders(text,text,integer)'::regprocedure) into definition;
 definition:=replace(definition,'search_text='''' or strpos','search_text='''' or search_text=''@id:''||t.id::text or strpos');
 execute definition;
 select pg_get_functiondef('solar_private.warehouse_action(bigint,text,text,jsonb,text)'::regprocedure) into definition;
 definition:=replace(definition,E'else\n  if j.warehouse_status<>''ready''',E'else\n  if j.installation_status in (''in_progress'',''completed'',''closed'') then raise exception ''بدأ تنفيذ المنظومة؛ لا يمكن إعادة التجهيز الآن'';end if;\n  if j.warehouse_status<>''ready''');
 execute definition;
end $$;
