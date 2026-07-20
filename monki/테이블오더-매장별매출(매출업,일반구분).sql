select st.store_no,
       st.store_nm,
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  1), 0) as "1월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  2), 0) as "2월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  3), 0) as "3월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  4), 0) as "4월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  5), 0) as "5월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  6), 0) as "6월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  7), 0) as "7월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  8), 0) as "8월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month =  9), 0) as "9월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month = 10), 0) as "10월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month = 11), 0) as "11월매출",
       coalesce(sum(tdoi.total_price) filter (where m.sale_month = 12), 0) as "12월매출",
       case when exists (select 1 from sellup.basic_info bi
                          where bi.store_no = st.store_no) then '매출업매장' else '' end as sellup_flag
  from pos.tb_deal_order_item tdoi
  join pos.tb_deal_order tdo on tdoi.order_id = tdo.order_id and tdo.order_status = 'OPRS_006'
  join pos.tb_deal td       on tdo.deal_id = td.deal_id and td.deal_status = 'OPRS_006'
  join public.tb_store st   on tdoi.store_no = st.store_no
  cross join lateral (
       select extract(month from to_timestamp(tdoi.reg_dt) at time zone 'Asia/Seoul')::int as sale_month
  ) m
 where tdoi.order_item_status = 'OPRS_006'
   -- :year = 2026 (integer). KST 기준 1/1 00:00 ~ 다음해 1/1 00:00
   and tdoi.reg_dt >= extract(epoch from (make_date(:year, 1, 1)::timestamp at time zone 'Asia/Seoul'))::int8
   and tdoi.reg_dt <  extract(epoch from (make_date(:year + 1, 1, 1)::timestamp at time zone 'Asia/Seoul'))::int8
 group by st.store_no, st.store_nm
 order by st.store_no;