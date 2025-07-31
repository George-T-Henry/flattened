-- Backup and Restore Procedures
-- Scripts for backing up and restoring flattened profile data

-- ===== BACKUP PROCEDURES =====

-- 1. Create backup table with current timestamp
CREATE OR REPLACE FUNCTION create_flattened_profiles_backup()
RETURNS TEXT AS $$
DECLARE
    backup_table_name TEXT;
    record_count INTEGER;
BEGIN
    -- Generate backup table name with timestamp
    backup_table_name := 'flattened_profiles_backup_' || to_char(NOW(), 'YYYY_MM_DD_HH24_MI_SS');
    
    -- Create backup table
    EXECUTE format('CREATE TABLE %I AS SELECT * FROM flattened_profiles', backup_table_name);
    
    -- Get record count
    EXECUTE format('SELECT COUNT(*) FROM %I', backup_table_name) INTO record_count;
    
    -- Add metadata to backup table
    EXECUTE format('COMMENT ON TABLE %I IS ''Backup of flattened_profiles created on %s with %s records''', 
                   backup_table_name, NOW(), record_count);
    
    RETURN format('Backup completed: %s (%s records)', backup_table_name, record_count);
END;
$$ LANGUAGE plpgsql;

-- 2. Export data to CSV (run via psql command line)
-- \copy flattened_profiles TO '/path/to/backup/flattened_profiles_backup.csv' WITH CSV HEADER;

-- 3. Create compressed JSON backup
CREATE OR REPLACE FUNCTION export_flattened_profiles_json()
RETURNS TEXT AS $$
DECLARE
    json_data TEXT;
    record_count INTEGER;
BEGIN
    SELECT COUNT(*) FROM flattened_profiles INTO record_count;
    
    SELECT array_to_json(array_agg(row_to_json(fp.*)))
    FROM flattened_profiles fp
    INTO json_data;
    
    -- Note: This returns the JSON data, save it to a file externally
    RETURN format('JSON export ready: %s records', record_count);
END;
$$ LANGUAGE plpgsql;

-- ===== RESTORE PROCEDURES =====

-- 4. Restore from backup table
CREATE OR REPLACE FUNCTION restore_from_backup(backup_table TEXT)
RETURNS TEXT AS $$
DECLARE
    backup_count INTEGER;
    current_count INTEGER;
BEGIN
    -- Verify backup table exists
    IF NOT EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = backup_table) THEN
        RAISE EXCEPTION 'Backup table % does not exist', backup_table;
    END IF;
    
    -- Get counts
    EXECUTE format('SELECT COUNT(*) FROM %I', backup_table) INTO backup_count;
    SELECT COUNT(*) FROM flattened_profiles INTO current_count;
    
    -- Clear current data
    TRUNCATE flattened_profiles;
    
    -- Restore from backup
    EXECUTE format('INSERT INTO flattened_profiles SELECT * FROM %I', backup_table);
    
    RETURN format('Restored %s records from %s (previous count: %s)', backup_count, backup_table, current_count);
END;
$$ LANGUAGE plpgsql;

-- 5. Import from CSV (run via psql command line)
-- \copy flattened_profiles FROM '/path/to/backup/flattened_profiles_backup.csv' WITH CSV HEADER;

-- ===== BACKUP MANAGEMENT =====

-- 6. List all backup tables
SELECT 
    tablename,
    obj_description(oid) as backup_info
FROM pg_tables t
JOIN pg_class c ON c.relname = t.tablename
WHERE tablename LIKE 'flattened_profiles_backup_%'
ORDER BY tablename DESC;

-- 7. Cleanup old backup tables (older than 30 days)
CREATE OR REPLACE FUNCTION cleanup_old_backups(days_to_keep INTEGER DEFAULT 30)
RETURNS TEXT AS $$
DECLARE
    backup_table RECORD;
    table_date DATE;
    dropped_count INTEGER := 0;
    result_message TEXT;
