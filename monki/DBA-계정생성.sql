-- 1. 사용자 생성
CREATE USER multica_mk WITH PASSWORD 'your_password';

-- 2. 데이터베이스 접속 권한
GRANT CONNECT ON DATABASE mk TO multica_mk;

-- 3. 모든 스키마 권한 + 테이블 SELECT (현재 존재하는 것)
DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname
        FROM pg_namespace
        WHERE nspname NOT IN ('pg_catalog', 'information_schema')
          AND nspname NOT LIKE 'pg_%'
    LOOP
        EXECUTE format('GRANT USAGE ON SCHEMA %I TO multica_mk', schema_name);
        EXECUTE format('GRANT SELECT ON ALL TABLES IN SCHEMA %I TO multica_mk', schema_name);
        EXECUTE format('GRANT SELECT ON ALL SEQUENCES IN SCHEMA %I TO multica_mk', schema_name);
    END LOOP;
END;
$$;

-- 4. 앞으로 생성될 테이블/시퀀스에도 자동 권한 부여 (스키마별로 실행)
DO $$
DECLARE
    schema_name TEXT;
BEGIN
    FOR schema_name IN
        SELECT nspname
        FROM pg_namespace
        WHERE nspname NOT IN ('pg_catalog', 'information_schema')
          AND nspname NOT LIKE 'pg_%'
    LOOP
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON TABLES TO multica_mk', schema_name);
        EXECUTE format('ALTER DEFAULT PRIVILEGES IN SCHEMA %I GRANT SELECT ON SEQUENCES TO multica_mk', schema_name);
    END LOOP;
END;
$$;

-- 5. 앞으로 생성될 스키마도 자동으로 커버 (선택사항 - superuser 필요)
-- 신규 스키마는 자동 적용이 안되므로, 스키마 추가 시 아래를 수동 실행해야 함
-- GRANT USAGE ON SCHEMA new_schema TO readonly_user;
-- ALTER DEFAULT PRIVILEGES IN SCHEMA new_schema GRANT SELECT ON TABLES TO readonly_user;