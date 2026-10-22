
-- schema 1행 + table 8행
SELECT 'schema'  AS kind, nspname AS name FROM pg_namespace WHERE nspname = 'sellup'
UNION ALL
SELECT 'table', c.relname FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
 WHERE n.nspname = 'sellup' AND c.relkind = 'r'
   AND c.relname IN ('campaign','campaign_user','apilot_config_store','apilot_config_system',
                     'holdout_policy','apilot_node_registry','apilot_run','apilot_run_node')
ORDER BY kind, name;

--적용 전 기록(롤백 보호용)
SELECT config_key, config_value_json
FROM sellup.apilot_config_system
ORDER BY config_key;

INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.max_allow_discount_amount', '{"value": 10000}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.max_allow_discount_rate', '{"value": 0.15}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.max_coupon_valid_days', '{"value": 7}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.min_customers', '{"value": 30}');
-- INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.min_open_days', '{"value": 14}');
-- INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.min_orders', '{"value": 50}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.monthly_allow_discount_rate', '{"value": 0.02}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.persona.recipient_cap_rate', '{"BALANCED": 0.30, "AGGRESSIVE": 0.70, "CONSERVATIVE": 0.10}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.run_lease_hours', '{"value": 12}');
INSERT INTO sellup.apilot_config_system (config_key, config_value_json) VALUES ('apilot.sales_good_bad_pct', '{"value": -3}');

-- 1.1 기존 테이블 변경 — sellup.campaign
BEGIN;
ALTER TABLE sellup.campaign ADD COLUMN IF NOT EXISTS opportunity_snapshot_id UUID    NULL;
ALTER TABLE sellup.campaign ADD COLUMN IF NOT EXISTS is_measurement          BOOLEAN NOT NULL DEFAULT FALSE;
ALTER TABLE sellup.campaign ADD COLUMN IF NOT EXISTS v2_json                 JSONB   NULL;
COMMENT ON COLUMN sellup.campaign.is_measurement
  IS '측정용 캠페인. 타겟 >= 250, 홀드아웃 0.12 강제. 점주에게 노출하지 않는다 (sellup-v2 6.3.1)';
COMMENT ON COLUMN sellup.campaign.v2_json
  IS 'V2 결정 컨텍스트. 조회는 opportunity_snapshot_id 조인으로 한다 (sellup-v2 8.9)';
CREATE INDEX IF NOT EXISTS ix_campaign_opp
  ON sellup.campaign (opportunity_snapshot_id);
-- 동일 opportunity_type 동시 진행 상한(기본 1) 검사의 주 경로.
-- opportunity_type이 v2_json 안이므로 표현식 인덱스다 (sellup-v2 8.0 승격 기준)
CREATE INDEX IF NOT EXISTS ix_campaign_inflight
  ON sellup.campaign (store_no, (v2_json->>'opportunity_type'), status);
COMMIT;

-- 1.2 기존 테이블 변경 — sellup.campaign_user
BEGIN;

ALTER TABLE sellup.campaign_user ADD COLUMN IF NOT EXISTS exclude_reason TEXT     NULL;
ALTER TABLE sellup.campaign_user ADD COLUMN IF NOT EXISTS holdout_bucket SMALLINT NULL;

ALTER TABLE sellup.campaign_user
  DROP CONSTRAINT IF EXISTS ck_cu_bucket;
ALTER TABLE sellup.campaign_user
  ADD  CONSTRAINT ck_cu_bucket
  CHECK (holdout_bucket IS NULL OR (holdout_bucket >= 0 AND holdout_bucket <= 99));

-- exclude_reason 값역도 enum이 아니라 CHECK로 (§0.3)
ALTER TABLE sellup.campaign_user DROP CONSTRAINT IF EXISTS ck_cu_exclude_reason;
ALTER TABLE sellup.campaign_user
  ADD  CONSTRAINT ck_cu_exclude_reason
  CHECK (exclude_reason IS NULL OR exclude_reason IN
    ('HAS_COUPON','RECENT_SEND_7D','FATIGUE_CAP','OPT_OUT','INVALID_CONTACT','GHOST'));

COMMENT ON COLUMN sellup.campaign_user.exclude_reason
  IS 'HAS_COUPON | RECENT_SEND_7D | FATIGUE_CAP | OPT_OUT | INVALID_CONTACT | GHOST';
COMMENT ON COLUMN sellup.campaign_user.holdout_bucket
  IS 'hash(store_no, user_id, YYYYMM) mod 100. 0~99 (sellup-v2 6.1.2)';

CREATE INDEX IF NOT EXISTS ix_cu_campaign_status
  ON sellup.campaign_user (campaign_id, status);
CREATE INDEX IF NOT EXISTS ix_cu_campaign_holdout
  ON sellup.campaign_user (campaign_id, holdout);
-- 사전 제외 집단만 세는 경로 (population_json.exclude_breakdown)
CREATE INDEX IF NOT EXISTS ix_cu_excluded
  ON sellup.campaign_user (campaign_id, exclude_reason)
  WHERE exclude_reason IS NOT NULL;

COMMIT;

-- 1.3 기존 테이블 변경 — sellup.apilot_config_store
BEGIN;

-- 실컬럼 3개. 전부 조회 조건이다.
--   apilot_mode             : 배치가 매일 WHERE apilot_mode = 'V2'로 대상 매장을 고른다
--   guardrail_paused_until  : 가드레일 평가가 WHERE ... > now()로 정지 매장을 센다
--   enable_customer_trigger : Phase 4 롤백 플래그
ALTER TABLE sellup.apilot_config_store
  ADD COLUMN IF NOT EXISTS apilot_mode             TEXT        NOT NULL DEFAULT 'V1',
  ADD COLUMN IF NOT EXISTS guardrail_paused_until  TIMESTAMPTZ NULL,
  ADD COLUMN IF NOT EXISTS enable_customer_trigger BOOLEAN     NOT NULL DEFAULT FALSE;

-- V2 파라미터 20개는 JSONB 하나로. 포맷 명세는 6.20
ALTER TABLE sellup.apilot_config_store
  ADD COLUMN IF NOT EXISTS v2_params_json          JSONB       NOT NULL DEFAULT '{}'::jsonb;

COMMIT;

BEGIN;

-- ADD CONSTRAINT에는 IF NOT EXISTS가 없다. DROP IF EXISTS로 재실행 안전하게 만든다.
ALTER TABLE sellup.apilot_config_store DROP CONSTRAINT IF EXISTS ck_acs_mode;
ALTER TABLE sellup.apilot_config_store DROP CONSTRAINT IF EXISTS ck_acs_params_obj;

ALTER TABLE sellup.apilot_config_store
  ADD CONSTRAINT ck_acs_mode       CHECK (apilot_mode IN ('V1','SHADOW','V2')),
  ADD CONSTRAINT ck_acs_params_obj CHECK (jsonb_typeof(v2_params_json) = 'object');

COMMENT ON COLUMN sellup.apilot_config_store.apilot_mode
  IS 'V1 | SHADOW | V2. 배치의 대상 매장 필터 (sellup-v2 5.1.2)';
COMMENT ON COLUMN sellup.apilot_config_store.guardrail_paused_until
  IS '이 시각까지 자동 캠페인 생성을 멈춘다 (sellup-v2 9.5.3)';
COMMENT ON COLUMN sellup.apilot_config_store.v2_params_json
  IS 'V2 파라미터 20개. 없는 키는 apilot_config_system에서 읽는다. 포맷은 sellup-v2 8.9';

