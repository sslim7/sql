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
CREATE TYPE billing.data_type          AS ENUM ('contract','invoice');
CREATE TYPE billing.calc_type          AS ENUM ('정액', '정률', '무료');
CREATE TYPE billing.sell_type          AS ENUM ('tableorder', 'qrorder', 'sellup', 'kakaotalk', 'waiting', 'service');
CREATE TYPE billing.invoice_status     AS ENUM ('draft', 'issued', 'processing', 'failed', 'paid', 'cancelled');
CREATE TYPE billing.sell_status        AS ENUM ('active', 'paused', 'cancelled');
CREATE TYPE billing.hard_type          AS ENUM ('일반형-선불', '일반형-후불','프리미엄-선불','프리미엄-후불');
CREATE TYPE billing.contract_type      AS ENUM ('약정', '무약정', '무료');
CREATE TYPE billing.payment_method     AS ENUM ('CMS출금', '신용카드');
CREATE TYPE billing.bill_day           AS ENUM ('5','10','15','20','25');
CREATE TYPE billing.agency             AS ENUM ('먼키','권프로');
CREATE TYPE billing.is_invoice         AS ENUM ('발행','발행안함');
CREATE TYPE billing.payment_status     AS ENUM ('CMS출금진행중','CMS출금완료','신용카드','무통장입금','CMS출금실패');
CREATE TYPE billing.commission_type    AS ENUM ('정액', '정률');
CREATE TYPE billing.chart_type         AS ENUM ('bar', 'stacked-bar','line','area','pie');
CREATE TYPE billing.data_source        AS ENUM ('contracts','billing','revenue','settlements');
CREATE TYPE billing.cms_member_status  AS ENUM ('신청전','효성(진행중)','효성(승인완료)','효성(승인실패)');

select * from billing.payments;
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
CREATE TABLE billing.sell_type_fields (
    sell_type_field_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    sell_type          billing.sell_type NOT NULL,          -- 매출유형
    data_type          billing.data_type default 'contract' not null,  -- 자료유형
--     field_id           UUID NOT NULL REFERENCES billing.fields(field_id),
    field_id           UUID NOT NULL ,
    sort_by            SMALLINT NOT NULL DEFAULT 0,          -- 노출순서
    created_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (sell_type, data_type, field_id)
);

COMMENT ON TABLE billing.sell_type_fields IS '매출유형별 필요한 필드 정의';
COMMENT ON COLUMN billing.sell_type_fields.sell_type IS '매출유형';
COMMENT ON COLUMN billing.sell_type_fields.data_type IS '자료유형';
COMMENT ON COLUMN billing.sell_type_fields.field_id IS '필드ID';
COMMENT ON COLUMN billing.sell_type_fields.sort_by IS '노출순서';

alter table billing.sell_type_fields owner to mk;
-- ===========================================
-- stores
-- 빌링매장
-- ===========================================
CREATE TABLE billing.stores (
    store_no    BIGINT PRIMARY KEY,                         -- 매장번호 (public.tb_store 참조)
    store_name  TEXT NOT NULL,                              -- 사업자등록증 상호명
    public_store_nm    TEXT,                                -- 사장님사이트 매장명
    owner_name  TEXT,                                       -- 대표자명
    biz_number  TEXT,                                       -- 사업자번호 (public.tb_store.biz_number 참조)
    address     TEXT,                                       -- 사업장주소
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,              -- 매장상태
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at  TIMESTAMPTZ
);

alter table billing.stores add column public_store_nm    TEXT;

select * from billing.stores;
select * from billing.billing;
select * from billing.invoice;

COMMENT ON TABLE  billing.stores          IS '빌링매장';
COMMENT ON COLUMN billing.stores.store_no IS '매장번호 PK (public.tb_store.store_no 참조)';
COMMENT ON COLUMN billing.stores.store_name IS '사업자등록증 상호명';
COMMENT ON COLUMN billing.stores.public_store_nm IS '사장님사이트 매장명';
COMMENT ON COLUMN billing.stores.owner_name IS '대표자명';
COMMENT ON COLUMN billing.stores.biz_number IS '사업자번호';
COMMENT ON COLUMN billing.stores.address IS '사업장주소';
COMMENT ON COLUMN billing.stores.is_active IS '매장상태';
update billing.stores set public_store_nm=store_name;
CREATE INDEX idx_stores_store_name ON billing.stores USING gin (store_name gin_trgm_ops);
create index idx_stores_owner_name on billing.stores using gin (owner_name gin_trgm_ops);

alter table billing.stores owner to mk;

-- ===========================================
-- accounts
-- 빌링계좌
-- ===========================================

