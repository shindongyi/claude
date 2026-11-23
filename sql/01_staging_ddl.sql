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
    REFUND_CLS      VARCHAR2(10),              -- 환급구분 (수불 REFU_CLS_CD, GO407 등 분리 기준값 보관)
    STOC_CLS_CD     VARCHAR2(10),              -- 재고구분 (수불 STOC_CLS_CD, WM014)
    FALT_CLS_CD     VARCHAR2(10),              -- 불량구분 (수불 FALT_CLS_CD, WM037)
    AGIG_CD         VARCHAR2(10),              -- 에이징코드
    GOOS_CD         VARCHAR2(30),              -- 환급분리+구코드정리 후 최종 상품코드
    QTY             NUMBER(15)     NOT NULL,
    SRC_BILL_NO     VARCHAR2(30),              -- 원천 빌번호 (빌 기반 컴포넌트)
    SRC_KEY         VARCHAR2(200),             -- 기타 원천 키 (SALE_DT|POS|RCPT|SEQ 등)
    EXTR_DTTM       DATE DEFAULT SYSDATE NOT NULL
);
CREATE INDEX MIG_STOC_COMP_IX1 ON MIG_STOC_COMP (MIG_RUN_ID, COMP_TYPE, STOR_CD);
CREATE INDEX MIG_STOC_COMP_IX2 ON MIG_STOC_COMP (MIG_RUN_ID, SRC_BILL_NO);

-- 최종 기초재고 (세관 신고 단위: 보세구역 × 장치장 × 물품구분 × 상품 × 교환권)
CREATE TABLE MIG_BASE_STOC (
    MIG_RUN_ID      VARCHAR2(20)   NOT NULL,
    BASE_DT         VARCHAR2(8)    NOT NULL,
    COMP_CD         CHAR(2)        NOT NULL,
    WH_CODE         VARCHAR2(8)    NOT NULL,   -- 보세구역코드 (신고지점 wh_code) 예: 01022006 본점
    SHED_CD         VARCHAR2(8)    NOT NULL,   -- 장치장코드 (자기 장치장 = WH_CODE, 통물 = 04077090 / 04077137)
    ITEM_TYPE       VARCHAR2(1)    NOT NULL,   -- G:상품, W:GWP
    STOC_TYPE       VARCHAR2(1)    NOT NULL,   -- N:정상 → 신고구분 Z(기초재고반입) / U:미인도 → Y(미인도물품재고반입)
    CSTM_ITEM_TYPE  VARCHAR2(1)    NOT NULL,   -- 물품구분 T:수입 W:환급 H:보세공장·수출자유무역 D:내국 ('?' = 미판정)
    GOOS_CD         VARCHAR2(30)   NOT NULL,
    REGISTER_NO     VARCHAR2(30)   DEFAULT '-' NOT NULL,   -- 미인도(Y)는 교환권번호, 정상은 '-'
    QTY             NUMBER(15)     NOT NULL,
    CONSTRAINT MIG_BASE_STOC_PK PRIMARY KEY
      (MIG_RUN_ID, COMP_CD, WH_CODE, SHED_CD, ITEM_TYPE, STOC_TYPE, CSTM_ITEM_TYPE, GOOS_CD, REGISTER_NO)
);

-- 매핑표 (고객 제공 엑셀 적재)
CREATE TABLE MIG_MAP_STOR (            -- 매출·수불의 (점, 코너) → 보세구역/장치장
    COMP_CD     CHAR(2)      NOT NULL,
    STOR_CD     VARCHAR2(10) NOT NULL,
    CORN_CD     VARCHAR2(10) DEFAULT '*' NOT NULL,   -- '*' = 점 전체
    SITE_GRP    VARCHAR2(10) NOT NULL,               -- MAIN(본점) / T1 / T2 / LOGI(통합물류 장치장)
    WH_CODE     VARCHAR2(8)  NOT NULL,               -- 보세구역 (01022006 / 04021040 / 04021041)
    SHED_CD     VARCHAR2(8)  NOT NULL,               -- 장치장 (예: 961→04077090? 965→04077137? 고객 확인)
    CONSTRAINT MIG_MAP_STOR_PK PRIMARY KEY (COMP_CD, STOR_CD, CORN_CD)
);

CREATE TABLE MIG_MAP_ITEM_CLS (        -- 환급 구분 원천값 → 신고 물품구분(T/W/H/D)
    SRC_TYPE       VARCHAR2(4)  NOT NULL,  -- CSTM: WM0121L.CSTM_ITEM_CLS_CD(MA071) / REFU: 수불 REFU_CLS_CD(GO407)
    SRC_VAL        VARCHAR2(10) NOT NULL,
    CSTM_ITEM_TYPE VARCHAR2(1)  NOT NULL,
    CONSTRAINT MIG_MAP_ITEM_CLS_PK PRIMARY KEY (SRC_TYPE, SRC_VAL)
);

CREATE TABLE MIG_MAP_GOOS_ITEM_TYPE (  -- 매출 기반 컴포넌트(교환권 등)는 환급 속성이 없음 → 상품별 기본 물품구분 (판정 기준 고객 확인)
    GOOS_CD        VARCHAR2(30) NOT NULL PRIMARY KEY,
    CSTM_ITEM_TYPE VARCHAR2(1)  NOT NULL
);

CREATE TABLE MIG_MAP_REFUND (          -- (선택) 환급코드를 별도 상품코드로 나누는 경우에만 사용. 신고양식상 물품구분(T/W)으로 나누면 불필요
    GOOS_CD_ORG VARCHAR2(30) NOT NULL,
    REFUND_CLS  VARCHAR2(10) NOT NULL,   -- 분리 기준값 (예: CSTM_ITEM_CLS_CD 또는 PMIT_CLS_CD) — 고객 확인
    GOOS_CD_REF VARCHAR2(30) NOT NULL,   -- 환급/비환급 분리 후 코드
    CONSTRAINT MIG_MAP_REFUND_PK PRIMARY KEY (GOOS_CD_ORG, REFUND_CLS)
);

CREATE TABLE MIG_MAP_GOOS (            -- 구코드 정리 (N:1 허용)
    OLD_GOOS_CD VARCHAR2(30) NOT NULL PRIMARY KEY,
    NEW_GOOS_CD VARCHAR2(30) NOT NULL
);

CREATE TABLE MIG_MAP_BOND (            -- 세관재고의 (보세구역, 장치장) → 원천 점코드, 장치장 성격
    BOND_GRN_CD VARCHAR2(20) NOT NULL,
    SHED_CD     VARCHAR2(20) NOT NULL,
    STOR_CD     VARCHAR2(10) NOT NULL,
    SITE_GRP    VARCHAR2(10) NOT NULL,     -- MAIN / T1 / T2 (자기 장치장) / LOGI (04077090, 04077137)
    CONSTRAINT MIG_MAP_BOND_PK PRIMARY KEY (BOND_GRN_CD, SHED_CD)
);

