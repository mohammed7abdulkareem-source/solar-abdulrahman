-- The activity RPC validates the administrator, target and dates before calling
-- this private aggregate. All amounts are historical posted IQD, including
-- receipts entered in USD. Neither current FX nor current catalog cost is used.
create function solar_private.user_activity_performance(person_id uuid, date_from date, date_to date)
returns jsonb language sql stable security invoker set search_path='' as $$
 with boundaries as (
  select coalesce(date_from::timestamp at time zone 'Asia/Baghdad','-infinity'::timestamptz) lower_bound,
   (date_to+1)::timestamp at time zone 'Asia/Baghdad' upper_bound
 ), receipts as (
  select t.id,t.kind,t.total,t.subtotal,t.profit,t.fx_pricing,
   (t.created_at at time zone 'Asia/Baghdad')::date as sale_day,
   t.profit_settlement_id is null and coalesce(t.cash_purpose,'')<>'external_profit'
    and (t.kind='sale' or t.installation_status='closed') recognized
  from public.transactions t cross join boundaries b
  where t.kind in('sale','system') and (t.created_by=person_id or (t.created_by is null and t.cashbox_user_id=person_id))
    and t.created_at>=b.lower_bound and t.created_at<b.upper_bound
 ), daily as (
  select sale_day,count(*) invoice_count,
   coalesce(sum(total) filter(where kind='sale'),0) wholesale_iqd,
   coalesce(sum(total) filter(where kind='system'),0) system_iqd,
   coalesce(sum(case when kind='sale' then coalesce(subtotal,total) else total end) filter(where recognized),0) eligible_iqd,
   -- Same per-invoice recognition, rounding and cost snapshots as profit_rows.
   -- A reassignment changes the profit beneficiary, never who made the sale.
   coalesce(sum(round(case when kind='system' or fx_pricing then profit
    else coalesce(subtotal,total)-coalesce((select sum(i.qty*i.cost) from public.transaction_items i where i.transaction_id=receipts.id),0)
    end,2)) filter(where recognized),0) profit_iqd
  from receipts group by sale_day
 ), span as (
  select coalesce(date_from,min(sale_day),date_to) first_day,date_to last_day from daily
 ), scale as (
  select s.*,case when last_day-first_day<31 then 'day' when last_day<first_day+interval '2 years' then 'month' else 'year' end grain
  from span s
 ), calendar as (
  select g::date key,greatest(s.first_day,g::date) as bucket_start,least(s.last_day,(g+d.step)::date-1) ending
  from scale s cross join lateral(values(case s.grain when 'day' then interval '1 day' when 'month' then interval '1 month'
   else interval '1 year' end)) d(step)
  cross join lateral generate_series(date_trunc(s.grain,s.first_day::timestamp),date_trunc(s.grain,s.last_day::timestamp),d.step) g
 ), bucket_totals as (
  select date_trunc(s.grain,d.sale_day::timestamp)::date key,sum(invoice_count) invoice_count,sum(wholesale_iqd) wholesale_iqd,
   sum(system_iqd) system_iqd,sum(eligible_iqd) eligible_iqd,sum(profit_iqd) profit_iqd
  from daily d cross join scale s group by 1
 ), chart as (
  select c.bucket_start,c.ending,coalesce(b.invoice_count,0) invoice_count,coalesce(b.wholesale_iqd,0) wholesale_iqd,
   coalesce(b.system_iqd,0) system_iqd,coalesce(b.eligible_iqd,0) eligible_iqd,coalesce(b.profit_iqd,0) profit_iqd
  from calendar c left join bucket_totals b using(key)
 ), performance as (
  select sum(eligible_iqd) eligible_iqd,sum(profit_iqd) profit_iqd,
   jsonb_agg(jsonb_build_object('start',bucket_start,'end',ending,'invoiceCount',invoice_count,'salesIQD',wholesale_iqd+system_iqd,
    'wholesaleIQD',wholesale_iqd,'systemIQD',system_iqd,'eligibleSalesIQD',eligible_iqd,'companyProfitIQD',profit_iqd)
    order by bucket_start) series from chart
 ), approved as (
  select coalesce(sum(r.share),0) share_iqd,coalesce(sum(r.profit),0) base_iqd,count(*) approved_count
  from solar_private.profit_settlements r cross join boundaries b
  where r.owner_id=person_id and r.status='approved' and r.share is not null and r.decided_at>=b.lower_bound and r.decided_at<b.upper_bound
 )
 select jsonb_build_object('from',s.first_day,'to',s.last_day,'currency','IQD','granularity',s.grain,
  'series',p.series,'eligibleSalesIQD',p.eligible_iqd,'companyProfitIQD',p.profit_iqd,
  'marginPercent',case when p.eligible_iqd>0 then round(p.profit_iqd*100/p.eligible_iqd,2) end,
  'approvedShareIQD',a.share_iqd,'approvedShareCount',a.approved_count,'approvedShareBaseIQD',a.base_iqd,
  'approvedSharePercent',case when a.base_iqd>0 then round(a.share_iqd*100/a.base_iqd,2) end)
 from scale s cross join performance p cross join approved a
$$;
revoke all on function solar_private.user_activity_performance(uuid,date,date) from public,anon,authenticated;

do $patch$
declare definition text; needle text:='''operations'',solar_private.user_activity_operations(person.id,first_day,last_day)';
begin
 definition:=pg_get_functiondef('solar_private.user_activity(jsonb)'::regprocedure);
 if strpos(definition,needle)=0 then raise exception 'Missing admin activity detail anchor';end if;
 execute replace(definition,needle,'''performance'',solar_private.user_activity_performance(person.id,first_day,last_day),'||needle);
end$patch$;
notify pgrst,'reload schema';
