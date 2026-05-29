-- ===========================================
-- Monki Billing Schema v3 (최종)
-- billing 스키마 내 전체 테이블
-- ===========================================

CREATE SCHEMA IF NOT EXISTS billing;
ALTER SCHEMA billing OWNER TO mk;

-- ===========================================
-- ENUM types
-- ===========================================
CREATE TYPE billing.selling_value_kind AS ENUM ('int', 'num', 'text', 'date', 'bool', 'json','enum');
CREATE TYPE billing.bill_type          AS ENUM ('정기과금', '수동과금');
CREATE TYPE billing.calc_type          AS ENUM ('정액', '정률', '무료');
CREATE TYPE billing.sell_type          AS ENUM ('tableorder', 'qrorder', 'sellup', 'kakaotalk', 'waiting', 'service');
CREATE TYPE billing.invoice_status     AS ENUM ('issued', 'paid', 'cancelled');
CREATE TYPE billing.sell_status        AS ENUM ('active', 'paused', 'cancelled');
CREATE TYPE billing.hard_type          AS ENUM ('일반형', '프리미엄');
CREATE TYPE billing.contract_type      AS ENUM ('렌탈', '구독', '무료');
CREATE TYPE billing.payment_method     AS ENUM ('자동출금', '신용카드', '기타');
CREATE TYPE billing.source             AS ENUM ('fn_aisellup','fn_kakaotalk');
CREATE TYPE billing.is_invoice         AS ENUM ('발행','발행안함');
SELECT e.*--typname, enumlabel, enumsortorder
FROM pg_type t
JOIN pg_enum e ON t.oid = e.enumtypid
JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE n.nspname = 'billing'
ORDER BY typname, enumsortorder;
drop type billing.hard_type;
-- ===========================================
-- stores
-- 빌링매장
-- ===========================================
CREATE TABLE billing.stores (
    store_no    BIGINT PRIMARY KEY,                         -- 매장번호 (public.tb_store 참조)
    store_name  TEXT NOT NULL,                              -- 매장명
    bill_day    SMALLINT NOT NULL DEFAULT 1,                 -- 빌링일
    biz_number  TEXT,                                       -- 사업자번호 (public.tb_store.biz_number 참조)
    address     TEXT,                                       -- 사업장주소
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,              -- 매장상태
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ
);

COMMENT ON TABLE  billing.stores          IS '빌링매장';
COMMENT ON COLUMN billing.stores.store_no IS '매장번호 PK (public.tb_store.store_no 참조)';
COMMENT ON COLUMN billing.stores.bill_day IS '청구일';
COMMENT ON COLUMN billing.stores.biz_number IS '사업자번호';
COMMENT ON COLUMN billing.stores.address IS '사업장주소';
COMMENT ON COLUMN billing.stores.is_active IS '매장상태';

CREATE INDEX idx_stores_store_name ON billing.stores USING gin (store_name gin_trgm_ops);


alter table billing.stores owner to mk;

-- ===========================================
-- accounts
-- 빌링계좌
-- ===========================================

CREATE TABLE billing.accounts (
    store_no       BIGINT NOT NULL REFERENCES billing.stores(store_no),
    bank_no        TEXT NOT NULL,                           -- 은행번호
    account_number TEXT NOT NULL,                           -- 계좌번호
    holder_name    TEXT NOT NULL,                           -- 예금주명
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ,

    PRIMARY KEY (store_no)
);

COMMENT ON TABLE billing.accounts IS '빌링계좌 (매장별 정산 계좌)';
COMMENT ON COLUMN billing.accounts.bank_no IS '은행코드';
COMMENT ON COLUMN billing.accounts.account_number IS '계좌번호';
COMMENT ON COLUMN billing.accounts.holder_name IS '예금주명';

alter table billing.accounts owner to mk;

-- ===========================================
-- fields
-- 항목 (invoice_data JSONB의 필드 메타 정의)
-- ===========================================

