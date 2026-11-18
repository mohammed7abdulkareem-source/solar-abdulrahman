-- The browser runner supplies two new UUIDs for each run on this local database.
\set ON_ERROR_STOP on
begin;
do $$
begin
 if current_database() not in ('solar_v4113_profit_browser','solar_v4113_final_browser') then
  raise exception 'Use the isolated profit target browser fixture';
 end if;
end $$;

insert into public.profiles(id,display_name,user_type,active,is_admin,phone,permissions) values
 (:'target_id', 'مستخدم تسوية تجريبية', 'admin_staff', true, false, '07704113111', '{"profit":true,"profitSettlement":true,"cash":true}'),
 (:'control_id', 'مستخدم للمقارنة', 'admin_staff', true, false, '07704113112', '{"profit":true,"profitSettlement":true,"cash":true}');

lock table public.transactions in share row exclusive mode;
with next_id as (select least(coalesce(min(id),0),0)-1 as id from public.transactions)
insert into public.transactions(id,kind,total,subtotal,profit,fx_pricing,cash,created_by,cashbox_user_id,payment_mode,created_at,notes)
select next_id.id + sample.offset_id,'sale',sample.total,sample.total,sample.profit,true,false,sample.owner_id,sample.owner_id,'credit',now()-interval '2 days','profit target browser sale'
from next_id cross join (values
 (0,50000,25000.25,:'target_id'::uuid),
 (-1,60000,3125.75,:'control_id'::uuid)
) as sample(offset_id,total,profit,owner_id);
insert into public.transactions(id,kind,total,cash,cash_purpose,payment_mode,created_by,cashbox_user_id,created_at,notes)
select min(id)-1,'cash_expense',125000.25,false,'expense','expense',:'target_id'::uuid,:'target_id'::uuid,now()-interval '1 day','profit target browser expense'
from public.transactions;
commit;
