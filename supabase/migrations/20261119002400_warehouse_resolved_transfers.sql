-- Extend only the read side of the source warehouse queue. Individual final
-- statuses stay available to older clients and in the transfer receipt.
do $migration$
declare
 definition text := pg_get_functiondef('solar_private.inventory(text,uuid,jsonb)'::regprocedure);
 change record;
begin
 for change in select * from (values
  ($old$if stage not in('','pending','posted','cancelled','reversed')$old$,
   $new$if stage not in('','pending','posted','cancelled','reversed','resolved')$new$),
  ($old$filtered as(select * from matched where stage='' or status=stage),paged as(select * from filtered order by created_at desc limit 30$old$,
   $new$filtered as(select * from matched where stage='' or status=stage or (stage='resolved' and status in('posted','cancelled','reversed'))),paged as(select * from filtered order by created_at desc,id desc limit 30$new$),
  ($old$'statusCounts',jsonb_build_object('pending',(select count(*) from matched where status='pending'),'posted',(select count(*) from matched where status='posted'),'all',(select count(*) from matched))$old$,
   $new$'statusCounts',(select jsonb_build_object(
     'pending',count(*) filter(where status='pending'),
     'posted',count(*) filter(where status='posted'),
     'cancelled',count(*) filter(where status='cancelled'),
     'reversed',count(*) filter(where status='reversed'),
     'resolved',count(*) filter(where status in('posted','cancelled','reversed')),
     'all',count(*)) from matched)$new$),
  ($old$jsonb_agg(solar_private.transfer_json(id) order by created_at desc) from paged$old$,
   $new$jsonb_agg(solar_private.transfer_json(id) order by created_at desc,id desc) from paged$new$)
 ) as changes(old_text,new_text) loop
  if cardinality(string_to_array(definition,change.old_text))<>2 then
   raise exception 'Unexpected transfer queue definition';
  end if;
  definition:=replace(definition,change.old_text,change.new_text);
 end loop;
 execute definition;
end
$migration$;