CREATE TABLE billing.cms_banks (
    store_no       BIGINT NOT NULL REFERENCES billing.stores(store_no),
    bank_no        TEXT NOT NULL,                           -- 은행번호
    account_number TEXT NOT NULL,                           -- 계좌번호
    holder_name    TEXT NOT NULL,                           -- 예금주명
    cms_agreement_path TEXT,
    cms_register_response jsonb,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ,

    PRIMARY KEY (store_no)
);

select * from billing.cms_banks;
alter table billing.cms_banks add column cms_register_response jsonb;
COMMENT ON TABLE billing.cms_banks IS '빌링계좌 (매장별 정산 계좌)';
COMMENT ON COLUMN billing.cms_banks.bank_no IS '은행코드';
COMMENT ON COLUMN billing.cms_banks.account_number IS '계좌번호';
COMMENT ON COLUMN billing.cms_banks.holder_name IS '예금주명';
COMMENT ON COLUMN billing.cms_banks.cms_agreement_path IS '출금이체동이서파일링크';
COMMENT ON COLUMN billing.cms_banks.cms_register_response IS '효성에게받은 동의서업로드 응답결과';
-- cms_register_response
-- {
-- "agreementFile":
-- { "registerStatus":
-- "등록",
-- "agreementKey": "1000000000000000000001",
-- "memberId": "MEMBER-01",
-- "memberName": null,
-- "agreementTime": "2020/01/20 15:00:00",
-- "agreementWay": "직접",
-- "agreementKind": "서면",
-- "fileExtension": "jpg",
-- "result": {
-- "code": "Y",
-- "message": "정상 처리"
-- }
-- }
-- }

alter table billing.cms_banks owner to mk;
select * from billing.cms_members;
CREATE TABLE billing.cms_members (
    store_no       BIGINT PRIMARY KEY NOT NULL REFERENCES billing.stores(store_no),
    member_id      varchar(20) not null,
    phone_no       varchar(12),
    is_receipt     boolean default false,
    receipt_number varchar(20),
    payer_number   varchar(10) not null,
    member_status  billing.cms_member_status not null default '신청전',
    request_date   TIMESTAMPTZ,
    request_fail_reason text,
    comment        text,
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ,
    UNIQUE (member_id)
);
create unique index cms_members_member_id on billing.cms_members (member_id);

COMMENT ON TABLE billing.cms_members IS 'CMS 회원가입정보';
COMMENT ON COLUMN billing.cms_members.store_no IS '매장번호';
COMMENT ON COLUMN billing.cms_members.member_id IS '회원번호 NYYMMDD999';
COMMENT ON COLUMN billing.cms_members.phone_no IS '전화번호';
COMMENT ON COLUMN billing.cms_members.is_receipt IS '현금영수증발행여부';
COMMENT ON COLUMN billing.cms_members.receipt_number IS '현금영수증발행번호(전화번호)';
COMMENT ON COLUMN billing.cms_members.payer_number IS '납세자번호(생년월이/사업자번호)';
COMMENT ON COLUMN billing.cms_members.member_status IS 'CMS회원상태';
COMMENT ON COLUMN billing.cms_members.request_date IS 'CMS회원신청일시';
COMMENT ON COLUMN billing.cms_members.request_fail_reason IS '신청실패이유';
COMMENT ON COLUMN billing.cms_members.comment IS '메모';

alter table billing.cms_members owner to mk;

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

-- CREATE TABLE billing.contract_history (
--     cont_hist_id  UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- 계약이력ID
--     cont_id       UUID NOT NULL REFERENCES billing.contracts(cont_id),  -- 계약ID
--     store_no      BIGINT NOT NULL,                              -- 매장번호
--     sell_type     billing.sell_type NOT NULL,                   -- 매출유형
--     contract_data JSONB NOT NULL,                               -- 변경 전 계약데이터
--     sell_status   billing.sell_status NOT NULL,                 -- 변경 전 판매상태
--     created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()            -- 변경시각
-- );
--
-- CREATE INDEX idx_contract_history_cont_id  ON billing.contract_history(cont_id);
-- CREATE INDEX idx_contract_history_store_no ON billing.contract_history(store_no);
-- CREATE INDEX idx_contract_history_time     ON billing.contract_history(created_at DESC);
--
-- COMMENT ON TABLE  billing.contract_history               IS '계약이력 (INSERT: NEW 저장, UPDATE: OLD 저장)';
-- COMMENT ON COLUMN billing.contract_history.cont_id IS '계약ID';
-- COMMENT ON COLUMN billing.contract_history.store_no IS '매장번호';
-- COMMENT ON COLUMN billing.contract_history.sell_type IS '매출유형';
-- COMMENT ON COLUMN billing.contract_history.sell_status IS '판매상태';
--
-- alter table billing.contract_history owner to mk;

