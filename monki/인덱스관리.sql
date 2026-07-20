SELECT
    schemaname,
    relname,
    indexrelname,
    idx_scan,
    idx_tup_read,
    idx_tup_fetch,
    pg_size_pretty(pg_relation_size(indexrelid)) AS index_size
FROM pg_stat_user_indexes
WHERE schemaname = 'table_order'
  AND relname = 'deal_discount'
ORDER BY idx_scan DESC;

-- 죽은 튜플까지 정리 + 통계갱신
VACUUM (ANALYZE) table_order.deal_discount;

EXPLAIN (
    ANALYZE,
    BUFFERS,
    VERBOSE
)