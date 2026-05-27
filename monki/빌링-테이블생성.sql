-- ===========================================
-- Monki Billing Schema v2
-- 스냅샷 기반 플랜 히스토리 관리
-- ===========================================

CREATE SCHEMA IF NOT EXISTS billing;

-- ===========================================
-- ENUM types
-- ===========================================

CREATE TYPE billing.plan_type           AS ENUM ('flat', 'rate');
CREATE TYPE billing.contract_type       AS ENUM ('rental', 'subscription', 'free');
CREATE TYPE billing.subs_type           AS ENUM ('sellup', 'hardware', 'kakaotalk');
CREATE TYPE billing.subscription_status AS ENUM ('active', 'paused', 'cancelled');
CREATE TYPE billing.invoice_status      AS ENUM ('draft', 'issued', 'paid', 'overdue');
CREATE TYPE billing.item_type           AS ENUM ('sellup', 'hardware', 'kakaotalk', 'service');


-- ===========================================
-- plans
-- 매장별 협의 요금제 + 변경 히스토리
-- 한 매장에 동시에 active plan은 subs_type당 1개
-- ===========================================

CREATE TABLE billing.plans (
    id              BIGSERIAL PRIMARY KEY,
    store_id        BIGINT NOT NULL,                    -- monki.stores.id
    subs_type       billing.subs_type NOT NULL,         -- 어떤 구독의 플랜인지
    plan_type       billing.plan_type NOT NULL,
    amount          NUMERIC(12, 2),                     -- 정액: 협의 금액
    rate            NUMERIC(5, 4),                      -- 정률: 요율 (0.0500 = 5%)
    valid_from      DATE NOT NULL,                      -- 적용 시작일
    valid_to        DATE,                               -- 적용 종료일 (NULL = 현재 적용중)
    note            TEXT,                               -- 협의 내용 메모
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- 매장+타입 기준 현재 플랜은 1개만
    CONSTRAINT uq_plans_active UNIQUE NULLS NOT DISTINCT (store_id, subs_type, valid_to),

    CONSTRAINT chk_plan_flat CHECK (plan_type != 'flat' OR amount IS NOT NULL),
    CONSTRAINT chk_plan_rate CHECK (plan_type != 'rate' OR rate IS NOT NULL),
    CONSTRAINT chk_plan_dates CHECK (valid_to IS NULL OR valid_to > valid_from)
);

CREATE INDEX idx_plans_store_id  ON billing.plans(store_id);
CREATE INDEX idx_plans_active    ON billing.plans(store_id, subs_type) WHERE valid_to IS NULL;

COMMENT ON TABLE  billing.plans            IS '매장별 협의 요금제 (변경 시 valid_to 세팅 후 신규 행 추가)';
COMMENT ON COLUMN billing.plans.valid_to   IS 'NULL = 현재 적용중. 플랜 변경 시 이전 행에 valid_to 설정';
COMMENT ON COLUMN billing.plans.subs_type  IS 'sellup 전용. hardware/kakaotalk는 subscription.meta로 관리';


-- ===========================================
-- subscriptions
-- 매장의 정기 구독 계약 (subs_type별)
-- ===========================================