-- ===========================================
-- contract_history 자동 적재 트리거
-- INSERT: NEW 저장 (최초 계약 기록)
-- UPDATE: OLD 저장 (변경 전 값 보존)
-- ===========================================

-- CREATE OR REPLACE FUNCTION billing.log_contract_history()
-- RETURNS TRIGGER LANGUAGE plpgsql AS $$
-- BEGIN
--     IF TG_OP = 'INSERT' THEN
--         INSERT INTO billing.contract_history
--             (cont_id, store_no, sell_type, contract_data, sell_status)
--         VALUES
--             (NEW.cont_id, NEW.store_no, NEW.sell_type, NEW.contract_data, NEW.sell_status);
--
--     ELSIF TG_OP = 'UPDATE' THEN
--         INSERT INTO billing.contract_history
--             (cont_id, store_no, sell_type, contract_data, sell_status)
--         VALUES
--             (OLD.cont_id, OLD.store_no, OLD.sell_type, OLD.contract_data, OLD.sell_status);
--     END IF;
--
--     RETURN NEW;
-- END;
-- $$;
--
-- CREATE TRIGGER trg_contract_history
-- AFTER INSERT OR UPDATE ON billing.contracts
-- FOR EACH ROW EXECUTE FUNCTION billing.log_contract_history();
-- DROP TRIGGER IF EXISTS trg_contract_history ON billing.contracts;
-- DROP FUNCTION IF EXISTS billing.log_contract_history();
-- ===========================================
-- billing
-- 송장 (월 청구서 헤더)
-- ===========================================

CREATE TABLE billing.billing (
    bill_id        UUID PRIMARY KEY DEFAULT gen_random_uuid(),  -- 빌링ID
    store_no       BIGINT NOT NULL REFERENCES billing.stores(store_no),
    bill_yymm      TEXT NOT NULL,                               -- 청구년일 (2026-05)
    bill_day       billing.bill_day NOT NULL,                   -- 출금일 (청구년월의 5,10,15,20,25일)
    row_seq        INTEGER NOT NULL DEFAULT 1,                  -- 청구행
    total_amount   INTEGER NOT NULL DEFAULT 0,                  -- 빌링금액합계
    supply_amount  INTEGER NOT NULL DEFAULT 0,                  -- 공급가액
    vat_amount     INTEGER NOT NULL DEFAULT 0,                  -- 부가세
    status         billing.invoice_status NOT NULL DEFAULT 'draft',
    created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ,

    UNIQUE (store_no, bill_yymm, bill_day, row_seq)
);

CREATE INDEX idx_billing_store_no            ON billing.billing(store_no);
CREATE INDEX idx_billing_store_status        ON billing.billing(store_no,status);

COMMENT ON TABLE  billing.billing                IS '송장 (월 청구서 헤더)';
COMMENT ON COLUMN billing.billing.bill_yymm      IS '청구년월 (2026-05)';
COMMENT ON COLUMN billing.billing.bill_day       IS '출금일(청구년월의 5,10,15,20,25일)';
COMMENT ON COLUMN billing.billing.row_seq        IS '청구행(UI용)';
COMMENT ON COLUMN billing.billing.total_amount   IS 'supply_amount + vat_amount (트리거로 자동 갱신)';
COMMENT ON COLUMN billing.billing.supply_amount  IS '공급가';
COMMENT ON COLUMN billing.billing.vat_amount     IS '부가세';
COMMENT ON COLUMN billing.billing.status         IS '빌링상태';

alter table billing.billing owner to mk;

-- ===========================================
-- invoice
-- 송장항목 (line items)
-- ===========================================

CREATE TABLE billing.invoice (
    invoice_id    UUID PRIMARY KEY DEFAULT gen_random_uuid(),   -- 송장항목ID
    bill_id       UUID NOT NULL REFERENCES billing.billing(bill_id) ON DELETE CASCADE,
    cont_id       UUID references billing.contracts(cont_id),
    sell_type     billing.sell_type NOT NULL,                   -- 매출유형
    invoice_data  JSONB,                  -- 빌링데이터 (생성 시점 스냅샷)
    total_amount  INTEGER NOT NULL DEFAULT 0,                       -- 빌링금액
    supply_amount INTEGER NOT NULL DEFAULT 0,                       -- 공급가액
    vat_amount    INTEGER NOT NULL DEFAULT 0,                       -- 부가세
    created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ,

    UNIQUE (bill_id, cont_id)
);