COMMIT;

-- 1.4 기존 테이블 시드 — sellup.apilot_config_system
BEGIN;

INSERT INTO sellup.apilot_config_system (config_key, config_value_json)
VALUES
  ('message_unit_cost_kakao',
   '{"value": 30.00, "unit": "KRW/건", "source": "사용자 확정 2026-09-29 (고정값)",
     "updated_at": "2026-09-29", "note": "발송비는 회사 부담. 내부 비용 계산용, 결정 제약 아님"}'::jsonb),
  ('message_unit_cost_sms',
   '{"value": 30.00, "unit": "KRW/건", "source": "사용자 확정 2026-09-29 (고정값)",
     "updated_at": "2026-09-29", "note": "카카오와 동일 30원 고정"}'::jsonb),
  ('holdout_pct',              '{"value": 10}'::jsonb),
  ('global_holdout_pct',       '{"value": 3}'::jsonb),
  ('grace_days',               '{"value": 3}'::jsonb),
  ('min_control_users',        '{"value": 30}'::jsonb),
  ('winsor_pct',               '{"value": 0.01}'::jsonb),
  ('mde_tolerance',            '{"value": 1.5}'::jsonb),
  ('min_eligible',             '{"value": 30}'::jsonb),
  ('contribution_target_pct',  '{"value": 0.10}'::jsonb),
  ('coverage_target_pct',      '{"value": 1.67}'::jsonb),
  ('min_target_users',         '{"CONSERVATIVE": 50, "BALANCED": 30, "AGGRESSIVE": 30}'::jsonb),
  ('min_response_rate',        '{"value": 0.01}'::jsonb),
  ('exploration_rate',         '{"CONSERVATIVE": 0.10, "BALANCED": 0.20, "AGGRESSIVE": 0.30}'::jsonb),
  ('exploration_budget_rate',  '{"value": 0.10}'::jsonb),
  ('max_inflight_per_type',    '{"value": 1}'::jsonb),
  ('shrinkage_k',              '{"value": 30}'::jsonb),
  ('calibration_shrinkage_k',  '{"value": 50}'::jsonb),
  ('prior_half_life_days',     '{"value": 180}'::jsonb),
  ('customer_fatigue_days',    '{"value": 14}'::jsonb),
  ('apilot_mode',              '{"value": "V1"}'::jsonb)
ON CONFLICT (config_key) DO NOTHING;

COMMIT;

-- 1.5 기존 테이블 변경 — sellup.holdout_policy
BEGIN;
ALTER TABLE sellup.holdout_policy DROP CONSTRAINT IF EXISTS holdout_policy_int4range_excl;
-- range_to를 포함하는 닫힌 구간끼리 겹치지 않게. 인접 밴드(…29 | 30…)는 허용된다.
ALTER TABLE sellup.holdout_policy
  ADD CONSTRAINT holdout_policy_int4range_excl
  EXCLUDE USING gist (int4range(range_from, COALESCE(range_to, 2147483647), '[]') WITH &&);
COMMIT;
BEGIN;

-- 1) 기존 too_small 행(0~50)의 상한을 29로 줄인다.
--    이 밴드는 "집행하지 않는다"를 뜻한다 — 값 자체가 아니라 애플리케이션의
--    min_target_users(30) 하한이 집행을 막는다 (sellup-v2 5.5.2 N1b, 6.3.1).
UPDATE sellup.holdout_policy
   SET range_to       = 29,
       standard_level = 'no_execute',
       label          = '집행 안 함 (union 후 NONE TOO_SMALL_TARGET)',
       min_control    = 30,
       updated_at     = now()
 WHERE range_from = 0 AND range_to = 50;

-- 2) 신규 밴드 30~50 -> 0.08.
--    개별 캠페인 측정용이 아니다. 대조군 0명 퇴화 경로를 없애고
--    매장 풀링 기준선에 기여하는 것이 목적이며, 순효과는 PRIOR_BASELINE으로 판정한다.
INSERT INTO sellup.holdout_policy
       (range_from, range_to, standard_level, holdout, uplift_type, label, min_control)
SELECT 30, 50, 'small', 0.08, 'estimated', '소규모(퇴화 방지용 홀드아웃)', 30
 WHERE NOT EXISTS (SELECT 1 FROM sellup.holdout_policy WHERE range_from = 30 AND range_to = 50);

-- 3) 정책 공백 51~200 -> 0.10 (현행 코드 기본값과 동일한 값을 행으로 명시)
INSERT INTO sellup.holdout_policy
       (range_from, range_to, standard_level, holdout, uplift_type, label, min_control)
SELECT 51, 200, 'standard', 0.10, 'measured', '표준(구 코드 기본값)', 30
 WHERE NOT EXISTS (SELECT 1 FROM sellup.holdout_policy WHERE range_from = 51 AND range_to = 200);

-- 4) 정책 공백 501~1000 -> 0.10 (현행 코드 기본값과 동일한 값을 행으로 명시)
INSERT INTO sellup.holdout_policy
       (range_from, range_to, standard_level, holdout, uplift_type, label, min_control)
SELECT 501, 1000, 'standard', 0.10, 'measured', '표준(구 코드 기본값)', 30
 WHERE NOT EXISTS (SELECT 1 FROM sellup.holdout_policy WHERE range_from = 501 AND range_to = 1000);

-- 5) min_control을 전 행에 30으로 채워 실제로 적용한다.
--    현재 3행 모두 NULL이라 한 번도 적용된 적이 없다 (sellup-v2 3.5 F11).
UPDATE sellup.holdout_policy
   SET min_control = 30, updated_at = now()
 WHERE min_control IS DISTINCT FROM 30;

COMMIT;

-- 1.6 신규 테이블 — sellup.campaign_outcome
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.campaign_outcome (
    campaign_id             UUID          NOT NULL,
    version                 INTEGER       NOT NULL DEFAULT 1,
    opportunity_snapshot_id UUID          NULL,
    store_no                INTEGER       NOT NULL,
    measured_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    window_from             DATE          NOT NULL,
    window_to               DATE          NOT NULL,
    opportunity_type        TEXT          NULL,
    segment_code            TEXT          NULL,
    offer_bucket            TEXT          NULL,
    trigger_type            TEXT          NULL,
    verdict                 TEXT          NOT NULL DEFAULT 'UNCERTAIN',
    measurable              BOOLEAN       NOT NULL DEFAULT TRUE,
    -- (v1.2) 뷰를 쓸 수 없으므로 "최신 버전"을 실컬럼으로 표현한다 (§0.3)
    is_latest               BOOLEAN       NOT NULL DEFAULT TRUE,
    formula_version         TEXT          NOT NULL DEFAULT 'v2.0',
    created_at              TIMESTAMPTZ   NOT NULL DEFAULT now(),

    population_json         JSONB         NOT NULL DEFAULT '{}'::jsonb,
    sales_json              JSONB         NOT NULL DEFAULT '{}'::jsonb,
    incremental_json        JSONB         NOT NULL DEFAULT '{}'::jsonb,
    cost_json               JSONB         NOT NULL DEFAULT '{}'::jsonb,

    PRIMARY KEY (campaign_id, version),
    CONSTRAINT ck_co_verdict CHECK (verdict IN ('POSITIVE','UNCERTAIN','NEGATIVE'))
);

