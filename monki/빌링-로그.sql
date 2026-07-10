CREATE TABLE billing.api_transmission
(
    api_trans_id    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    request_id      uuid             NOT NULL DEFAULT gen_random_uuid(),
    call_from       text             NOT NULL,                   -- 어느 페이지(모듈)에서 호출한건지

    -- 연동 대상
    target_system   text             NOT NULL,                   -- 'hyosung_fms' ...
    api_name        text             NOT NULL,                   -- 'cms_withdraw_request' 등
    endpoint        text             NOT NULL,
    http_method     text             NOT NULL,

    -- 요청/응답 payload (민감정보 마스킹 후 저장)
    request_headers jsonb,
    request_body    jsonb,
    response_status int,
    response_body   jsonb,

    -- 결과
    status          text             NOT NULL DEFAULT 'pending'
        CONSTRAINT chk_api_trans_status
        CHECK (status IN ('pending','success','failed','timeout')),
    result_code     text,
    error_message   text,
    retry_count     int              NOT NULL DEFAULT 0,
    latency_ms      int,

    -- 역추적
    ref_type        text,                                        -- 'invoice' | 'cms_member' ...
    ref_id          text,

    -- 시각
    requested_at    timestamptz      NOT NULL DEFAULT now(),
    responded_at    timestamptz,
    created_at      timestamptz      NOT NULL DEFAULT now()
);

CREATE INDEX idx_api_trans_created ON billing.api_transmission (created_at DESC);
CREATE INDEX idx_api_trans_ref     ON billing.api_transmission (ref_type, ref_id);
CREATE INDEX idx_api_trans_failed  ON billing.api_transmission (created_at DESC)
    WHERE status IN ('failed','timeout');

alter table billing.api_transmission owner to mk;