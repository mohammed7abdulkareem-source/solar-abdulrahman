-- Add a fifth personal presentation without changing stored column/order choices.
alter table solar_private.section_layouts drop constraint section_layouts_display_mode_check;
alter table solar_private.section_layouts add constraint section_layouts_display_mode_check check(display_mode in('groups','columns','premium','desk','solar'));
do $$declare definition text;needle text:='mode not in(''groups'',''columns'',''premium'',''desk'')';begin
 definition:=pg_get_functiondef('solar_private.section_layout(text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Section design validation contract missing';end if;
 definition:=replace(definition,needle,'mode not in(''groups'',''columns'',''premium'',''desk'',''solar'')');
 definition:=replace(definition,'اختر أحد تصاميم الأقسام الأربعة','اختر أحد تصاميم الأقسام الخمسة');execute definition;
end$$;
notify pgrst,'reload schema';