CREATE INDEX IF NOT EXISTS ix_co_store_window ON sellup.campaign_outcome (store_no, window_to DESC);
CREATE INDEX IF NOT EXISTS ix_co_type         ON sellup.campaign_outcome (opportunity_type, offer_bucket, segment_code, trigger_type) WHERE measurable;
CREATE INDEX IF NOT EXISTS ix_co_snapshot     ON sellup.campaign_outcome (opportunity_snapshot_id);
CREATE INDEX IF NOT EXISTS ix_co_version      ON sellup.campaign_outcome (campaign_id, version DESC);
CREATE INDEX IF NOT EXISTS ix_co_verdict      ON sellup.campaign_outcome (verdict, window_to DESC);
-- 캠페인당 "최신" 행은 하나뿐이다. 뷰 대신 이 부분 유니크 인덱스가 그것을 보장한다 (§0.3)
CREATE UNIQUE INDEX IF NOT EXISTS ux_co_latest ON sellup.campaign_outcome (campaign_id) WHERE is_latest;

COMMENT ON COLUMN sellup.campaign_outcome.is_latest
  IS '캠페인별 최신 버전. 모든 집계가 WHERE is_latest를 쓴다 (sellup-v2 8.0.1)';

alter table sellup.campaign_outcome owner to mk;
COMMIT;

