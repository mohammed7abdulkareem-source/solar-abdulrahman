-- Add a presentation choice only. No stored preferences, finance rows,
-- ownership checks, grants, or RLS policies are changed by this migration.
set local lock_timeout = '5s';
set local statement_timeout = '30s';

do $migration$
declare definition text;
 needle text := 'mode not in(''groups'',''columns'',''premium'',''desk'',''solar'')';
begin
 definition := pg_get_functiondef('solar_private.section_layout(text,jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then
  raise exception 'Section design validation contract missing';
 end if;
 definition := replace(definition,needle,'mode not in(''groups'',''columns'',''premium'',''desk'',''solar'',''general'')');
 definition := replace(definition,'اختر أحد تصاميم الأقسام الخمسة','اختر أحد تصاميم البرنامج');
 execute definition;
end $migration$;

alter table solar_private.section_layouts
 drop constraint section_layouts_display_mode_check,
 add constraint section_layouts_display_mode_check
 check(display_mode in('groups','columns','premium','desk','solar','general'));

notify pgrst, 'reload schema';
