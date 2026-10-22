alter table solar_private.section_layouts drop constraint section_layouts_display_mode_check;
alter table solar_private.section_layouts add constraint section_layouts_display_mode_check check(display_mode in('groups','columns','premium','desk'));
do $$declare definition text;needle text:='mode not in(''groups'',''columns'')';begin
 definition:=pg_get_functiondef('solar_private.section_layout(text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Section design validation contract missing';end if;
 definition:=replace(definition,needle,'mode not in(''groups'',''columns'',''premium'',''desk'')');
 definition:=replace(definition,'اختر تصميم المجموعات أو الأعمدة','اختر أحد تصاميم الأقسام الأربعة');execute definition;
end$$;
notify pgrst,'reload schema';
