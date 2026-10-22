-- Administrative messages use the existing notification and delivery pipelines.
do $$declare expression text;begin
 select pg_get_expr(conbin,conrelid) into expression from pg_constraint where conrelid='public.solar_notifications'::regclass and conname='solar_notifications_event_check';
 if expression is null then raise exception 'Notification contract missing';end if;
 alter table public.solar_notifications drop constraint solar_notifications_event_check;
 execute 'alter table public.solar_notifications add constraint solar_notifications_event_check check(('||expression||') or event=''admin_message'')';
end$$;
create function solar_private.admin_announcement(action text,target text default 'all',heading text default '',message text default '',request_id uuid default null) returns jsonb
language plpgsql security definer set search_path='' set lock_timeout='5s' as $$
#variable_conflict use_variable
declare actor public.profiles;prior solar_private.finance_requests;request_body jsonb;result jsonb;recipient_count integer;begin
 select * into actor from public.profiles where id=auth.uid() and active and is_admin and user_type not in('warehouse','installer');
 if actor.id is null then raise exception 'إرسال الرسائل متاح للأدمن فقط' using errcode='42501';end if;
 if action is null or action not in('preview','send') or target is null or target not in('all','staff','installers','warehouse') then raise exception 'اختر فئة المستلمين' using errcode='22023';end if;
 heading:=trim(coalesce(heading,''));message:=trim(coalesce(message,''));
 if length(heading)<1 or length(heading)>120 or length(message)<1 or length(message)>2000 then raise exception 'اكتب عنوانًا حتى 120 حرفًا ورسالة حتى 2000 حرف' using errcode='22023';end if;
 request_body:=jsonb_build_object('target',target,'title',heading,'message',message);
 if action='send' then
  if request_id is null then raise exception 'معرّف الإرسال مطلوب' using errcode='22023';end if;
  perform pg_advisory_xact_lock(7311,1);
  select * into prior from solar_private.finance_requests r where r.request_id=admin_announcement.request_id;
  if found then
   if prior.actor_id=actor.id and prior.action='admin_announcement' and prior.payload=request_body then return prior.response;end if;
   raise exception 'طلب الإرسال مستخدم ببيانات مختلفة' using errcode='PT409';
  end if;
 end if;
 select count(*) into recipient_count from public.profiles p where p.active and
  (target='all' or(target='staff' and p.user_type not in('installer','warehouse')) or(target='installers' and p.user_type='installer') or(target='warehouse' and p.user_type='warehouse'));
 result:=request_body||jsonb_build_object('recipients',recipient_count,'sender',coalesce(actor.display_name,actor.username));
 if action='preview' then return result;end if;
 if recipient_count=0 then raise exception 'لا يوجد مستلمون فعّالون ضمن الفئة المختارة' using errcode='22023';end if;
 with notices as(insert into public.solar_notifications(user_id,event,title,body)
  select p.id,'admin_message',heading,message||E'\n— '||coalesce(actor.display_name,actor.username,'الإدارة') from public.profiles p where p.active and
   (target='all' or(target='staff' and p.user_type not in('installer','warehouse')) or(target='installers' and p.user_type='installer') or(target='warehouse' and p.user_type='warehouse')) returning id,user_id)
 insert into solar_private.push_deliveries(notification_id,endpoint) select n.id,s.endpoint from notices n join public.solar_push_subscriptions s on s.user_id=n.user_id;
 result:=result||jsonb_build_object('sent',true,'sentAt',now());
 insert into solar_private.finance_requests(request_id,actor_id,action,payload,response) values(request_id,actor.id,'admin_announcement',request_body,result);
 perform solar_private.wake_push();return result;
end$$;
create function public.solar_admin_announcement(action text,target text default 'all',heading text default '',message text default '',request_id uuid default null) returns jsonb
language sql security invoker set search_path='' as $$select solar_private.admin_announcement(action,target,heading,message,request_id)$$;
revoke all on function solar_private.admin_announcement(text,text,text,text,uuid),public.solar_admin_announcement(text,text,text,text,uuid) from public,anon;
grant execute on function solar_private.admin_announcement(text,text,text,text,uuid),public.solar_admin_announcement(text,text,text,text,uuid) to authenticated;
notify pgrst,'reload schema';