-- 1.7 신규 테이블 — sellup.campaign_exposure
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.campaign_exposure (
    exposure_id      BIGSERIAL     PRIMARY KEY,
    store_no         INTEGER       NOT NULL,
    user_id          UUID          NOT NULL,
    campaign_id      UUID          NOT NULL,
    exposure_date    DATE          NOT NULL,
    channel          TEXT          NOT NULL,
    is_holdout       BOOLEAN       NOT NULL DEFAULT FALSE,
    holdout_bucket   SMALLINT      NULL,
    episode_id       UUID          NULL,
    opportunity_type TEXT          NULL,
    segment_code     TEXT          NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    meta_json        JSONB         NULL,

    CONSTRAINT ck_ce_channel CHECK (channel IN ('KAKAO','SMS','NONE')),
    CONSTRAINT ck_ce_bucket  CHECK (holdout_bucket IS NULL OR (holdout_bucket >= 0 AND holdout_bucket <= 99))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_ce_unique ON sellup.campaign_exposure (campaign_id, user_id);
CREATE INDEX IF NOT EXISTS ix_ce_user_date  ON sellup.campaign_exposure (store_no, user_id, exposure_date DESC);
CREATE INDEX IF NOT EXISTS ix_ce_episode    ON sellup.campaign_exposure (episode_id) WHERE episode_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_ce_store_date ON sellup.campaign_exposure (store_no, exposure_date DESC);
-- Phase 4 피로도 집계의 주 경로 (별도 테이블 없이 여기서 센다)
CREATE INDEX IF NOT EXISTS ix_ce_fatigue    ON sellup.campaign_exposure (store_no, user_id, exposure_date DESC)
    WHERE channel <> 'NONE';
-- append 순서가 시간순에 가까우므로 날짜 범위 조회는 BRIN으로 충분하다
CREATE INDEX IF NOT EXISTS ix_ce_date_brin  ON sellup.campaign_exposure USING BRIN (exposure_date);

COMMENT ON COLUMN sellup.campaign_exposure.channel IS 'KAKAO | SMS | NONE(대조군)';

alter table sellup.campaign_exposure owner to mk;
COMMIT;

-- 1.8 신규 테이블 — sellup.apilot_budget_ledger
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_budget_ledger (
    ledger_id      BIGSERIAL     PRIMARY KEY,
    store_no       INTEGER       NOT NULL,
    month          DATE          NOT NULL,
    campaign_id    UUID          NULL,
    snapshot_id    UUID          NULL,
    status         TEXT          NOT NULL DEFAULT 'RESERVED',
    reserved_krw   NUMERIC(16,2) NOT NULL DEFAULT 0,
    confirmed_krw  NUMERIC(16,2) NULL,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now(),

    amounts_json   JSONB         NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT ck_abl_status CHECK (status IN ('RESERVED','CONFIRMED','RELEASED'))
);

CREATE INDEX IF NOT EXISTS ix_abl_store_month ON sellup.apilot_budget_ledger (store_no, month, status);
CREATE UNIQUE INDEX IF NOT EXISTS ux_abl_campaign ON sellup.apilot_budget_ledger (campaign_id)
    WHERE campaign_id IS NOT NULL;

COMMENT ON COLUMN sellup.apilot_budget_ledger.month          IS '해당 월 1일로 정규화';
COMMENT ON COLUMN sellup.apilot_budget_ledger.reserved_krw   IS '예약 총액 = 할인 + 발송비. 내역은 amounts_json';
COMMENT ON COLUMN sellup.apilot_budget_ledger.confirmed_krw  IS 'OUTCOME 스텝이 채우는 실측 총액';

alter table sellup.apilot_budget_ledger owner to mk;
COMMIT;

-- 1.9 신규 테이블 — sellup.store_month_contribution
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.store_month_contribution (
    store_no          INTEGER       NOT NULL,
    month             DATE          NOT NULL,
    contribution_rate NUMERIC(6,5)  NOT NULL,   -- 정본 C_fee = ai_sales_fee_basis / total_sales
    is_rampup         BOOLEAN       NOT NULL DEFAULT FALSE,
    net_basis         TEXT          NULL,
    formula_version   TEXT          NOT NULL DEFAULT 'v2.0',
    computed_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    measures_json     JSONB         NOT NULL DEFAULT '{}'::jsonb,

    PRIMARY KEY (store_no, month),
    CONSTRAINT ck_smc_basis CHECK (net_basis IS NULL OR net_basis IN ('MEASURED','PRIOR_BASELINE','NONE'))
);

CREATE INDEX IF NOT EXISTS ix_smc_month ON sellup.store_month_contribution (month, contribution_rate)
    WHERE NOT is_rampup;
-- C_net 괴리 매장 조회는 월 1회 배치이므로 표현식 인덱스로 충분하다
CREATE INDEX IF NOT EXISTS ix_smc_net ON sellup.store_month_contribution
    (month, ((measures_json->>'contribution_rate_net')::numeric));

COMMENT ON COLUMN sellup.store_month_contribution.month
  IS '해당 월 1일 (KST). 주문은 주문일이 속한 달에 귀속된다 (sellup-v2 8.10)';
COMMENT ON COLUMN sellup.store_month_contribution.contribution_rate
  IS '정본 C_fee = ai_sales_fee_basis / total_sales (캠페인 + 비캠페인 CRM). 점주 노출 유일 지표';

alter table sellup.store_month_contribution owner to mk;
COMMIT;

-- 2.1 sellup.apilot_opportunity_registry
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_opportunity_registry (
    registry_id      BIGSERIAL     PRIMARY KEY,
    node_key         TEXT          NOT NULL,
    opportunity_type TEXT          NOT NULL,
    trigger_type     TEXT          NOT NULL DEFAULT 'KPI',
    is_active        BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    candidate_json   JSONB         NOT NULL,
    offer_json       JSONB         NOT NULL,
    prior_json       JSONB         NULL,
    meta_json        JSONB         NULL,

    CONSTRAINT ck_aor_trigger CHECK (trigger_type IN ('KPI','CUSTOMER'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_aor_type_node
  ON sellup.apilot_opportunity_registry (opportunity_type, node_key);
CREATE INDEX IF NOT EXISTS ix_aor_node_active
  ON sellup.apilot_opportunity_registry (node_key) WHERE is_active;
-- V1 카테고리 매핑은 Shadow 비교에서만 쓰므로 표현식 인덱스로 충분하다
CREATE INDEX IF NOT EXISTS ix_aor_v1_category
  ON sellup.apilot_opportunity_registry ((meta_json->>'v1_category'))
  WHERE meta_json ? 'v1_category';

COMMENT ON COLUMN sellup.apilot_opportunity_registry.candidate_json IS '세그먼트 후보와 union 규칙';
COMMENT ON COLUMN sellup.apilot_opportunity_registry.offer_json     IS '오퍼 범위와 버킷 목록';
COMMENT ON COLUMN sellup.apilot_opportunity_registry.prior_json     IS '콜드스타트 시드와 정규화 기준';
COMMENT ON COLUMN sellup.apilot_opportunity_registry.meta_json      IS '표시명, V1 매핑, UI 메타';
alter table sellup.apilot_opportunity_registry owner to mk;
COMMIT;

-- 2.2 sellup.apilot_opportunity_snapshot
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_opportunity_snapshot (
    snapshot_id            UUID          NOT NULL DEFAULT gen_random_uuid(),
    store_no               INTEGER       NOT NULL,
    snapshot_date          DATE          NOT NULL,
    trigger_type           TEXT          NOT NULL,
    opportunity_type       TEXT          NOT NULL,
    segment_code           TEXT          NOT NULL,
    offer_bucket           TEXT          NOT NULL,
    decision_path          TEXT          NOT NULL DEFAULT 'NONE',
    recommended_action     TEXT          NOT NULL,
    mode                   TEXT          NOT NULL DEFAULT 'SHADOW',
    formula_version        TEXT          NOT NULL DEFAULT 'v2.0',
    created_at             TIMESTAMPTZ   NOT NULL DEFAULT now(),
    supersedes_snapshot_id UUID          NULL REFERENCES sellup.apilot_opportunity_snapshot(snapshot_id),
    is_current             BOOLEAN       NOT NULL DEFAULT TRUE,
    superseded_at          TIMESTAMPTZ   NULL,
    final_action           TEXT          NULL,
    actual_campaign_id     UUID          NULL,
    settled_at             TIMESTAMPTZ   NULL,

    inputs_json            JSONB         NOT NULL DEFAULT '{}'::jsonb,
    estimate_json          JSONB         NOT NULL DEFAULT '{}'::jsonb,
    actual_json            JSONB         NULL,
    trace_json             JSONB         NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT ck_aos_action   CHECK (recommended_action IN ('NONE','COUPON','POINT','MESSAGE')),
    CONSTRAINT ck_aos_trigger  CHECK (trigger_type IN ('KPI','CUSTOMER','NONE_DETECTED')),
    CONSTRAINT ck_aos_mode     CHECK (mode IN ('V1','SHADOW','V2')),
    CONSTRAINT ck_aos_final    CHECK (final_action IS NULL OR final_action IN ('EXECUTED','NONE','PENDING')),
    CONSTRAINT ck_aos_path     CHECK (decision_path IN ('NORMAL','EXPLORE','NONE')),
    -- POINT는 스키마에만 예약. Action Selector는 반환하지 않는다
    CONSTRAINT ck_aos_no_point CHECK (recommended_action <> 'POINT'),
    -- 단일 컬럼 PK. outcome/campaign이 snapshot_id 하나로 FK를 걸 수 있어야 한다
    PRIMARY KEY (snapshot_id)
);

-- append-only이므로 전체 유니크를 걸지 않고 "현재 행"만 유일하게 한다.
-- trigger_type과 segment_code를 키에 포함한다 (sellup-v2 8.2.1, 8.2)
CREATE UNIQUE INDEX IF NOT EXISTS ux_aos_current
  ON sellup.apilot_opportunity_snapshot
     (store_no, snapshot_date, trigger_type, opportunity_type, segment_code, offer_bucket)
  WHERE is_current;

CREATE INDEX IF NOT EXISTS ix_aos_date_brin  ON sellup.apilot_opportunity_snapshot USING BRIN (snapshot_date);
CREATE INDEX IF NOT EXISTS ix_aos_store_date ON sellup.apilot_opportunity_snapshot (store_no, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS ix_aos_campaign   ON sellup.apilot_opportunity_snapshot (actual_campaign_id)
  WHERE actual_campaign_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_aos_type_date  ON sellup.apilot_opportunity_snapshot (opportunity_type, offer_bucket, snapshot_date DESC);
CREATE INDEX IF NOT EXISTS ix_aos_supersedes ON sellup.apilot_opportunity_snapshot (supersedes_snapshot_id)
  WHERE supersedes_snapshot_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS ix_aos_unsettled  ON sellup.apilot_opportunity_snapshot (actual_campaign_id)
  WHERE actual_campaign_id IS NOT NULL AND settled_at IS NULL;
-- gap 충족 순서로 뽑는 주 경로. ranked_value는 JSONB 안이므로 표현식 인덱스
CREATE INDEX IF NOT EXISTS ix_aos_ranked     ON sellup.apilot_opportunity_snapshot
  (snapshot_date, ((estimate_json->>'ranked_value')::numeric) DESC) WHERE is_current;
-- 선택된 행만 세는 경로
CREATE INDEX IF NOT EXISTS ix_aos_selected   ON sellup.apilot_opportunity_snapshot
  (snapshot_date) WHERE is_current AND (estimate_json->>'is_selected')::boolean;

COMMENT ON COLUMN sellup.apilot_opportunity_snapshot.segment_code
  IS 'union이면 UNION:{a}+{b} 형식';
COMMENT ON COLUMN sellup.apilot_opportunity_snapshot.formula_version
  IS 'JSONB 스키마 버전. 필드 추가는 마이그레이션 없이 이 값만 올린다 (sellup-v2 8.0)';

-- 소유자 변경 (조회 계정 mk가 소유자가 되도록, 사용자 운영 방식)
ALTER TABLE sellup.apilot_opportunity_snapshot OWNER TO mk;

COMMIT;

-- 2.3 2.3 sellup.apilot_customer_episode
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_customer_episode (
    episode_id       UUID          PRIMARY KEY DEFAULT gen_random_uuid(),
    store_no         INTEGER       NOT NULL,
    user_id          UUID          NOT NULL,
    opportunity_type TEXT          NOT NULL,
    started_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    last_eligible_at DATE          NOT NULL,
    ended_at         TIMESTAMPTZ   NULL,
    exit_reason      TEXT          NULL,
    assigned_arm     TEXT          NULL,
    holdout_bucket   SMALLINT      NULL,
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    CONSTRAINT ck_ace_arm  CHECK (assigned_arm IS NULL OR assigned_arm IN ('TREATED','CONTROL')),
    CONSTRAINT ck_ace_exit CHECK (exit_reason IS NULL
        OR exit_reason IN ('CONVERTED','INELIGIBLE_30D','TYPE_MOVED','GHOST_ROTATION'))
);

-- 고객·유형당 진행 중 episode는 하나뿐
CREATE UNIQUE INDEX IF NOT EXISTS ux_ace_open ON sellup.apilot_customer_episode
  (store_no, user_id, opportunity_type) WHERE ended_at IS NULL;
CREATE INDEX IF NOT EXISTS ix_ace_store_type ON sellup.apilot_customer_episode (store_no, opportunity_type, started_at DESC);
CREATE INDEX IF NOT EXISTS ix_ace_user       ON sellup.apilot_customer_episode (store_no, user_id);
-- 이탈 판정 배치의 주 경로
CREATE INDEX IF NOT EXISTS ix_ace_stale      ON sellup.apilot_customer_episode (last_eligible_at) WHERE ended_at IS NULL;

COMMENT ON COLUMN sellup.apilot_customer_episode.last_eligible_at
  IS '마지막으로 eligible이었던 날. 30일 연속 비eligible을 이 한 컬럼으로 판정한다';
COMMENT ON COLUMN sellup.apilot_customer_episode.assigned_arm
  IS '진입 시 확정, 불변. 월 경계를 넘어도 바뀌지 않는다 (sellup-v2 6.1.2)';

-- 소유자 변경 (조회 계정 mk가 소유자가 되도록, 사용자 운영 방식)
ALTER TABLE sellup.apilot_customer_episode OWNER TO mk;

COMMIT;

-- 2.4 미뤘던 FK — campaign_exposure.episode_id
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'sellup' AND t.relname = 'campaign_exposure'
      AND c.conname = 'fk_exposure_episode'
  ) THEN
    ALTER TABLE sellup.campaign_exposure
      ADD CONSTRAINT fk_exposure_episode
      FOREIGN KEY (episode_id)
      REFERENCES sellup.apilot_customer_episode(episode_id)
      NOT VALID;
  END IF;
END $$;

ALTER TABLE sellup.campaign_exposure VALIDATE CONSTRAINT fk_exposure_episode;

COMMIT;

-- 2.5 미뤘던 FK — campaign_outcome.opportunity_snapshot_id
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'sellup' AND t.relname = 'campaign_outcome'
      AND c.conname = 'fk_co_snapshot'
  ) THEN
    ALTER TABLE sellup.campaign_outcome
      ADD CONSTRAINT fk_co_snapshot
      FOREIGN KEY (opportunity_snapshot_id)
      REFERENCES sellup.apilot_opportunity_snapshot(snapshot_id)
      NOT VALID;
  END IF;
END $$;

ALTER TABLE sellup.campaign_outcome VALIDATE CONSTRAINT fk_co_snapshot;

COMMIT;

-- 2.6 선택 — 불변 계약 트리거 aos_guard
BEGIN;

CREATE OR REPLACE FUNCTION sellup.aos_guard() RETURNS trigger AS $$
BEGIN
  IF NEW.inputs_json IS DISTINCT FROM OLD.inputs_json
     OR NEW.estimate_json IS DISTINCT FROM OLD.estimate_json THEN
    RAISE EXCEPTION 'snapshot decision values are immutable (sellup-v2 8.2.2)';
  END IF;
  RETURN NEW;
END $$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS tg_aos_guard ON sellup.apilot_opportunity_snapshot;
CREATE TRIGGER tg_aos_guard BEFORE UPDATE ON sellup.apilot_opportunity_snapshot
  FOR EACH ROW EXECUTE FUNCTION sellup.aos_guard();

COMMIT;

-- 3.1 campaign.opportunity_snapshot_id FK
BEGIN;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint c
    JOIN pg_class t ON t.oid = c.conrelid
    JOIN pg_namespace n ON n.oid = t.relnamespace
    WHERE n.nspname = 'sellup' AND t.relname = 'campaign'
      AND c.conname = 'fk_campaign_snapshot'
  ) THEN
    ALTER TABLE sellup.campaign
      ADD CONSTRAINT fk_campaign_snapshot
      FOREIGN KEY (opportunity_snapshot_id)
      REFERENCES sellup.apilot_opportunity_snapshot(snapshot_id)
      NOT VALID;
  END IF;
END $$;

ALTER TABLE sellup.campaign VALIDATE CONSTRAINT fk_campaign_snapshot;

COMMIT;

-- 3.2 campaign.status = 'paused' — DDL 없음
-- campaign.status는 Text 컬럼이므로 값 추가에 DDL이 필요하지 않다(app/models/campaign.py). 상수 정의와 문서만 고치면 된다. 가드레일 발동 시 ready 캠페인을 paused로 전환해 SEND를 멈춘다(§9.5.3).
-- 확인만: 이 값을 읽는 다른 코드·화면이 있는지 미확인이다 (sellup-v2 14 A25)
SELECT status, count(*) FROM sellup.campaign GROUP BY status ORDER BY 2 DESC;

-- 4.1 sellup.apilot_uplift_prior
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_uplift_prior (
    prior_id         BIGSERIAL     PRIMARY KEY,
    scope            TEXT          NOT NULL,
    scope_id         TEXT          NOT NULL,
    opportunity_type TEXT          NOT NULL,
    offer_bucket     TEXT          NOT NULL,
    segment_code     TEXT          NOT NULL,
    trigger_type     TEXT          NOT NULL,
    send_slot        TEXT          NOT NULL DEFAULT 'DEFAULT',
    formula_version  TEXT          NOT NULL DEFAULT 'v2.0',
    recomputed_at    TIMESTAMPTZ   NOT NULL DEFAULT now(),
    updated_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),
    created_at       TIMESTAMPTZ   NOT NULL DEFAULT now(),

    stats_json       JSONB         NOT NULL DEFAULT '{}'::jsonb,

    CONSTRAINT ck_aup_scope   CHECK (scope IN ('store','category','global')),
    CONSTRAINT ck_aup_trigger CHECK (trigger_type IN ('KPI','CUSTOMER'))
);

CREATE UNIQUE INDEX IF NOT EXISTS ux_aup_key ON sellup.apilot_uplift_prior
  (scope, scope_id, opportunity_type, offer_bucket, segment_code, trigger_type, send_slot);
CREATE INDEX IF NOT EXISTS ix_aup_lookup ON sellup.apilot_uplift_prior (opportunity_type, trigger_type, scope);

COMMENT ON COLUMN sellup.apilot_uplift_prior.scope_id      IS 'store_no | category_code | ''*''';
COMMENT ON COLUMN sellup.apilot_uplift_prior.recomputed_at IS '전량 재계산 시각. 매일 갱신된다';
COMMENT ON COLUMN sellup.apilot_uplift_prior.updated_at    IS '값이 실제로 바뀐 시각';

-- 소유자 변경 (조회 계정 mk가 소유자가 되도록, 사용자 운영 방식)
ALTER TABLE sellup.apilot_uplift_prior OWNER TO mk;

COMMIT;

-- 4.2 sellup.apilot_uplift_prior_history
BEGIN;

CREATE TABLE IF NOT EXISTS sellup.apilot_uplift_prior_history (
    history_id      BIGSERIAL     PRIMARY KEY,
    prior_id        BIGINT        NOT NULL REFERENCES sellup.apilot_uplift_prior(prior_id),
    changed_at      TIMESTAMPTZ   NOT NULL DEFAULT now(),
    batch_id        UUID          NULL,
    formula_version TEXT          NOT NULL,

    before_json     JSONB         NOT NULL,
    after_json      JSONB         NOT NULL,
    source_json     JSONB         NOT NULL
);

CREATE INDEX IF NOT EXISTS ix_auph_prior ON sellup.apilot_uplift_prior_history (prior_id, changed_at DESC);
CREATE INDEX IF NOT EXISTS ix_auph_batch ON sellup.apilot_uplift_prior_history (batch_id);

COMMENT ON TABLE sellup.apilot_uplift_prior_history
  IS '전량 재계산 후 값이 달라진 키에만 1행. 보존 무기한 (sellup-v2 8.5)';

-- 소유자 변경 (조회 계정 mk가 소유자가 되도록, 사용자 운영 방식)
ALTER TABLE sellup.apilot_uplift_prior_history OWNER TO mk;

COMMIT;

-- 8. 적용 후 검증 쿼리
-- 8.1 테이블 9개가 있는가
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'sellup'
  AND table_name IN ('apilot_opportunity_registry','apilot_opportunity_snapshot','campaign_outcome',
                     'apilot_uplift_prior','apilot_uplift_prior_history','campaign_exposure',
                     'apilot_customer_episode','apilot_budget_ledger','store_month_contribution')
ORDER BY table_name;
select * from sellup.v_kpi_unidentified_sales;
-- view: v_kpi_unidentified_sales
-- 8.2 뷰가 없는가 (zero-ETL 규칙)
SELECT table_name FROM information_schema.views
WHERE table_schema = 'sellup';
-- "최신 버전" 보장이 부분 유니크 인덱스로 대체됐는지 확인한다
SELECT indexdef FROM pg_indexes
WHERE schemaname = 'sellup' AND indexname = 'ux_co_latest';
-- 8.3 실컬럼 수가 §8과 일치하는가
SELECT c.relname AS table_name,
       count(*) FILTER (WHERE a.atttypid <> 'jsonb'::regtype) AS real_cols,
       count(*) FILTER (WHERE a.atttypid  = 'jsonb'::regtype) AS jsonb_cols
FROM pg_class c
JOIN pg_namespace n ON n.oid = c.relnamespace
JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0 AND NOT a.attisdropped
WHERE n.nspname = 'sellup' AND c.relkind = 'r'
  AND c.relname IN ('apilot_opportunity_registry','apilot_opportunity_snapshot','campaign_outcome',
                    'apilot_uplift_prior','apilot_uplift_prior_history','campaign_exposure',
                    'apilot_customer_episode','apilot_budget_ledger','store_month_contribution')
GROUP BY c.relname
ORDER BY c.relname;
table_name,real_cols,jsonb_cols
apilot_budget_ledger,10,1
apilot_customer_episode,11,0
apilot_opportunity_registry,7,4
apilot_opportunity_snapshot,18,4
apilot_uplift_prior,12,1
apilot_uplift_prior_history,5,3
campaign_exposure,12,1
campaign_outcome,16,4
store_month_contribution,7,1

-- 8.4 인덱스가 다 있는가
BEGIN;
DROP VIEW IF EXISTS sellup.campaign_outcome_latest;
ALTER TABLE sellup.campaign_outcome ADD COLUMN IF NOT EXISTS is_latest BOOLEAN NOT NULL DEFAULT TRUE;
CREATE INDEX IF NOT EXISTS ix_co_version ON sellup.campaign_outcome (campaign_id, version DESC);
CREATE UNIQUE INDEX IF NOT EXISTS ux_co_latest ON sellup.campaign_outcome (campaign_id) WHERE is_latest;
CREATE INDEX IF NOT EXISTS ix_cu_excluded ON sellup.campaign_user (campaign_id, exclude_reason) WHERE exclude_reason IS NOT NULL;
COMMIT;

-- 41행 나오면 된다.
SELECT tablename, indexname
FROM pg_indexes
WHERE schemaname = 'sellup'
  AND indexname IN ('ix_abl_store_month', 'ix_ace_stale', 'ix_ace_store_type', 'ix_ace_user', 'ix_aor_node_active',
                    'ix_aor_v1_category', 'ix_aos_campaign', 'ix_aos_date_brin', 'ix_aos_ranked', 'ix_aos_selected',
                    'ix_aos_store_date', 'ix_aos_supersedes', 'ix_aos_type_date', 'ix_aos_unsettled', 'ix_aup_lookup',
                    'ix_auph_batch', 'ix_auph_prior', 'ix_campaign_inflight', 'ix_campaign_opp', 'ix_ce_date_brin',
                    'ix_ce_episode', 'ix_ce_fatigue', 'ix_ce_store_date', 'ix_ce_user_date', 'ix_co_snapshot',
                    'ix_co_store_window', 'ix_co_type', 'ix_co_verdict', 'ix_co_version', 'ix_cu_campaign_holdout',
                    'ix_cu_campaign_status', 'ix_cu_excluded', 'ix_smc_month', 'ix_smc_net', 'ux_abl_campaign',
                    'ux_ace_open', 'ux_aor_type_node', 'ux_aos_current', 'ux_aup_key', 'ux_ce_unique',
                    'ux_co_latest')
ORDER BY tablename, indexname;
SELECT column_name FROM information_schema.columns
 WHERE table_schema='sellup' AND table_name='campaign_outcome' AND column_name='is_latest';   -- 1행이어야 함
SELECT table_name FROM information_schema.views WHERE table_schema='sellup';                   -- 0행이어야 함
SELECT conname FROM pg_constraint WHERE conname IN ('ck_cu_exclude_reason','ck_cu_bucket');  -- 2행이어야 함

-- 마지막 한꺼번에 검증 , 모두 OK 나오면 된다.
SELECT '8.1 신규 테이블 9'       AS chk, CASE WHEN count(*)=9 THEN 'OK' ELSE 'FAIL '||count(*) END AS result
FROM pg_tables WHERE schemaname='sellup' AND tablename IN ('campaign_outcome','campaign_exposure','apilot_budget_ledger','store_month_contribution','apilot_opportunity_registry','apilot_opportunity_snapshot','apilot_customer_episode','apilot_uplift_prior','apilot_uplift_prior_history')
UNION ALL
SELECT '8.12 소유자 mk 9', CASE WHEN count(*)=9 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM pg_tables WHERE schemaname='sellup' AND tableowner='mk' AND tablename IN ('campaign_outcome','campaign_exposure','apilot_budget_ledger','store_month_contribution','apilot_opportunity_registry','apilot_opportunity_snapshot','apilot_customer_episode','apilot_uplift_prior','apilot_uplift_prior_history')
UNION ALL
SELECT '8.5 ux_aos_current에 segment_code', CASE WHEN indexdef LIKE '%segment_code%' AND indexdef LIKE '%WHERE%is_current%' THEN 'OK' ELSE 'FAIL' END
FROM pg_indexes WHERE schemaname='sellup' AND indexname='ux_aos_current'
UNION ALL
SELECT '8.6 BRIN 2개', CASE WHEN count(*)=2 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM pg_indexes WHERE schemaname='sellup' AND indexname IN ('ix_aos_date_brin','ix_ce_date_brin') AND indexdef ILIKE '%USING brin%'
UNION ALL
SELECT '8.7 holdout_policy 6행', CASE WHEN count(*)=6 AND bool_and(min_control=30) THEN 'OK' ELSE 'FAIL '||count(*) END
FROM sellup.holdout_policy
UNION ALL
SELECT '8.7 밴드 연속(틈 없음)', CASE WHEN bool_and(gap=1) THEN 'OK' ELSE 'FAIL' END
FROM (SELECT lead(range_from) OVER (ORDER BY range_from) - range_to AS gap FROM sellup.holdout_policy) g WHERE gap IS NOT NULL
UNION ALL
SELECT '8.8 config_system V2 키 21', CASE WHEN count(*)=21 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM sellup.apilot_config_system WHERE config_key IN ('message_unit_cost_kakao','message_unit_cost_sms','holdout_pct','global_holdout_pct','grace_days','min_control_users','winsor_pct','mde_tolerance','min_eligible','contribution_target_pct','coverage_target_pct','min_target_users','min_response_rate','exploration_rate','exploration_budget_rate','max_inflight_per_type','shrinkage_k','calibration_shrinkage_k','prior_half_life_days','customer_fatigue_days','apilot_mode')
UNION ALL
SELECT '8.8 메시지 단가 30', CASE WHEN bool_and((config_value_json->>'value')::numeric=30) THEN 'OK' ELSE 'FAIL' END
FROM sellup.apilot_config_system WHERE config_key IN ('message_unit_cost_kakao','message_unit_cost_sms')
UNION ALL
SELECT '8.9 config_store 신규 4컬럼', CASE WHEN count(*)=4 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM information_schema.columns WHERE table_schema='sellup' AND table_name='apilot_config_store' AND column_name IN ('apilot_mode','guardrail_paused_until','enable_customer_trigger','v2_params_json')
UNION ALL
SELECT '1.1 campaign 신규 3컬럼', CASE WHEN count(*)=3 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM information_schema.columns WHERE table_schema='sellup' AND table_name='campaign' AND column_name IN ('opportunity_snapshot_id','is_measurement','v2_json')
UNION ALL
SELECT '1.2 campaign_user 신규 2컬럼', CASE WHEN count(*)=2 THEN 'OK' ELSE 'FAIL '||count(*) END
FROM information_schema.columns WHERE table_schema='sellup' AND table_name='campaign_user' AND column_name IN ('exclude_reason','holdout_bucket')
UNION ALL
SELECT '8.10 FK 3건 validated', CASE WHEN count(*)=3 AND bool_and(convalidated) THEN 'OK' ELSE 'FAIL '||count(*) END
FROM pg_constraint WHERE conname IN ('fk_exposure_episode','fk_co_snapshot','fk_campaign_snapshot');

chk,result
8.1 신규 테이블 9,OK
8.12 소유자 mk 9,OK
8.5 ux_aos_current에 segment_code,OK
8.6 BRIN 2개,OK
8.7 holdout_policy 6행,OK
8.7 밴드 연속(틈 없음),OK
8.8 config_system V2 키 21,OK
8.8 메시지 단가 30,OK
8.9 config_store 신규 4컬럼,OK
1.1 campaign 신규 3컬럼,OK
1.2 campaign_user 신규 2컬럼,OK
8.10 FK 3건 validated,OK

BEGIN;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."ai_bridge_daemon" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_config_store" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_config_system" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_flow_edge" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_node_cooldown" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_node_registry" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_run" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_run_decision" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."apilot_run_node" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."autopilot_jobs" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."briefing_log" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."briefing_policy" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."briefing_setting" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."report_jobs" TO mk;
GRANT SELECT, INSERT, UPDATE, DELETE ON sellup."reports" TO mk;
-- 앞으로 mkadmin 이 만드는 sellup 객체에도 자동 부여
ALTER DEFAULT PRIVILEGES FOR ROLE mkadmin IN SCHEMA sellup GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO mk;
ALTER DEFAULT PRIVILEGES FOR ROLE mkadmin IN SCHEMA sellup GRANT USAGE, SELECT ON SEQUENCES TO mk;
-- 확인: 0 이어야 한다
-- SELECT count(*) AS tables_without_write FROM information_schema.tables t
--  WHERE t.table_schema='sellup' AND t.table_type='BASE TABLE' AND NOT has_table_privilege('mk', format('sellup.%I', t.table_name), 'INSERT');
COMMIT;

BEGIN;

INSERT INTO sellup.apilot_opportunity_registry
    (node_key, opportunity_type, trigger_type, is_active,
     candidate_json, offer_json, prior_json, meta_json)
VALUES
-- ---------------------------------------------------------------------
-- 1) NEW_TO_SECOND — 신규→2차방문 (재방문율, v1_category=retention)
-- ---------------------------------------------------------------------
(
    'sales.orders.retention.revisit_rate',
    'NEW_TO_SECOND',
    'KPI',
    TRUE,
    '{"segment_codes": [
        {"code": "NEW_7_21", "priority": 1, "rule": [
            {"field": "orders_90d", "op": "=", "value": 1},
            {"field": "days_since_last_visit", "op": "between", "value": [7, 21]}]},
        {"code": "NEW_7_30", "priority": 2, "rule": [
            {"field": "orders_90d", "op": "=", "value": 1},
            {"field": "days_since_last_visit", "op": "between", "value": [7, 30]}]}],
      "union_allowed": true,
      "min_eligible_override": null,
      "always_evaluate": true}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.70,
      "seed": {"r_trt": 0.240, "r_ctrl": 0.080,
               "avg_aov": 28000, "avg_discount": 1680}}'::jsonb,
    '{"name_ko": "신규→2차방문", "v1_category": "retention",
      "ui": {"icon": "user-plus", "color": "#2563eb"}}'::jsonb
),
-- ---------------------------------------------------------------------
-- 2) MID_CHURN_WINBACK — 중기이탈복귀 (고위험군 비율, v1_category=churn)
-- ---------------------------------------------------------------------
(
    'sales.orders.churn.high_risk_ratio',
    'MID_CHURN_WINBACK',
    'KPI',
    TRUE,
    '{"segment_codes": [
        {"code": "MID_CHURN_30D", "priority": 1, "rule": [
            {"field": "days_since_last_visit", "op": "between", "value": [30, 59]},
            {"field": "orders_30d", "op": "<=", "value": 1}]},
        {"code": "MID_CHURN_60D", "priority": 2, "rule": [
            {"field": "days_since_last_visit", "op": "between", "value": [60, 89]},
            {"field": "orders_30d", "op": "<=", "value": 1}]}],
      "union_allowed": true,
      "min_eligible_override": null,
      "always_evaluate": true}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.60,
      "seed": {"r_trt": 0.115, "r_ctrl": 0.082,
               "avg_aov": 29000, "avg_discount": 1740}}'::jsonb,
    '{"name_ko": "중기이탈복귀", "v1_category": "churn",
      "ui": {"icon": "clock", "color": "#c2410c"}}'::jsonb
),
-- ---------------------------------------------------------------------
-- 3) DORMANT_WINBACK — 휴면복귀 (평균 재방문간격, v1_category=retention)
--    node_key 를 `revisit_interval`(category_keys={retention}) 로 잡았기
--    때문에 `churn` 이 아니라 `retention` 이다(§5.1, Q-A).
-- ---------------------------------------------------------------------
(
    'sales.orders.retention.revisit_interval',
    'DORMANT_WINBACK',
    'KPI',
    TRUE,
    '{"segment_codes": [
        {"code": "DORMANT_90_180", "priority": 1, "rule": [
            {"field": "days_since_last_visit", "op": "between", "value": [90, 180]},
            {"field": "orders_30d", "op": "=", "value": 0}]},
        {"code": "DORMANT_181P", "priority": 2, "rule": [
            {"field": "days_since_last_visit", "op": ">=", "value": 181},
            {"field": "orders_30d", "op": "=", "value": 0}]}],
      "union_allowed": true,
      "min_eligible_override": null,
      "always_evaluate": true}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.40,
      "seed": {"r_trt": 0.050, "r_ctrl": 0.030,
               "avg_aov": 30000, "avg_discount": 1800}}'::jsonb,
    '{"name_ko": "휴면복귀", "v1_category": "retention",
      "ui": {"icon": "moon", "color": "#7c3aed"}}'::jsonb
),
-- ---------------------------------------------------------------------
-- 4) VIP_REACTIVATION — VIP재방문 (VIP 재방문율 30일, v1_category=abc)
--    `union_allowed=false` — 두 세그먼트가 서로 다른 정의라 겹친다(실사 §8.1).
--    `min_eligible_override=15` — N2 에만(Q-J).
-- ---------------------------------------------------------------------
(
    'sales.orders.retention.revisit_rate_vip',
    'VIP_REACTIVATION',
    'KPI',
    TRUE,
    '{"segment_codes": [
        {"code": "VIP_RFM80_14_89", "priority": 1, "rule": [
            {"field": "rfm_percentile", "op": ">=", "value": 80},
            {"field": "days_since_last_visit", "op": "between", "value": [14, 89]}]},
        {"code": "VIP_LEVEL_14_89", "priority": 2, "rule": [
            {"field": "vip_level_90d", "op": "=", "value": "VIP"},
            {"field": "days_since_last_visit", "op": "between", "value": [14, 89]}]}],
      "union_allowed": false,
      "min_eligible_override": 15,
      "always_evaluate": true}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.50,
      "seed": {"r_trt": 0.400, "r_ctrl": 0.080,
               "avg_aov": 76000, "avg_discount": 4560}}'::jsonb,
    '{"name_ko": "VIP재방문", "v1_category": "abc",
      "ui": {"icon": "crown", "color": "#b45309"}}'::jsonb
),
-- ---------------------------------------------------------------------
-- 5) LOW_AOV_UPLIFT — 저가치개선 (1인당 매출, v1_category=aov)
--    `name_ko` 가 "저AOV개선" 이 아닌 이유: rule 이 `revenue_cum_share_30d`
--    (매출 누적 기여 하위)여서 AOV 가 아니라 **가치 기준**이다(§5.5, A35).
--    세그먼트 1개 — `LOW_VALUE_ABC_C` 는 같은 집합이라 제거(§5.2.1).
-- ---------------------------------------------------------------------
(
    'sales.aov.per_capita',
    'LOW_AOV_UPLIFT',
    'KPI',
    TRUE,
    '{"segment_codes": [
        {"code": "LOW_VALUE_TAIL_30D", "priority": 1, "rule": [
            {"field": "orders_30d", "op": ">=", "value": 1},
            {"field": "revenue_cum_share_30d", "op": ">", "value": 0.95}]}],
      "union_allowed": false,
      "min_eligible_override": 15,
      "always_evaluate": true}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.45,
      "seed": {"r_trt": 0.080, "r_ctrl": 0.050,
               "avg_aov": 25000, "avg_discount": 1500}}'::jsonb,
    '{"name_ko": "저가치개선", "v1_category": "aov",
      "ui": {"icon": "trending-up", "color": "#0f766e"}}'::jsonb
)
ON CONFLICT (opportunity_type, node_key) DO UPDATE SET
    trigger_type   = EXCLUDED.trigger_type,
    is_active      = EXCLUDED.is_active,
    candidate_json = EXCLUDED.candidate_json,
    offer_json     = EXCLUDED.offer_json,
    prior_json     = EXCLUDED.prior_json,
    meta_json      = EXCLUDED.meta_json,
    updated_at     = now();

