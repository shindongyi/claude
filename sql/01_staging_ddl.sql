/* =====================================================================
   01. 기초재고 마이그레이션 스테이징 DDL (초안)
   - 컴포넌트별 상세를 남겨 차이 추적이 가능하도록 설계
   ===================================================================== */

-- 컴포넌트 상세: 원천 수량은 양수로, 가감은 SIGN 으로
CREATE TABLE MIG_STOC_COMP (
    MIG_RUN_ID      VARCHAR2(20)   NOT NULL,   -- 리허설 회차 (예: R1, R2, R3, PROD)
    BASE_DT         VARCHAR2(8)    NOT NULL,   -- 기준일자
    COMP_CD         CHAR(2)        NOT NULL,
    STOR_CD         VARCHAR2(10)   NOT NULL,   -- 재고 귀속 점 (원천 코드)
    CORN_CD         VARCHAR2(10),              -- 재고 귀속 코너/창고 (원천 코드)
    BOND_GRN_CD     VARCHAR2(20),              -- 보세구역 (세관재고 컴포넌트)
    SHED_CD         VARCHAR2(20),              -- 장치장
    ITEM_TYPE       VARCHAR2(1)    NOT NULL,   -- G:상품, W:GWP
    STOC_TYPE       VARCHAR2(1)    NOT NULL,   -- N:정상, U:미인도
    COMP_TYPE       VARCHAR2(3)    NOT NULL,   -- C01 HS세관재고 / C02 수불기말 / C03 교환권(+) / C04 H재반입(-) / C05 미인도반입(-)
    SIGN            NUMBER(1)      NOT NULL,   -- +1 / -1
    GOOS_CD_ORG     VARCHAR2(30)   NOT NULL,   -- 원천 상품코드
    REFUND_CLS      VARCHAR2(10),              -- 환급구분 (분리 기준값 보관)
    GOOS_CD         VARCHAR2(30),              -- 환급분리+구코드정리 후 최종 상품코드
    QTY             NUMBER(15)     NOT NULL,
    SRC_BILL_NO     VARCHAR2(30),              -- 원천 빌번호 (빌 기반 컴포넌트)
    SRC_KEY         VARCHAR2(200),             -- 기타 원천 키 (SALE_DT|POS|RCPT|SEQ 등)
    EXTR_DTTM       DATE DEFAULT SYSDATE NOT NULL
);
CREATE INDEX MIG_STOC_COMP_IX1 ON MIG_STOC_COMP (MIG_RUN_ID, COMP_TYPE, STOR_CD);
CREATE INDEX MIG_STOC_COMP_IX2 ON MIG_STOC_COMP (MIG_RUN_ID, SRC_BILL_NO);

-- 최종 기초재고
CREATE TABLE MIG_BASE_STOC (
    MIG_RUN_ID      VARCHAR2(20)   NOT NULL,
    BASE_DT         VARCHAR2(8)    NOT NULL,
    COMP_CD         CHAR(2)        NOT NULL,
    NEW_WH_CD       VARCHAR2(20)   NOT NULL,   -- 신규 시스템 창고코드
    ITEM_TYPE       VARCHAR2(1)    NOT NULL,
    STOC_TYPE       VARCHAR2(1)    NOT NULL,
    GOOS_CD         VARCHAR2(30)   NOT NULL,
    QTY             NUMBER(15)     NOT NULL,
    CONSTRAINT MIG_BASE_STOC_PK PRIMARY KEY (MIG_RUN_ID, COMP_CD, NEW_WH_CD, ITEM_TYPE, STOC_TYPE, GOOS_CD)
);

-- 매핑표 (고객 제공 엑셀 적재)
CREATE TABLE MIG_MAP_STOR (            -- 원천 점/코너 -> 신규 창고, 적용 규칙 구분
    COMP_CD     CHAR(2)      NOT NULL,
    STOR_CD     VARCHAR2(10) NOT NULL,
    CORN_CD     VARCHAR2(10) DEFAULT '*' NOT NULL,   -- '*' = 점 전체
    SITE_GRP    VARCHAR2(10) NOT NULL,               -- MAIN(본점) / T1 / T2 / LOGI(통합물류)
    NEW_WH_CD   VARCHAR2(20) NOT NULL,
    CONSTRAINT MIG_MAP_STOR_PK PRIMARY KEY (COMP_CD, STOR_CD, CORN_CD)
);

CREATE TABLE MIG_MAP_REFUND (          -- 환급코드 분리
    GOOS_CD_ORG VARCHAR2(30) NOT NULL,
    REFUND_CLS  VARCHAR2(10) NOT NULL,   -- 분리 기준값 (예: CSTM_ITEM_CLS_CD 또는 PMIT_CLS_CD) — 고객 확인
    GOOS_CD_REF VARCHAR2(30) NOT NULL,   -- 환급/비환급 분리 후 코드
    CONSTRAINT MIG_MAP_REFUND_PK PRIMARY KEY (GOOS_CD_ORG, REFUND_CLS)
);

CREATE TABLE MIG_MAP_GOOS (            -- 구코드 정리 (N:1 허용)
    OLD_GOOS_CD VARCHAR2(30) NOT NULL PRIMARY KEY,
    NEW_GOOS_CD VARCHAR2(30) NOT NULL
);

CREATE TABLE MIG_MAP_BOND (            -- 보세구역/장치장 -> 원천 점코드 (HS세관재고 귀속용)
    BOND_GRN_CD VARCHAR2(20) NOT NULL,
    SHED_CD     VARCHAR2(20) NOT NULL,
    STOR_CD     VARCHAR2(10) NOT NULL,
    CONSTRAINT MIG_MAP_BOND_PK PRIMARY KEY (BOND_GRN_CD, SHED_CD)
);