CREATE TABLE billing.fields (
    field_id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    field_name        TEXT NOT NULL,
    field_description TEXT,
    field_type        billing.selling_value_kind NOT NULL,
    created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE billing.fields IS 'invoice_data JSONB에 들어가는 필드 메타 정의';
COMMENT ON COLUMN billing.fields.field_name IS '필드명';
COMMENT ON COLUMN billing.fields.field_description IS '필드설명';
COMMENT ON COLUMN billing.fields.field_type IS '필드속성';

alter table billing.fields owner to mk;


-- ===========================================
-- sell_type_fields
-- 매출유형별 필요 항목
-- ===========================================
drop table billing.sell_type_fields;
CREATE TABLE billing.sell_type_fields (
    sell_type_field_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sell_type          billing.sell_type NOT NULL,          -- 매출유형
--     field_id           UUID NOT NULL REFERENCES billing.fields(field_id),
    field_id           UUID NOT NULL ,
    sort_by            SMALLINT NOT NULL DEFAULT 0,          -- 노출순서
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (sell_type, field_id)
);

COMMENT ON TABLE billing.sell_type_fields IS '매출유형별 필요한 필드 정의';
COMMENT ON COLUMN billing.sell_type_fields.sell_type IS '매출유형';
COMMENT ON COLUMN billing.sell_type_fields.field_id IS '필드ID';
COMMENT ON COLUMN billing.sell_type_fields.sort_by IS '노출순서';

alter table billing.sell_type_fields owner to mk;


-- ===========================================
-- contracts
-- 계약
-- ===========================================

CREATE TABLE billing.contracts (
    cont_id       UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- 계약ID
    store_no      BIGINT NOT NULL REFERENCES billing.stores(store_no),
    sell_type     billing.sell_type NOT NULL,                   -- 매출유형
    contract_data JSONB,                                        -- 계약데이터 (sell_type별 상이)
    sell_status   billing.sell_status NOT NULL DEFAULT 'active',
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ
);

CREATE INDEX idx_contracts_store_no   ON billing.contracts(store_no);
CREATE INDEX idx_contracts_store_type ON billing.contracts(store_no, sell_type);
CREATE INDEX idx_contracts_status     ON billing.contracts(sell_status);

COMMENT ON TABLE  billing.contracts               IS '계약';
COMMENT ON COLUMN billing.contracts.store_no IS '매장번호';
COMMENT ON COLUMN billing.contracts.sell_type IS '매출유형';
COMMENT ON COLUMN billing.contracts.sell_status IS '판매상태';
COMMENT ON COLUMN billing.contracts.contract_data IS 'sell_type 별 계약결과';

alter table billing.contracts owner to mk;

-- ===========================================
-- contract_history
-- 계약이력 (contracts 변경 시 자동 적재)
-- ===========================================

CREATE TABLE billing.contract_history (
    cont_hist_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- 계약이력ID
    cont_id       UUID NOT NULL REFERENCES billing.contracts(cont_id),  -- 계약ID
    store_no      BIGINT NOT NULL,                              -- 매장번호
    sell_type     billing.sell_type NOT NULL,                   -- 매출유형
    contract_data JSONB NOT NULL,                               -- 변경 전 계약데이터
    sell_status   billing.sell_status NOT NULL,                 -- 변경 전 판매상태
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()            -- 변경시각
);

CREATE INDEX idx_contract_history_cont_id  ON billing.contract_history(cont_id);
CREATE INDEX idx_contract_history_store_no ON billing.contract_history(store_no);
CREATE INDEX idx_contract_history_time     ON billing.contract_history(created_at DESC);

COMMENT ON TABLE  billing.contract_history               IS '계약이력 (INSERT: NEW 저장, UPDATE: OLD 저장)';
COMMENT ON COLUMN billing.contract_history.cont_id IS '계약ID';
COMMENT ON COLUMN billing.contract_history.store_no IS '매장번호';
COMMENT ON COLUMN billing.contract_history.sell_type IS '매출유형';
COMMENT ON COLUMN billing.contract_history.sell_status IS '판매상태';

alter table billing.contract_history owner to mk;

-- ===========================================
-- contract_history 자동 적재 트리거
-- INSERT: NEW 저장 (최초 계약 기록)
-- UPDATE: OLD 저장 (변경 전 값 보존)
-- ===========================================

CREATE OR REPLACE FUNCTION billing.log_contract_history()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF TG_OP = 'INSERT' THEN
        INSERT INTO billing.contract_history
            (cont_id, store_no, sell_type, contract_data, sell_status)
        VALUES
            (NEW.cont_id, NEW.store_no, NEW.sell_type, NEW.contract_data, NEW.sell_status);

    ELSIF TG_OP = 'UPDATE' THEN
        INSERT INTO billing.contract_history
            (cont_id, store_no, sell_type, contract_data, sell_status)
        VALUES
            (OLD.cont_id, OLD.store_no, OLD.sell_type, OLD.contract_data, OLD.sell_status);
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_contract_history
AFTER INSERT OR UPDATE ON billing.contracts
FOR EACH ROW EXECUTE FUNCTION billing.log_contract_history();


-- ===========================================
-- billing
-- 송장 (월 청구서 헤더)
-- ===========================================

CREATE TABLE billing.billing (
    bill_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- 빌링ID
    store_no       BIGINT NOT NULL REFERENCES billing.stores(store_no),
    billing_month  DATE NOT NULL,                               -- 빌링월 (항상 1일, e.g. 2025-05-01)
    total_amount   INTEGER NOT NULL DEFAULT 0,                      -- 빌링금액합계
    supply_amount  INTEGER NOT NULL DEFAULT 0,                      -- 공급가액
    vat_amount     INTEGER NOT NULL DEFAULT 0,                      -- 부가세
    status         billing.invoice_status NOT NULL DEFAULT 'issued',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ,

    UNIQUE (store_no, billing_month)
);

CREATE INDEX idx_billing_store_no      ON billing.billing(store_no);
CREATE INDEX idx_billing_month         ON billing.billing(billing_month);
CREATE INDEX idx_billing_status        ON billing.billing(status);

COMMENT ON TABLE  billing.billing              IS '송장 (월 청구서 헤더)';
COMMENT ON COLUMN billing.billing.billing_month IS '빌링월 (항상 1일로 저장, e.g. 2025-05-01)';
COMMENT ON COLUMN billing.billing.total_amount  IS 'supply_amount + vat_amount (트리거로 자동 갱신)';
COMMENT ON COLUMN billing.billing.supply_amount  IS '공급가';
COMMENT ON COLUMN billing.billing.vat_amount  IS '부가세';
COMMENT ON COLUMN billing.billing.status  IS '빌링상태';

alter table billing.billing owner to mk;
-- ===========================================
-- invoice
-- 송장항목 (line items)
-- ===========================================

CREATE TABLE billing.invoice (
    invoice_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- 송장항목ID
    bill_id       UUID NOT NULL REFERENCES billing.billing(bill_id) ON DELETE CASCADE,
    sell_type     billing.sell_type NOT NULL,                   -- 매출유형
    invoice_data  JSONB,                  -- 빌링데이터 (생성 시점 스냅샷)
    total_amount  INTEGER NOT NULL DEFAULT 0,                       -- 빌링금액
    supply_amount INTEGER NOT NULL DEFAULT 0,                       -- 공급가액
    vat_amount    INTEGER NOT NULL DEFAULT 0,                       -- 부가세
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ
);

CREATE INDEX idx_invoice_bill_id   ON billing.invoice(bill_id);
CREATE INDEX idx_invoice_sell_type ON billing.invoice(sell_type);

COMMENT ON TABLE  billing.invoice              IS '송장항목 (line items)';
COMMENT ON COLUMN billing.invoice.bill_id IS '빌링ID';
COMMENT ON COLUMN billing.invoice.sell_type IS '매출유형';
COMMENT ON COLUMN billing.invoice.invoice_data IS '생성 시점 계약데이터 스냅샷 (이후 contract 변경 영향 없음)';
COMMENT ON COLUMN billing.invoice.total_amount IS '합계';
COMMENT ON COLUMN billing.invoice.supply_amount IS '공급가';
COMMENT ON COLUMN billing.invoice.vat_amount IS '부가세';

alter table billing.invoice owner to mk;

-- ===========================================
-- billing.total_amount 자동 갱신 트리거
-- invoice 변경 시 billing 합계 재계산
-- ===========================================

CREATE OR REPLACE FUNCTION billing.sync_billing_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_bill_id UUID;
BEGIN
    v_bill_id := COALESCE(NEW.bill_id, OLD.bill_id);

    UPDATE billing.billing
    SET
        supply_amount = (SELECT COALESCE(SUM(supply_amount), 0) FROM billing.invoice WHERE bill_id = v_bill_id),
        vat_amount    = (SELECT COALESCE(SUM(vat_amount),    0) FROM billing.invoice WHERE bill_id = v_bill_id),
        total_amount  = (SELECT COALESCE(SUM(total_amount),  0) FROM billing.invoice WHERE bill_id = v_bill_id),
        updated_at    = NOW()
    WHERE bill_id = v_bill_id;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_billing_total
AFTER INSERT OR UPDATE OR DELETE ON billing.invoice
FOR EACH ROW EXECUTE FUNCTION billing.sync_billing_total();


-- ===========================================
-- updated_at 자동 갱신 트리거
-- ===========================================

CREATE OR REPLACE FUNCTION billing.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_stores_updated_at    BEFORE UPDATE ON billing.stores    FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_accounts_updated_at  BEFORE UPDATE ON billing.accounts  FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_contracts_updated_at BEFORE UPDATE ON billing.contracts FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_billing_updated_at   BEFORE UPDATE ON billing.billing   FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_invoice_updated_at   BEFORE UPDATE ON billing.invoice   FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();


-- ===========================================
-- 기초 데이터
-- ===========================================
-- ===========================================
-- billing.fields + billing.sell_type_fields
-- 초기 데이터 INSERT
-- ===========================================

-- fields 먼저 insert (중복 방지를 위해 field_name unique 가정)
-- field_id는 gen_random_uuid()로 자동 생성되므로
-- sell_type_fields 연결 시 서브쿼리로 참조

INSERT INTO billing.fields (field_name, field_description, field_type) VALUES
-- 공통
    ('bill_type',        '빌링유형',            'enum'),
    ('payment_method',   '결제방법',            'enum'),
    ('is_invoice',       '인보이스유무',         'enum'),
-- sellup
    ('calc_type',        '계산유형    ',        'enum'),
    ('calc_value',       '계산값',              'int'),
    ('contract_date',    '계약일',              'date'),
    ('start_bill_date',  '빌링시작일',           'date'),
    ('source',           '연동자료',            'enum'),
-- tableorder
    ('contract_type',    '계약형태',            'enum'),
    ('ops_qty',          '보급수량',            'int'),
    ('unit_price',       '단가',               'int'),
    ('subs_price',       '월분납액',            'int'),
    ('prepaid_amount',   '선납금액',            'int'),
    ('contract_count',  '계약렌탈횟수',          'int'),
    ('prepaid_count',   '선납횟수',             'int'),
    ('hard_type',        '테이블오더종류',        'enum'),
-- service
    ('service_name',     '제공서비스',           'text'),
    ('service_date',     '서비스제공일',         'date'),
    ('qty',              '수량',               'int'),
    ('price',            '금액',               'int'),
    ('comment',          '비고',               'text')
ON CONFLICT DO NOTHING;
select * from billing.fields;

-- ===========================================
-- sell_type_fields INSERT
-- sell_type별 필요한 field 매핑
-- field_id는 field_name으로 서브쿼리 참조
-- ===========================================

-- sellup
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
--     values ('sellup', '31fee5f8-443e-499e-981f-84878aba34fd', 1);

SELECT 'sellup'::billing.sell_type, f.field_id, t.sort_by
FROM (
    VALUES
        ('bill_type',       1),
        ('calc_type',       2),
        ('calc_value',      3),
        ('contract_date',   4),
        ('start_bill_date', 5),
        ('source',          6),
        ('payment_method',  7),
        ('is_invoice',      8)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;

-- tableorder
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
SELECT 'tableorder', field_id, sort_by FROM (
    VALUES
        ('bill_type',        1),
        ('contract_type',    2),
        ('contract_date',    3),
        ('hard_type',        4),
        ('ops_qty',          5),
        ('unit_price',       6),
        ('subs_price',       7),
        ('prepaid_amount',   8),
        ('contract_count',   9),
        ('prepaid_count',    10),
        ('start_bill_date',  11),
        ('payment_method',   12),
        ('is_invoice',       13)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
SELECT 'qrorder', field_id, sort_by FROM (
    VALUES
        ('bill_type',        1),
        ('contract_date',    2),
        ('ops_qty',          3),
        ('unit_price',       4),
        ('subs_price',       5),
        ('start_bill_date',  6),
        ('payment_method',   7),
        ('is_invoice',       8)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
SELECT 'waiting', field_id, sort_by FROM (
    VALUES
        ('bill_type',        1),
        ('contract_date',    2),
        ('subs_price',       3),
        ('start_bill_date',  4),
        ('payment_method',   5),
        ('is_invoice',       6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;

-- select * from billing.fields;
-- select * from billing.sell_type_fields where sell_type='tableorder';
-- kakaotalk
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
SELECT 'kakaotalk', field_id, sort_by FROM (
    VALUES
        ('bill_type',       1),
        ('contract_date',   2),
        ('unit_price',      3),
        ('source',          4),
        ('payment_method',  5),
        ('is_invoice',      6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;


-- service
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by)
SELECT 'service', field_id, sort_by FROM (
    VALUES
        ('bill_type',     1),
        ('service_name',  2),
        ('service_date',  3),
        ('qty',           4),
        ('price',         5),
        ('comment',       6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id) DO NOTHING;


-- ===========================================
-- sell_type별 필드 리스트
-- ===========================================

SELECT
    stf.sell_type,
    stf.sort_by,
    f.field_name,
    f.field_description,
    f.field_type
FROM billing.sell_type_fields stf
JOIN billing.fields f ON f.field_id = stf.field_id
-- WHERE stf.sell_type='tableorder'
ORDER BY stf.sell_type, stf.sort_by;

-- ===========================================
-- 샘플 데이터
-- ===========================================

-- 매장
INSERT INTO billing.stores (store_no, store_name, bill_day, biz_number, address) VALUES
    (101, '강남 XX식당', 25, '123-45-67890', '서울시 강남구 테헤란로 123');

-- 계좌
INSERT INTO billing.accounts (store_no, bank_no, account_number, holder_name) VALUES
    (101, '004', '123-456-789012', '홍길동');

-- 계약 (sellup 정액)
INSERT INTO billing.contracts (store_no, sell_type, contract_data) VALUES
    (101, 'sellup', '{
        "bill_type": "subs",
        "calc_type": "flat",
        "calc_value": 75000,
        "contract_date": "2025-01-01",
        "start_bill_date": "2025-02-01",
        "source": "fn_get_aisellup"
    }');

-- 계약 (tableorder 렌탈)
INSERT INTO billing.contracts (store_no, sell_type, contract_data) VALUES
    (101, 'tableorder', '{
        "bill_type": "subs",
        "contract_type": "rental",
        "ops_qty": 3,
        "unit_price": 20000,
        "subs_price": 60000,
        "prepaid_amount": 240000,
        "contract_number": 24,
        "prepaid_number": 12,
        "start_bill_date": "2025-01-01",
        "hard_type": "normal"
    }');

-- 계약 (kakaotalk)
INSERT INTO billing.contracts (store_no, sell_type, contract_data) VALUES
    (101, 'kakaotalk', '{
        "bill_type": "subs",
        "contract_date": "2025-03-01",
        "unit_price": 50,
        "source": "fn_get_sms"
    }');

-- billing (2025년 5월 청구서)
INSERT INTO billing.billing (store_no, billing_month, status) VALUES
    (101, '2025-05-01', 'issued');

-- invoice 항목들 (bill_id는 위에서 생성된 UUID 참조)
-- 실제 사용 시 bill_id를 변수로 처리
/*
INSERT INTO billing.invoice (bill_id, sell_type, invoice_data, supply_amount, vat_amount, total_amount)
VALUES
    ('...', 'sellup', '{
        "bill_type": "subs",
        "calc_type": "flat",
        "calc_value": 75000,
        "snapshot_at": "2025-05-01"
    }', 75000, 7500, 82500),

    ('...', 'tableorder', '{
        "bill_type": "subs",
        "contract_type": "rental",
        "ops_qty": 3,
        "unit_price": 20000,
        "subs_price": 60000,
        "snapshot_at": "2025-05-01"
    }', 60000, 6000, 66000),

    ('...', 'kakaotalk', '{
        "bill_type": "subs",
        "unit_price": 50,
        "usage_count": 128,
        "snapshot_at": "2025-05-01"
    }', 6400, 640, 7040);
*/