CREATE INDEX idx_invoice_bill_id   ON billing.invoice(bill_id);
CREATE INDEX idx_invoice_sell_type ON billing.invoice(sell_type);

COMMENT ON TABLE  billing.invoice              IS '송장항목 (line items)';
COMMENT ON COLUMN billing.invoice.bill_id IS '빌링ID';
COMMENT ON COLUMN billing.invoice.cont_id IS '계약ID (service면 null)';
COMMENT ON COLUMN billing.invoice.sell_type IS '매출유형';
COMMENT ON COLUMN billing.invoice.invoice_data IS '생성 시점 계약데이터 스냅샷 (이후 contract 변경 영향 없음)';
COMMENT ON COLUMN billing.invoice.total_amount IS '합계';
COMMENT ON COLUMN billing.invoice.supply_amount IS '공급가';
COMMENT ON COLUMN billing.invoice.vat_amount IS '부가세';

alter table billing.invoice owner to mk;

CREATE TABLE billing.payments
(
    payment_id     UUID PRIMARY KEY                DEFAULT gen_random_uuid(), -- 출금처리ID
    payment_status billing.payment_status NOT NULL,                           -- CMS출금완료,신용카드,무통장입금,CMS출금실패
    payment_date   DATE NOT NULL,
    reason         TEXT,
    cms_transaction_id TEXT,
    created_at     TIMESTAMPTZ            NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payments_date             ON billing.payments(payment_date);
CREATE INDEX idx_payments_transaction_id   ON billing.payments(cms_transaction_id);

COMMENT ON TABLE  billing.payments              IS '출금처리정보';
COMMENT ON COLUMN billing.payments.payment_id   IS '출금처리ID';
COMMENT ON COLUMN billing.payments.payment_date IS '철금처리일';
COMMENT ON COLUMN billing.payments.reason       IS '처리사유';
COMMENT ON COLUMN billing.payments.cms_transaction_id       IS '효성에 신청한 transaction_id';

alter table billing.payments owner to mk;

CREATE TABLE billing.payment_detail
(
    pay_dtl_id     UUID PRIMARY KEY                DEFAULT gen_random_uuid(), -- 출금처리상세ID
    payment_id UUID NOT NULL REFERENCES billing.payments(payment_id) ON DELETE CASCADE,
    bill_id   UUID NOT NULL REFERENCES billing.billing(bill_id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES billing.invoice(invoice_id) ON DELETE CASCADE,
    created_at     TIMESTAMPTZ            NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_payinv_payment   ON billing.payment_detail(payment_id);
CREATE INDEX idx_payinv_bill      ON billing.payment_detail(bill_id);
CREATE INDEX idx_payinv_invoice   ON billing.payment_detail(invoice_id);

COMMENT ON TABLE  billing.payment_detail              IS '출금처리정보상세';

alter table billing.payment_detail owner to mk;

CREATE TABLE billing.holidays
(
    holiday_date   DATE PRIMARY KEY NOT NULL,
    holiday_name   text,
    date_Kind      text,
    is_holiday     boolean NOT NULL DEFAULT true,
    created_at     TIMESTAMPTZ            NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  billing.holidays                IS '휴일정보';
COMMENT ON COLUMN billing.holidays.holiday_date   IS '일자';
COMMENT ON COLUMN billing.holidays.holiday_name   IS '휴일명';
COMMENT ON COLUMN billing.holidays.date_kind      IS '휴일종류';
COMMENT ON COLUMN billing.holidays.is_holiday     IS '휴일유무';

alter table billing.holidays owner to mk;

CREATE TABLE billing.settle_contracts
(
    settle_cont_id     UUID PRIMARY KEY                DEFAULT gen_random_uuid(),                -- 정산계약ID
    cont_id            UUID NOT NULL REFERENCES billing.contracts(cont_id) ON DELETE CASCADE,    -- contract_id
    agency_id          VARCHAR NOT NULL,
    is_deduction       BOOLEAN NOT NULL DEFAULT false,
    commission_type    billing.commission_type NOT NULL,
    commission         INT NOT NULL,
    created_at         TIMESTAMPTZ            NOT NULL DEFAULT NOW(),
    UNIQUE (cont_id, agency_id)
);

COMMENT ON TABLE  billing.settle_contracts                      IS '정산계약정보';
COMMENT ON COLUMN billing.settle_contracts.cont_id              IS '계약ID';
COMMENT ON COLUMN billing.settle_contracts.agency_id            IS '에이전시ID';
COMMENT ON COLUMN billing.settle_contracts.is_deduction         IS '기기원가공제여부';
COMMENT ON COLUMN billing.settle_contracts.commission_type      IS '수수료유형';
COMMENT ON COLUMN billing.settle_contracts.commission           IS '수수료';

CREATE INDEX idx_settcont_agency_id      ON billing.settle_contracts(agency_id);
CREATE INDEX idx_settcont_cont_id        ON billing.settle_contracts(cont_id);

alter table billing.settle_contracts owner to mk;
select * from billing.settle_contracts;
select code_id agency_id, code_desc agency_name from public.tb_code where code_group = 'AGENCY' order by sort_order;

insert into public.tb_code (user_gb, code_group, code_id, code_desc, rel_col, sort_order)
SELECT 'USER','AGENCY', id, name,'partner_id',sort_by FROM (
    VALUES
        ('A001','권프로',1),
        ('A002','다음정보통신',2),
        ('A003','하준솔루션',3)
) AS t(id, name, sort_by)
-- ON CONFLICT (user_gb,code_group,code_id) DO NOTHING
;

CREATE INDEX idx_payinv_payment   ON billing.payment_detail(payment_id);
CREATE INDEX idx_payinv_bill      ON billing.payment_detail(bill_id);
CREATE INDEX idx_payinv_invoice   ON billing.payment_detail(invoice_id);

COMMENT ON TABLE  billing.payment_detail              IS '출금처리정보상세';

alter table billing.payment_detail owner to mk;

CREATE TYPE billing.chart_type         AS ENUM ('bar', 'stacked-bar','line','area','pie');
CREATE TYPE billing.data_source        AS ENUM ('contracts','billing','revenue','settlements');
-- 분석 템플릿
CREATE TABLE billing.analytics_template (
    template_id   UUID PRIMARY KEY                    DEFAULT gen_random_uuid(),
    data_source   billing.data_source     NOT NULL,
    label         VARCHAR(100)            NOT NULL,
    config        JSONB                   NOT NULL,
    chart_type    billing.chart_type      NOT NULL    DEFAULT 'bar',
    sort_order    INT NOT NULL DEFAULT 0,
    created_by    UUID,
    created_at    TIMESTAMPTZ             NOT NULL    DEFAULT now()
  );

COMMENT ON TABLE  billing.analytics_template                      IS '빌링분석템플릿';
COMMENT ON COLUMN billing.analytics_template.data_source          IS 'Data Source';
COMMENT ON COLUMN billing.analytics_template.label                IS '표시 레이블';
COMMENT ON COLUMN billing.analytics_template.config               IS '템플릿 구조';
COMMENT ON COLUMN billing.analytics_template.chart_type           IS '차트유형';
COMMENT ON COLUMN billing.analytics_template.sort_order           IS '레이블 표시순서';
COMMENT ON COLUMN billing.analytics_template.created_by           IS '생성자 operations.users.id';

alter table billing.analytics_template owner to mk;
select * from billing.analytics_template;
INSERT INTO billing.analytics_template (data_source, label, config, chart_type, sort_order) VALUES
  -- 계약
  ('contracts', '서비스별 계약현황',
    '{"rows":["sell_type"],"columns":["payment_method"],"values":[{"field":"cont_id","agg":"count","label":"계약수"}],"filters":[]}',
    'bar', 1),

  -- 청구
  ('billing', '월별 청구예정금액',
    '{"rows":["bill_yymm"],"columns":["sell_type"],"values":[{"field":"total_amount","agg":"sum","label":"합계금액"}],"filters":[]}',
    'stacked-bar', 2),
  ('billing', '매장별 청구예정금액',
    '{"rows":["store_name"],"columns":["sell_type"],"values":[{"field":"total_amount","agg":"sum","label":"합계금액"}],"filters":[]}',
    'bar', 3),

  -- 매출
  ('revenue', '월별 매출현황',
    '{"rows":["bill_yymm"],"columns":["sell_type"],"values":[{"field":"total_amount","agg":"sum","label":"합계금액"}],"filters":[]}',
    'stacked-bar', 4),
  ('revenue', '수금율 현황',
    '{"rows":["bill_yymm"],"columns":["payment_status"],"values":[{"field":"total_amount","agg":"sum","label":"금액"}],"filters":[]}',
    'stacked-bar', 5),

  -- 정산
  ('settlements', '에이전시 기여도',
      '{"rows":["agency_name"],"columns":[],"values":[{"field":"sellup_fee","agg":"sum","label":"매출업요금"},{"field":"settle_target","agg":"sum","label":"정산대상금액"},{"field":"settle_amount","agg":"sum","label":"정산금"}],"filters":[]}',
      'bar', 6),
    ('settlements', '에이전시 공제금액 추이',
      '{"rows":["bill_yymm"],"columns":["agency_name"],"values":[{"field":"deduct_amount","agg":"sum","label":"공제금액"}],"filters":[]}',
      'line', 7),
    ('settlements', '매출업요금 vs 정산금 추이',
      '{"rows":["bill_yymm"],"columns":[],"values":[{"field":"sellup_fee","agg":"sum","label":"매출업요금"},{"field":"settle_amount","agg":"sum","label":"정산금"}],"filters":[]}',
      'area', 8);

select * from billing.analytics_template ;

  UPDATE billing.analytics_template
  SET config = '{"rows":["agency_name"],"columns":[],"values":[{"field":"sellup_fee","agg":"sum","label":"매출업요금"},{"field":"settle_target","agg":"sum","label":"정산대상금액"},{"field":"settle_amount","agg":"sum","label":"정산금"}],"filters":[]}'
  WHERE label = '에이전시 기여도' AND data_source = 'settlements';

  UPDATE billing.analytics_template
  SET label = '에이전시 공제금액 추이',
      config = '{"rows":["bill_yymm"],"columns":["agency_name"],"values":[{"field":"deduct_amount","agg":"sum","label":"공제금액"}],"filters":[]}'
  WHERE label = '에이전시 공제액 추이' AND data_source = 'settlements';

  UPDATE billing.analytics_template
  SET label = '매출업요금 vs 정산금 추이',
      config = '{"rows":["bill_yymm"],"columns":[],"values":[{"field":"sellup_fee","agg":"sum","label":"매출업요금"},{"field":"settle_amount","agg":"sum","label":"정산금"}],"filters":[]}'
  WHERE label = 'Take Rate 추이' AND data_source = 'settlements';


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
select * from billing.fields;
INSERT INTO billing.fields (field_name, field_description, field_type) VALUES
--공통
    ('bill_type',        '빌링유형',            'enum'),
    ('payment_method',   '결제방법',            'enum'),
    ('is_invoice',       '인보이스 발행',        'enum'),
    ('bill_day',         '출금일',             'enum'),
-- sellup
    ('calc_type',        '계산유형    ',        'enum'),
    ('calc_value',       '계산값',              'int'),
    ('contract_date',    '계약일',              'date'),
    ('start_bill_date',  '빌링시작일',           'date'),
--     ('source',           '연동자료',            'enum'),
-- tableorder
    ('contract_type',    '계약형태',            'enum'),
    ('ops_qty',          '보급수량',            'int'),
    ('unit_price',       '단가',               'int'),
    ('subs_price',       '월분납액',            'int'),
    ('prepaid_amount',   '선납금액',            'int'),
    ('contract_count',  '계약렌탈횟수',          'int'),
    ('prepaid_count',   '선납횟수',             'int'),
    ('hard_type',        '테이블오더종류',        'enum'),
-- invoice
    ('service_name',     '제공서비스',           'text'),
    ('service_date',     '서비스제공일',          'date'),
    ('qty',              '수량',                'int'),
    ('comment',          '비고',                'text'),
    ('supply_amount',    '공급가',               'int'),
    ('vat_amount',       '부가세',               'int'),
    ('ai_sales',         'ai-매출액',            'int'),
    ('cms_cont_no',      'CMS 계약번호',         'text'),
    ('agency',           '대리점',              'enum'),
    ('commission_type',  '수수료율 유형',        'enum'),
    ('commission_rate',  '수수료 율',           'int'),
    ('settle_unit_price',  '정산차감 단가',           'int')

ON CONFLICT DO NOTHING;
select * from billing.fields;
-- ===========================================
-- CONTACT
-- sell_type_fields INSERT
-- sell_type별 필요한 field 매핑
-- field_id는 field_name으로 서브쿼리 참조
-- ===========================================
-- tableorder

delete from billing.sell_type_fields where sell_type='tableorder' and data_type='contract';

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by, data_type)
SELECT 'tableorder', field_id, sort_by, 'contract' FROM (
    VALUES
        ('contract_type',     1),
        ('contract_date',     2),
        ('hard_type',         3),
        ('ops_qty',           4),
        ('unit_price',        5),
        ('subs_price',        6),
        ('prepaid_amount',    7),
        ('contract_count',    8),
        ('start_bill_date',   9),
        ('payment_method',    10),
        ('bill_day',          11),
        ('cms_cont_no',       12),
        ('settle_unit_price', 13)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by, data_type)
SELECT 'qrorder', field_id, sort_by, 'contract' FROM (
    VALUES
        ('contract_date',    1),
        ('ops_qty',          2),
        ('unit_price',       3),
        ('subs_price',       4),
        ('start_bill_date',  5),
        ('payment_method',   6),
        ('bill_day',         7)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- sellup

delete from billing.sell_type_fields where sell_type='sellup' and data_type='contract';

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by, data_type)
SELECT 'sellup'::billing.sell_type, f.field_id, t.sort_by, 'contract'
FROM (
    VALUES
        ('calc_type',       1),
        ('calc_value',      2),
        ('contract_date',   3),
        ('start_bill_date', 4),
        ('payment_method',  5),
        ('bill_day',        6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by, data_type)
SELECT 'waiting', field_id, sort_by, 'contract' FROM (
    VALUES
        ('contract_date',    1),
        ('subs_price',       2),
        ('start_bill_date',  3),
        ('payment_method',   4),
        ('bill_day',         5)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- select * from billing.fields;
-- select * from billing.sell_type_fields where sell_type='tableorder';
-- kakaotalk
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by, data_type)
SELECT 'kakaotalk', field_id, sort_by, 'contract' FROM (
    VALUES
--         ('contract_date',   1),
--         ('unit_price',      2),
--         ('start_bill_date', 3),
--         ('payment_method',  4),
        ('bill_day',        5)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- *****************************
-- ***** INVOICE
-- *****************************
-- tableorder
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'tableorder', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('qty',             1),
--         ('unit_price',      2),
--         ('supply_amount',   3),
--         ('vat_amount',      4),
        ('comment', 5)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- qrorder
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'qrorder', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('qty',             1),
--         ('unit_price',      2),
--         ('supply_amount',   3),
--         ('vat_amount',      4),
        ('comment',         5)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- sellup
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'sellup', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('ai_sales',        1),
--         ('calc_type',       2),
--         ('calc_value',      3),
--         ('supply_amount',   4),
--         ('vat_amount',      5),
        ('comment',         6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- waiting
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'waiting', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('supply_amount',   1),
--         ('vat_amount',      2),
        ('comment',         3)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;
select * from billing.billing;
-- kakaotalk
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'kakaotalk', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('qty',             1),
--         ('unit_price',      2),
--         ('supply_amount',   3),
--         ('vat_amount',      4),
        ('comment',         5)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;

-- service
INSERT INTO billing.sell_type_fields (sell_type, field_id, sort_by,data_type)
SELECT 'service', field_id, sort_by, 'invoice' FROM (
    VALUES
--         ('service_name',    1),
--         ('service_date',    2),
--         ('qty',             3),
--         ('supply_amount',   4),
--         ('vat_amount',      5),
        ('comment',         6)
) AS t(fname, sort_by)
JOIN billing.fields f ON f.field_name = t.fname
ON CONFLICT (sell_type, field_id, data_type) DO NOTHING;
-- ===========================================
-- sell_type별 필드 리스트
-- ===========================================

SELECT stf.*
--     stf.sell_type,
--     stf.sort_by,
--     f.field_name,
--     f.field_description,
--     f.field_type
FROM billing.sell_type_fields stf
JOIN billing.fields f ON f.field_id = stf.field_id
WHERE stf.data_type='contract'
-- AND stf.sell_type='tableorder'
ORDER BY stf.sell_type, stf.sort_by;
select * from billing.fields;
      SELECT
        stf.sell_type,
        stf.sort_by,
        f.field_name,
        f.field_description,
        f.field_type
      FROM billing.sell_type_fields stf
      JOIN billing.fields f ON f.field_id = stf.field_id
      WHERE stf.sell_type = 'sellup' AND stf.data_type='invoice'
      ORDER BY stf.sort_by;

년월: 2026-06

처리일자      합계   cms출금  신용카드   무통장입금   출금실패
2026-06-01  10      7       1         1        1
2026-06-02   5      4       0         0        0

select
    pm.payment_date as 처리일자,
    count(distinct pd.bill_id) as 합계,
    count(distinct pd.bill_id) filter (where pm.payment_status = 'CMS출금완료')  as cms출금,
    count(distinct pd.bill_id) filter (where pm.payment_status = '신용카드')      as 신용카드,
    count(distinct pd.bill_id) filter (where pm.payment_status = '무통장입금')    as 무통장입금,
    count(distinct pd.bill_id) filter (where pm.payment_status = 'CMS출금실패')  as 출금실패
  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id = pd.payment_id
  join billing.billing bl on pd.bill_id = bl.bill_id
 where pm.payment_date >= (:payment_yymm || '-01')::date
   and pm.payment_date <  ((:payment_yymm || '-01')::date + interval '1 month')
 group by pm.payment_date
 order by pm.payment_date;

select
    bl.store_no,st.store_name,st.biz_number,bl.bill_yymm,
    sum(iv.total_amount),
    sum(iv.total_amount) filter (where iv.sell_type = 'tableorder')  as tableorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'qrorder')     as qrorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'sellup')   as sellup,
    sum(iv.total_amount) filter (where iv.sell_type = 'waiting')  as waiting,
    sum(iv.total_amount) filter (where iv.sell_type = 'kakaotalk')   as kakaotalk,
    sum(iv.total_amount) filter (where iv.sell_type = 'service')   as service
  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id = pd.payment_id
  join billing.billing bl on pd.bill_id = bl.bill_id
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
  join billing.stores st on bl.store_no=st.store_no
 where pm.payment_date=:p_date and pm.payment_status=:p_status
 group by bl.store_no,st.store_name,st.biz_number,bl.bill_yymm
 order by st.store_name COLLATE "ko-KR-x-icu", bl.bill_yymm;

select * from billing.invoice;
--   join billing.invoice iv on pd.invoice_id=iv.invoice_id

select status,count(1) from table_order.sms_send_log where store_no=709 and created_at >= (:dt_from at time zone 'Asia/Seoul')::date and created_at < (:dt_to at time zone 'Asia/Seoul')::date
group by 1;
show time zone;
select status,count(1) from table_order.sms_send_log where store_no=709 and created_at >= (:dt_from)::date and created_at < (:dt_to)::date
group by 1;

select billing.get_kakaotalk_count('2026-05',709);

WITH tz AS MATERIALIZED (
  SELECT
    (date_trunc('month', to_date(:p_base_yymm, 'YYYY-MM'))
      AT TIME ZONE 'UTC')                  AS utc_from,
    ((date_trunc('month', to_date(:p_base_yymm, 'YYYY-MM'))
      + interval '1 month')
      AT TIME ZONE 'UTC')                  AS utc_to
)

SELECT COUNT(1)::bigint
FROM table_order.sms_send_log
WHERE store_no  = :p_store_no
  AND status    = 'SENT'
  AND created_at >= (SELECT utc_from FROM tz)
  AND created_at <  (SELECT utc_to   FROM tz);

select * from billing.invoice where sell_type='kakaotalk';

select
    bl.store_no,st.store_name,st.biz_number,bl.bill_yymm,
    sum(iv.total_amount),
    sum(iv.total_amount) filter (where iv.sell_type = 'tableorder')  as tableorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'qrorder')     as qrorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'sellup')   as sellup,
    sum(iv.total_amount) filter (where iv.sell_type = 'waiting')  as waiting,
    sum(iv.total_amount) filter (where iv.sell_type = 'kakaotalk')   as kakaotalk,
    sum(iv.total_amount) filter (where iv.sell_type = 'service')   as service
  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id = pd.payment_id
  join billing.billing bl on pd.bill_id = bl.bill_id and bl.store_no=:store_no
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
  join billing.stores st on bl.store_no=st.store_no
 group by bl.store_no,st.store_name,st.biz_number,bl.bill_yymm
 order by st.store_name COLLATE "ko-KR-x-icu", bl.bill_yymm;

TYPE billing.sell_type          AS ENUM ('tableorder', 'qrorder', 'sellup', 'waiting', 'kakaotalk', 'service');
-- 테이블오더,큐알오더,매출업,웨이팅,알림톡,서비스
select sell_type,contract_data from billing.contracts where store_no=:store_no;

select
    pm.payment_date,pm.payment_status,bl.bill_yymm,
    sum(iv.total_amount),
    sum(iv.total_amount) filter (where iv.sell_type = 'tableorder')  as tableorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'qrorder')     as qrorder,
    sum(iv.total_amount) filter (where iv.sell_type = 'sellup')   as sellup,
    sum(iv.total_amount) filter (where iv.sell_type = 'waiting')  as waiting,
    sum(iv.total_amount) filter (where iv.sell_type = 'kakaotalk')   as kakaotalk,
    sum(iv.total_amount) filter (where iv.sell_type = 'service')   as service
  from billing.payments pm
  join billing.payment_detail pd on pm.payment_id = pd.payment_id
  join billing.billing bl on pd.bill_id = bl.bill_id and bl.store_no=:store_no
  join billing.invoice iv on pd.invoice_id=iv.invoice_id
  join billing.stores st on bl.store_no=st.store_no
  where iv.sell_type in (:status)
 group by pm.payment_date,pm.payment_status,bl.bill_yymm
 order by pm.payment_date, bl.bill_yymm;

select * from billing.payment_detail;