CREATE TABLE billing.subscriptions (
    id                  BIGSERIAL PRIMARY KEY,
    store_id            BIGINT NOT NULL,
    subs_type           billing.subs_type NOT NULL,
    billing_start_date  DATE NOT NULL,
    status              billing.subscription_status NOT NULL DEFAULT 'active',
    meta                JSONB NOT NULL DEFAULT '{}',    -- 타입별 기준정보 (아래 주석)
    note                TEXT,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subscriptions_store_id   ON billing.subscriptions(store_id);
CREATE INDEX idx_subscriptions_store_type ON billing.subscriptions(store_id, subs_type);
CREATE INDEX idx_subscriptions_status     ON billing.subscriptions(status);

COMMENT ON COLUMN billing.subscriptions.meta IS '
  [sellup]
    {} -- 금액정보는 plans 테이블에서 관리

  [hardware]
    {
      "contract_type": "rental" | "subscription" | "free",
      "quantity": 3,
      "unit_price": 20000
    }

  [kakaotalk]
    {
      "unit_price": 50    -- 건당 단가, 사용량은 invoice 생성 시 입력
    }
';


-- ===========================================
-- invoices
-- 월 청구서 (매장별, 월별 1건)
-- ===========================================

CREATE TABLE billing.invoices (
    id              BIGSERIAL PRIMARY KEY,
    store_id        BIGINT NOT NULL,
    billing_month   DATE NOT NULL,                      -- 항상 1일로 저장 (e.g. 2025-05-01)
    total_amount    NUMERIC(12, 2) NOT NULL DEFAULT 0,  -- invoice_items 합산 (트리거 유지)
    status          billing.invoice_status NOT NULL DEFAULT 'draft',
    note            TEXT,
    issued_at       TIMESTAMPTZ,
    paid_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (store_id, billing_month)
);

CREATE INDEX idx_invoices_store_id      ON billing.invoices(store_id);
CREATE INDEX idx_invoices_billing_month ON billing.invoices(billing_month);
CREATE INDEX idx_invoices_status        ON billing.invoices(status);

COMMENT ON COLUMN billing.invoices.billing_month IS '청구 대상 월 (항상 1일, e.g. 2025-05-01)';


-- ===========================================
-- invoice_items
-- 청구 항목 + 생성 시점 스냅샷
-- ===========================================

CREATE TABLE billing.invoice_items (
    id              BIGSERIAL PRIMARY KEY,
    invoice_id      BIGINT NOT NULL REFERENCES billing.invoices(id) ON DELETE CASCADE,
    subscription_id BIGINT REFERENCES billing.subscriptions(id),  -- service는 NULL
    item_type       billing.item_type NOT NULL,
    name            VARCHAR(200) NOT NULL,
    amount          NUMERIC(12, 2) NOT NULL,
    snapshot        JSONB NOT NULL DEFAULT '{}',        -- 생성 시점 기준정보 스냅샷
    note            TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_invoice_items_invoice_id      ON billing.invoice_items(invoice_id);
CREATE INDEX idx_invoice_items_subscription_id ON billing.invoice_items(subscription_id);

COMMENT ON COLUMN billing.invoice_items.subscription_id IS 'service 타입은 NULL (수동 입력)';
COMMENT ON COLUMN billing.invoice_items.snapshot IS '
  invoice 생성 시점의 기준정보 스냅샷.
  플랜/단가가 나중에 바뀌어도 과거 청구서는 이 값 기준.

  [sellup]
    {
      "plan_id": 12,
      "plan_type": "flat",
      "amount": 75000,
      "snapshot_at": "2025-05-01"
    }
    {
      "plan_id": 13,
      "plan_type": "rate",
      "rate": 0.05,
      "base_amount": 8500000,
      "snapshot_at": "2025-05-01"
    }

  [hardware]
    {
      "contract_type": "rental",
      "quantity": 3,
      "unit_price": 20000,
      "snapshot_at": "2025-05-01"
    }

  [kakaotalk]
    {
      "unit_price": 50,
      "usage_count": 128,
      "snapshot_at": "2025-05-01"
    }

  [service]
    {
      "items": [
        {"name": "공유기", "amount": 50000},
        {"name": "문자발송", "amount": 300000},
        {"name": "출장비", "amount": 50000}
      ]
    }
';


-- ===========================================
-- total_amount 자동 갱신 트리거
-- ===========================================

CREATE OR REPLACE FUNCTION billing.sync_invoice_total()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE
    v_invoice_id BIGINT;
BEGIN
    v_invoice_id := COALESCE(NEW.invoice_id, OLD.invoice_id);
    UPDATE billing.invoices
    SET
        total_amount = (
            SELECT COALESCE(SUM(amount), 0)
            FROM billing.invoice_items
            WHERE invoice_id = v_invoice_id
        ),
        updated_at = NOW()
    WHERE id = v_invoice_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_invoice_total
AFTER INSERT OR UPDATE OR DELETE ON billing.invoice_items
FOR EACH ROW EXECUTE FUNCTION billing.sync_invoice_total();


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

CREATE TRIGGER trg_plans_updated_at         BEFORE UPDATE ON billing.plans         FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_subscriptions_updated_at BEFORE UPDATE ON billing.subscriptions FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_invoices_updated_at      BEFORE UPDATE ON billing.invoices      FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();
CREATE TRIGGER trg_invoice_items_updated_at BEFORE UPDATE ON billing.invoice_items FOR EACH ROW EXECUTE FUNCTION billing.set_updated_at();


-- ===========================================
-- 플랜 변경 헬퍼 함수
-- 기존 플랜 종료 + 신규 플랜 삽입을 트랜잭션으로
-- ===========================================

CREATE OR REPLACE FUNCTION billing.change_plan(
    p_store_id      BIGINT,
    p_subs_type     billing.subs_type,
    p_plan_type     billing.plan_type,
    p_amount        NUMERIC DEFAULT NULL,
    p_rate          NUMERIC DEFAULT NULL,
    p_valid_from    DATE DEFAULT CURRENT_DATE,
    p_note          TEXT DEFAULT NULL
)
RETURNS billing.plans LANGUAGE plpgsql AS $$
DECLARE
    v_new_plan billing.plans;
BEGIN
    -- 기존 active 플랜 종료
    UPDATE billing.plans
    SET valid_to = p_valid_from - INTERVAL '1 day',
        updated_at = NOW()
    WHERE store_id = p_store_id
      AND subs_type = p_subs_type
      AND valid_to IS NULL;

    -- 신규 플랜 삽입
    INSERT INTO billing.plans (store_id, subs_type, plan_type, amount, rate, valid_from, note)
    VALUES (p_store_id, p_subs_type, p_plan_type, p_amount, p_rate, p_valid_from, p_note)
    RETURNING * INTO v_new_plan;

    RETURN v_new_plan;
END;
$$;

COMMENT ON FUNCTION billing.change_plan IS '
  플랜 변경 사용 예:
  -- 정액 변경
  SELECT billing.change_plan(101, ''sellup'', ''flat'', 100000, NULL, ''2025-06-01'', ''6월부터 인상 협의'');
  -- 정률 변경
  SELECT billing.change_plan(101, ''sellup'', ''rate'', NULL, 0.05, ''2025-06-01'', ''정률로 전환'');
';


-- ===========================================
-- invoice 자동 생성 함수
-- 특정 월의 active subscription → invoice_items 자동 주입
-- (kakaotalk usage_count, service는 별도 추가 필요)
-- ===========================================

CREATE OR REPLACE FUNCTION billing.generate_invoice(
    p_store_id      BIGINT,
    p_billing_month DATE    -- 항상 1일로 넘길 것
)
RETURNS billing.invoices LANGUAGE plpgsql AS $$
DECLARE
    v_invoice   billing.invoices;
    v_sub       billing.subscriptions;
    v_plan      billing.plans;
    v_amount    NUMERIC(12,2);
    v_snapshot  JSONB;
BEGIN
    -- invoice 생성 (이미 있으면 기존 반환)
    INSERT INTO billing.invoices (store_id, billing_month)
    VALUES (p_store_id, DATE_TRUNC('month', p_billing_month))
    ON CONFLICT (store_id, billing_month) DO UPDATE SET updated_at = NOW()
    RETURNING * INTO v_invoice;

    -- active subscription 순회
    FOR v_sub IN
        SELECT * FROM billing.subscriptions
        WHERE store_id = p_store_id AND status = 'active'
    LOOP
        -- 이미 해당 subscription 항목이 있으면 스킵
        CONTINUE WHEN EXISTS (
            SELECT 1 FROM billing.invoice_items
            WHERE invoice_id = v_invoice.id
              AND subscription_id = v_sub.id
        );

        IF v_sub.subs_type = 'sellup' THEN
            -- 해당 시점 active plan 조회
            SELECT * INTO v_plan
            FROM billing.plans
            WHERE store_id = p_store_id
              AND subs_type = 'sellup'
              AND valid_from <= p_billing_month
              AND (valid_to IS NULL OR valid_to >= p_billing_month)
            ORDER BY valid_from DESC
            LIMIT 1;

            IF v_plan IS NULL THEN CONTINUE; END IF;

            IF v_plan.plan_type = 'flat' THEN
                v_amount   := v_plan.amount;
                v_snapshot := jsonb_build_object(
                    'plan_id', v_plan.id, 'plan_type', 'flat',
                    'amount', v_plan.amount, 'snapshot_at', p_billing_month
                );
            ELSE
                -- 정률: base_amount는 청구 시점에 별도 입력 필요 → 0으로 우선 생성
                v_amount   := 0;
                v_snapshot := jsonb_build_object(
                    'plan_id', v_plan.id, 'plan_type', 'rate',
                    'rate', v_plan.rate, 'base_amount', 0,
                    'snapshot_at', p_billing_month
                );
            END IF;

            INSERT INTO billing.invoice_items (invoice_id, subscription_id, item_type, name, amount, snapshot)
            VALUES (v_invoice.id, v_sub.id, 'sellup', '매출업', v_amount, v_snapshot);

        ELSIF v_sub.subs_type = 'hardware' THEN
            v_amount := (v_sub.meta->>'quantity')::NUMERIC * (v_sub.meta->>'unit_price')::NUMERIC;
            v_snapshot := v_sub.meta || jsonb_build_object('snapshot_at', p_billing_month);

            INSERT INTO billing.invoice_items (invoice_id, subscription_id, item_type, name, amount, snapshot)
            VALUES (v_invoice.id, v_sub.id, 'hardware', '테이블오더 디바이스', v_amount, v_snapshot);

        ELSIF v_sub.subs_type = 'kakaotalk' THEN
            -- usage_count는 0으로 생성 후 별도 업데이트
            v_snapshot := v_sub.meta || jsonb_build_object('usage_count', 0, 'snapshot_at', p_billing_month);

            INSERT INTO billing.invoice_items (invoice_id, subscription_id, item_type, name, amount, snapshot)
            VALUES (v_invoice.id, v_sub.id, 'kakaotalk', '알림톡', 0, v_snapshot);
        END IF;
    END LOOP;

    RETURN v_invoice;
END;
$$;

COMMENT ON FUNCTION billing.generate_invoice IS '
  사용 예:
  SELECT billing.generate_invoice(101, ''2025-05-01'');

  생성 후 수동 처리 필요:
  1. 정률 sellup → base_amount 업데이트
  2. kakaotalk → usage_count 업데이트
  3. service 항목 → invoice_items에 직접 INSERT
';


-- ===========================================
-- 샘플 데이터
-- ===========================================

-- 매장 101: sellup 정액 플랜 (2025-01-01 시작, 2025-04-30 종료)
INSERT INTO billing.plans (store_id, subs_type, plan_type, amount, valid_from, valid_to, note)
VALUES (101, 'sellup', 'flat', 75000, '2025-01-01', '2025-04-30', '초기 협의가');

-- 매장 101: sellup 플랜 변경 (2025-05-01~)
INSERT INTO billing.plans (store_id, subs_type, plan_type, amount, valid_from, note)
VALUES (101, 'sellup', 'flat', 100000, '2025-05-01', '5월 재협의');

-- 매장 101: subscriptions
INSERT INTO billing.subscriptions (store_id, subs_type, billing_start_date, meta) VALUES
    (101, 'sellup',    '2025-01-01', '{}'),
    (101, 'hardware',  '2025-01-01', '{"contract_type":"rental","quantity":3,"unit_price":20000}'),
    (101, 'kakaotalk', '2025-03-01', '{"unit_price":50}');