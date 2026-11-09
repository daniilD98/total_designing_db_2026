DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'inspector') THEN
        CREATE ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    ELSE
        ALTER ROLE inspector LOGIN PASSWORD 'NetoSQL2025';
    END IF;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO inspector', current_database());
END $$;

GRANT ALL PRIVILEGES ON SCHEMA dolgopolov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL TABLES    IN SCHEMA dolgopolov_food TO inspector;  
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA dolgopolov_food TO inspector;
GRANT ALL PRIVILEGES ON ALL ROUTINES  IN SCHEMA dolgopolov_food TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA dolgopolov_food GRANT ALL PRIVILEGES ON TABLES    TO inspector;
ALTER DEFAULT PRIVILEGES IN SCHEMA dolgopolov_food GRANT ALL PRIVILEGES ON ROUTINES  TO inspector;

GRANT USAGE ON SCHEMA exts TO inspector;
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA exts TO inspector;

GRANT USAGE ON SCHEMA information_schema, pg_catalog TO inspector;