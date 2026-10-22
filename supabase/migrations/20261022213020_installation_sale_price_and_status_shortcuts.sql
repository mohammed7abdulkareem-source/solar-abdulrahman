-- Show the agreed selling total to the invoice owner/admin without granting
-- closing permissions or exposing prices to assigned engineers.
do $$declare definition text;needle text:=') || case when solar_private.can_close_installation(t.created_by) then';begin
 definition:=pg_get_functiondef('solar_private.installation_jobs()'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Installation jobs finance contract missing';end if;
 execute replace(definition,needle,') || case when p.user_type<>''installer'' and(p.is_admin or t.created_by=p.id) then jsonb_build_object(''sellingPrice'',t.total) else ''{}''::jsonb end || case when solar_private.can_close_installation(t.created_by) then');
end$$;
notify pgrst,'reload schema';