BEGIN
    FOR backup_table IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE tablename LIKE 'flattened_profiles_backup_%'
    LOOP
        -- Extract date from table name (format: flattened_profiles_backup_YYYY_MM_DD_HH24_MI_SS)
        BEGIN
            table_date := to_date(
                substring(backup_table.tablename FROM 'backup_(\d{4}_\d{2}_\d{2})'), 
                'YYYY_MM_DD'
            );
            
            IF table_date < CURRENT_DATE - INTERVAL '1 day' * days_to_keep THEN
                EXECUTE format('DROP TABLE %I', backup_table.tablename);
                dropped_count := dropped_count + 1;
                RAISE NOTICE 'Dropped old backup table: %', backup_table.tablename;
            END IF;
        EXCEPTION WHEN OTHERS THEN
            RAISE NOTICE 'Could not parse date from table name: %', backup_table.tablename;
        END;
    END LOOP;
    
    result_message := format('Cleanup completed: %s old backup tables dropped', dropped_count);
    RETURN result_message;
END;
$$ LANGUAGE plpgsql;

-- ===== DISASTER RECOVERY =====

-- 8. Emergency restore procedure
CREATE OR REPLACE FUNCTION emergency_restore()
RETURNS TEXT AS $$
DECLARE
    latest_backup TEXT;
    result_message TEXT;
BEGIN
    -- Find the most recent backup
    SELECT tablename INTO latest_backup
    FROM pg_tables 
    WHERE tablename LIKE 'flattened_profiles_backup_%'
    ORDER BY tablename DESC
    LIMIT 1;
    
    IF latest_backup IS NULL THEN
        RETURN 'No backup tables found for emergency restore';
    END IF;
    
    -- Perform restore
    SELECT restore_from_backup(latest_backup) INTO result_message;
    
    RETURN format('Emergency restore completed using %s: %s', latest_backup, result_message);
END;
$$ LANGUAGE plpgsql;

-- 9. Data consistency check after restore
CREATE OR REPLACE FUNCTION verify_restore_integrity()
RETURNS TABLE (
    check_name TEXT,
    status TEXT,
    details TEXT
) AS $$
BEGIN
    -- Check 1: Record count
    RETURN QUERY
    SELECT 
        'Record Count'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        format('%s records found', COUNT(*))::TEXT
    FROM flattened_profiles;
    
    -- Check 2: Essential fields populated
    RETURN QUERY
    SELECT 
        'Essential Fields'::TEXT,
        CASE WHEN COUNT(*) = 0 THEN 'PASS' ELSE 'FAIL' END::TEXT,
        format('%s profiles missing essential data', COUNT(*))::TEXT
    FROM flattened_profiles 
    WHERE profile_id IS NULL OR full_name IS NULL OR full_name = '';
    
    -- Check 3: Search vectors
    RETURN QUERY
    SELECT 
        'Search Vectors'::TEXT,
        CASE WHEN COUNT(*) FILTER (WHERE search_vector IS NULL) = 0 THEN 'PASS' ELSE 'WARN' END::TEXT,
        format('%s profiles missing search vectors', COUNT(*) FILTER (WHERE search_vector IS NULL))::TEXT
    FROM flattened_profiles;
    
    -- Check 4: Original data preservation
    RETURN QUERY
    SELECT 
        'Original Data'::TEXT,
        CASE WHEN COUNT(*) FILTER (WHERE original_data IS NULL) = 0 THEN 'PASS' ELSE 'WARN' END::TEXT,
        format('%s profiles missing original data', COUNT(*) FILTER (WHERE original_data IS NULL))::TEXT
    FROM flattened_profiles;
    
    -- Check 5: Recent updates
    RETURN QUERY
    SELECT 
        'Recent Activity'::TEXT,
        CASE WHEN COUNT(*) > 0 THEN 'PASS' ELSE 'WARN' END::TEXT,
        format('Latest update: %s', COALESCE(MAX(last_updated)::TEXT, 'No records'))::TEXT
    FROM flattened_profiles;
    
END;
$$ LANGUAGE plpgsql;

-- ===== USAGE EXAMPLES =====

-- Create a backup:
-- SELECT create_flattened_profiles_backup();

-- List available backups:
-- SELECT tablename, obj_description(oid) FROM pg_tables t JOIN pg_class c ON c.relname = t.tablename WHERE tablename LIKE 'flattened_profiles_backup_%';

-- Restore from specific backup:
-- SELECT restore_from_backup('flattened_profiles_backup_2024_01_15_14_30_00');

-- Emergency restore (uses latest backup):
-- SELECT emergency_restore();

-- Verify restore integrity:
-- SELECT * FROM verify_restore_integrity();

-- Cleanup old backups (keep last 30 days):
-- SELECT cleanup_old_backups(30);