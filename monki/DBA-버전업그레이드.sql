select version(); -- > PostgreSQL 16.14 on aarch64-unknown-linux-gnu, compiled by aarch64-unknown-linux-gnu-gcc (GCC) 12.4.0, 64-bit
-- 확장 기능 확인
select extname, extversion
from pg_extension
order by extname;

extname,extversion
cube,1.4
earthdistance,1.1
pgcrypto,1.3
plpgsql,1.0

CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

extname,extversion
cube,1.4
earthdistance,1.1
pg_trgm,1.6
pgcrypto,1.3
plpgsql,1.0
uuid-ossp,1.1

select version(); -- > PostgreSQL 16.3 on aarch64-unknown-linux-gnu, compiled by gcc (GCC) 7.3.1 20180712 (Red Hat 7.3.1-17), 64-bit
-- 확장 기능 확인
select extname, extversion
from pg_extension
order by extname;

extname,extversion
cube,1.4
earthdistance,1.1
pg_trgm,1.6
pgcrypto,1.3
plpgsql,1.0
uuid-ossp,1.1