COMMIT;

BEGIN;

INSERT INTO sellup.apilot_opportunity_registry
    (node_key, opportunity_type, trigger_type, is_active,
     candidate_json, offer_json, prior_json, meta_json)
VALUES
-- ---------------------------------------------------------------------
-- 1) CUST_MID_CHURN — 고객 단위 중기 이탈 징후
-- ---------------------------------------------------------------------
(
    'sales.orders.churn.high_risk_ratio',
    'CUST_MID_CHURN',
    'CUSTOMER',
    FALSE,
    '{"segment_codes": [
        {"code": "CUST_MID_30_59", "priority": 1, "rule": [
            {"field": "days_since_last_visit", "op": "BETWEEN", "value": [30, 59]},
            {"field": "orders_30d", "op": "<=", "value": 1}]},
        {"code": "CUST_MID_60_89", "priority": 2, "rule": [
            {"field": "days_since_last_visit", "op": "BETWEEN", "value": [60, 89]},
            {"field": "orders_30d", "op": "<=", "value": 1}]}],
      "union_allowed": true,
      "min_eligible_override": 10}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.60,
      "seed": {"r_trt": 0.115, "r_ctrl": 0.082,
               "avg_aov": 29000, "avg_discount": 1740}}'::jsonb,
    '{"name_ko": "고객중기이탈"}'::jsonb
),
-- ---------------------------------------------------------------------
-- 2) CUST_VISIT_CYCLE_OVERDUE — 개인 방문주기 초과
-- ---------------------------------------------------------------------
(
    'sales.orders.retention.revisit_interval',
    'CUST_VISIT_CYCLE_OVERDUE',
    'CUSTOMER',
    FALSE,
    '{"segment_codes": [
        {"code": "CUST_CYCLE_OVERDUE_12", "priority": 1, "rule": [
            {"field": "visit_gap_overdue_ratio", "op": ">=", "value": 1.2},
            {"field": "days_since_last_visit", "op": "BETWEEN", "value": [7, 89]},
            {"field": "orders_30d", "op": "<=", "value": 2}]}],
      "union_allowed": false,
      "min_eligible_override": 10}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.55,
      "seed": {"r_trt": 0.090, "r_ctrl": 0.060,
               "avg_aov": 30000, "avg_discount": 1800}}'::jsonb,
    '{"name_ko": "방문주기초과"}'::jsonb
),
-- ---------------------------------------------------------------------
-- 3) CUST_NEW_TO_SECOND — 신규 고객 2차 방문 유도
-- ---------------------------------------------------------------------
(
    'sales.orders.retention.revisit_rate',
    'CUST_NEW_TO_SECOND',
    'CUSTOMER',
    FALSE,
    '{"segment_codes": [
        {"code": "CUST_NEW_LIFETIME_1", "priority": 1, "rule": [
            {"field": "orders_lifetime", "op": "=", "value": 1},
            {"field": "first_order_at", "op": ">=", "value": "1900-01-01"},
            {"field": "days_since_last_visit", "op": "BETWEEN", "value": [7, 30]}]}],
      "union_allowed": false,
      "min_eligible_override": 10,
      "meta": {"store_age_min_days": 365}}'::jsonb,
    '{"offer_buckets": ["RATE_5", "RATE_7", "MESSAGE_ONLY"],
      "default": {"discount_type": "percent", "value_min": 3, "value_max": 7,
                  "ttl_days_min": 5, "ttl_days_max": 10},
      "allowed_actions": ["COUPON", "MESSAGE"]}'::jsonb,
    '{"u_ref": 0.10, "addressability": 0.70,
      "seed": {"r_trt": 0.240, "r_ctrl": 0.080,
               "avg_aov": 28000, "avg_discount": 1680}}'::jsonb,
    '{"name_ko": "고객신규2차방문"}'::jsonb
)
ON CONFLICT (opportunity_type, node_key) DO UPDATE SET
    trigger_type   = EXCLUDED.trigger_type,
    is_active      = EXCLUDED.is_active,
    candidate_json = EXCLUDED.candidate_json,
    offer_json     = EXCLUDED.offer_json,
    prior_json     = EXCLUDED.prior_json,
    meta_json      = EXCLUDED.meta_json,
    updated_at     = now();

COMMIT;

SELECT opportunity_type, node_key, is_active FROM sellup.apilot_opportunity_registry;
INSERT INTO sellup.apilot_config_system (config_key, config_value_json)
VALUES ('calibration_enabled', '{"value": false}');
SELECT config_key, config_value_json FROM sellup.apilot_config_system
WHERE config_key IN ('calibration_enabled', 'episode_enabled', 'message_only_enabled');