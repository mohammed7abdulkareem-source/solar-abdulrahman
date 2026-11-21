\set ON_ERROR_STOP on
begin;
insert into public.profiles(id,display_name,active,user_type,is_admin,permissions) values
 ('00000000-0000-0000-0000-000000412901','اختبار التحصيل',true,'admin_staff',false,'{"tahseel":true}');
insert into public.products(id,code,name,category,qty,cost) values
 (412901,'P29-P','لوح 600 للاختبار','ألواح',100,80000),
 (412902,'P29-B','بطارية اختبار السعة','بطارية',100,1500000),
 (412903,'P29-I','انفيرتر اختبار السعة','انفيرتر',100,300000);
create function pg_temp.quote(capacity numeric,night numeric default 33) returns jsonb language sql as $$
 select jsonb_build_object('schema',5,'systemType','standard','day','12','night',night,'batteryCapacity',capacity,
 'panel',jsonb_build_object('id',412901),'battery',jsonb_build_object('id',412902),'inverter',jsonb_build_object('id',412903))
$$;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000412901',true);
set local role authenticated;
do $checks$
declare result jsonb; first_quote jsonb; saved jsonb; amount numeric; expected numeric; qid uuid:=gen_random_uuid();
begin
 for amount,expected in values(16,3),(32,2),(15,3),(7.5,5) loop
  result:=public.solar_limited_quote('preview',pg_temp.quote(amount));
  assert result->'errors'='[]' and(result->>'batteryCapacity')::numeric=amount and(result->>'batteryQty')::numeric=expected;
  assert exists(select from jsonb_array_elements(result->'materials')v where v->>'key'='battery' and(v->>'qty')::numeric=expected);
  assert (result->>'price')::numeric>0 and(result->>'markupPercent')::numeric=15;
  if amount=16 then first_quote:=result;
  elsif amount=32 then assert (first_quote->>'price')::numeric-(result->>'price')::numeric=1500000*1.15;end if;
 end loop;
 assert (public.solar_limited_quote('preview',pg_temp.quote(32,32))->>'batteryQty')::numeric=1;
 assert (public.solar_limited_quote('preview',pg_temp.quote(16,32))->>'batteryQty')::numeric=2;
 result:=public.solar_limited_quote('preview',pg_temp.quote(17));
 assert jsonb_array_length(result->'errors')>0 and result->>'price' is null;
 saved:=public.solar_limited_quote('save',pg_temp.quote(16),qid);
 assert saved#>>'{payload,batteryCapacity}'='16' and (saved#>>'{result,batteryQty}')::numeric=3;
 assert not(saved#>'{payload,battery}' ? 'cost');
 saved:=public.solar_limited_quote('save',pg_temp.quote(32),qid,(saved->>'revision')::int);
 assert saved#>>'{payload,batteryCapacity}'='32' and (saved->>'revision')::int=2;
 select v into result from jsonb_array_elements(public.solar_limited_quote('list'))v where v->>'id'=qid::text;
 assert result#>>'{payload,batteryCapacity}'='32' and(result#>>'{result,batteryQty}')::numeric=2;
 assert result::text!~'"cost"|unitCost|materialsTotal';
end$checks$;
rollback;
