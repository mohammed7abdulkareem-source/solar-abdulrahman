-- Installation payouts may overdraw the IQD cashbox. Later customer
-- collections reduce the negative balance through the existing ledger.
-- Keep delta posting, original-payer refunds, caller identity and privileges.
CREATE OR REPLACE FUNCTION solar_private.post_installation_cash(job_id bigint, approved numeric, actor uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare paid numeric; difference numeric; refund numeric; allocation record;
begin
 if actor is distinct from auth.uid() then raise exception 'Not permitted' using errcode='42501';end if;
 select -coalesce(sum(delta),0) into paid from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id;
 difference:=approved-paid;
 if difference>0 then
  insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(actor,-difference,'installation_payout',job_id,actor,'مصاريف تنصيب ملف #'||job_id::text);
 elsif difference<0 then
  refund:=-difference;
  for allocation in select owner_id,-sum(delta) as amount,max(created_at) as last_at from public.solar_cash_entries e where e.job_id=post_installation_cash.job_id group by owner_id having sum(delta)<0 order by max(created_at) desc,owner_id loop
   insert into public.solar_cash_entries(owner_id,delta,entry_type,job_id,actor_id,notes) values(allocation.owner_id,least(refund,allocation.amount),'installation_refund',job_id,actor,'استرجاع فرق مصاريف ملف #'||job_id::text);
   refund:=refund-least(refund,allocation.amount);exit when refund=0;
  end loop;
 end if;
end $function$
;
