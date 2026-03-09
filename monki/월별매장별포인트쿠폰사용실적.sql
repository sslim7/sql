select dd.store_no,st.store_nm,
       to_char(dd.created_at,'YYYY-MM'),
       case when any_value(bi.store_no) is null then '' else 'Y' end sellup_yn,
       sum(case when dd.discount_type='POINT' then 1 else 0 end) point_count,sum(case when dd.discount_type='POINT' then discount_amount else 0 end) point_discount_amount,
       sum(case when dd.discount_type='COUPON' then 1 else 0 end) coupon_count,sum(case when dd.discount_type='COUPON' then discount_amount else 0 end) coupon_discount_amount
  from table_order.deal_discount dd join public.tb_store st on dd.store_no=st.store_no
  join pos.tb_deal_order tdo on dd.order_id=tdo.order_id and dd.deal_id=tdo.deal_id and tdo.order_status = 'OPRS_006'
  left join sellup.basic_info bi on dd.store_no=bi.store_no
         where dd.created_at > '2025-10-01' and dd.created_at < '2026-04-01' and dd.store_no=803
 group by 1,2,3
 order by 2,3;