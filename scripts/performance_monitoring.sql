-- Performance Monitoring Queries
-- Use these queries to monitor system performance and identify bottlenecks

-- 1. Table size and statistics
SELECT 
    schemaname,
    tablename,
    attname as column_name,
    n_distinct,
    correlation,
    most_common_vals[1:5] as top_5_values
FROM pg_stats 
WHERE tablename = 'flattened_profiles'
ORDER BY tablename, attname;

-- 2. Index usage statistics
SELECT 
    schemaname,
    tablename,
    indexname,
    idx_tup_read,
    idx_tup_fetch,
    idx_scan,
    CASE 
        WHEN idx_scan = 0 THEN 'Never used'
        WHEN idx_scan < 100 THEN 'Low usage'
        WHEN idx_scan < 1000 THEN 'Medium usage'
        ELSE 'High usage'
    END as usage_level
FROM pg_stat_user_indexes 
WHERE tablename = 'flattened_profiles'
ORDER BY idx_scan DESC;

-- 3. Table scan vs index scan ratio
SELECT 
    schemaname,
    tablename,
    seq_scan as table_scans,
    seq_tup_read as rows_read_by_table_scan,
    idx_scan as index_scans,
    idx_tup_fetch as rows_fetched_by_index,
    CASE 
        WHEN seq_scan + idx_scan = 0 THEN 0
        ELSE ROUND((idx_scan::float / (seq_scan + idx_scan) * 100)::numeric, 2)
    END as index_usage_percentage
FROM pg_stat_user_tables 
WHERE tablename = 'flattened_profiles';

-- 4. Most expensive queries (requires pg_stat_statements extension)
-- Enable with: CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    rows,
    100.0 * shared_blks_hit / nullif(shared_blks_hit + shared_blks_read, 0) AS hit_percent
FROM pg_stat_statements 
WHERE query ILIKE '%flattened_profiles%'
ORDER BY mean_time DESC
LIMIT 10;

-- 5. Buffer cache hit ratio for flattened_profiles
SELECT 
    schemaname,
    tablename,
    heap_blks_read,
    heap_blks_hit,
    CASE 
        WHEN heap_blks_read + heap_blks_hit = 0 THEN NULL
        ELSE ROUND((heap_blks_hit::float / (heap_blks_read + heap_blks_hit) * 100)::numeric, 2)
    END as cache_hit_ratio
FROM pg_statio_user_tables 
WHERE tablename = 'flattened_profiles';

-- 6. Table and index sizes
SELECT 
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as total_size,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as table_size,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename) - pg_relation_size(schemaname||'.'||tablename)) as index_size
FROM pg_tables 
WHERE tablename = 'flattened_profiles';

-- 7. Search performance test
EXPLAIN (ANALYZE, BUFFERS) 
SELECT original_id, full_name, current_company 
FROM flattened_profiles 
WHERE search_text @@ plainto_tsquery('software engineer');

-- 8. Skills search performance (using GIN index)
EXPLAIN (ANALYZE, BUFFERS)
SELECT original_id, full_name, skills
FROM flattened_profiles 
WHERE to_tsvector('english', COALESCE(skills, '')) @@ plainto_tsquery('JavaScript');

-- 9. Company search performance
EXPLAIN (ANALYZE, BUFFERS)
SELECT original_id, full_name, current_company
FROM flattened_profiles 
WHERE current_company ILIKE '%google%';

-- 10. Trigger performance monitoring
-- Check how long the sync operations are taking
SELECT 
    'Trigger Performance Check' as metric,
    COUNT(*) as profiles_updated_last_hour,
    AVG(EXTRACT(EPOCH FROM (last_updated - created_at))) as avg_processing_time_seconds
FROM flattened_profiles
WHERE last_updated > NOW() - INTERVAL '1 hour'
AND created_at != last_updated; -- Only updates, not inserts

-- 11. Dead tuple analysis
SELECT 
    schemaname,
    tablename,
    n_tup_ins as inserts,
    n_tup_upd as updates,
    n_tup_del as deletes,
    n_dead_tup as dead_tuples,
    last_vacuum,
    last_autovacuum,
    last_analyze,
    last_autoanalyze
FROM pg_stat_user_tables 
WHERE tablename = 'flattened_profiles';

-- 12. Bloat estimation for flattened_profiles table
SELECT 
    tablename,
    ROUND(100 * (pg_relation_size(schemaname||'.'||tablename) / 
          pg_size_bytes(pg_size_pretty(pg_relation_size(schemaname||'.'||tablename))))::numeric, 2) as bloat_ratio,
    pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) as current_size
FROM pg_tables 
WHERE tablename = 'flattened_profiles';

-- 13. Lock monitoring
SELECT 
    blocked_locks.pid AS blocked_pid,
    blocked_activity.usename AS blocked_user,
    blocking_locks.pid AS blocking_pid,
    blocking_activity.usename AS blocking_user,
    blocked_activity.query AS blocked_statement,
    blocking_activity.query AS blocking_statement
FROM pg_catalog.pg_locks blocked_locks
JOIN pg_catalog.pg_stat_activity blocked_activity ON blocked_activity.pid = blocked_locks.pid
JOIN pg_catalog.pg_locks blocking_locks 
    ON blocking_locks.locktype = blocked_locks.locktype
    AND blocking_locks.database IS NOT DISTINCT FROM blocked_locks.database
    AND blocking_locks.relation IS NOT DISTINCT FROM blocked_locks.relation
    AND blocking_locks.page IS NOT DISTINCT FROM blocked_locks.page
    AND blocking_locks.tuple IS NOT DISTINCT FROM blocked_locks.tuple
    AND blocking_locks.virtualxid IS NOT DISTINCT FROM blocked_locks.virtualxid
    AND blocking_locks.transactionid IS NOT DISTINCT FROM blocked_locks.transactionid
    AND blocking_locks.classid IS NOT DISTINCT FROM blocked_locks.classid
    AND blocking_locks.objid IS NOT DISTINCT FROM blocked_locks.objid
    AND blocking_locks.objsubid IS NOT DISTINCT FROM blocked_locks.objsubid
    AND blocking_locks.pid != blocked_locks.pid
JOIN pg_catalog.pg_stat_activity blocking_activity ON blocking_activity.pid = blocking_locks.pid
WHERE NOT blocked_locks.granted
AND blocked_activity.query ILIKE '%flattened_profiles%';

-- 14. Concurrent operations monitoring
SELECT 
    pid,
    state,
    query_start,
    state_change,
    query
FROM pg_stat_activity 
WHERE query ILIKE '%flattened_profiles%'
AND state != 'idle'
ORDER BY query_start;

-- 15. Maintenance recommendations
SELECT 
    'Maintenance Recommendations' as category,
    CASE 
        WHEN last_vacuum < NOW() - INTERVAL '1 week' THEN 'VACUUM recommended'
        WHEN last_analyze < NOW() - INTERVAL '1 day' THEN 'ANALYZE recommended'
        WHEN n_dead_tup > 1000 THEN 'VACUUM recommended due to dead tuples'
        ELSE 'Maintenance up to date'
    END as recommendation
FROM pg_stat_user_tables 
WHERE tablename = 'flattened_profiles';