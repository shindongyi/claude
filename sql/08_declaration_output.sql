/* =====================================================================
   08. 세관 신고 양식 산출: 물품반입검사신청서 Header / Detail
       (고객 제공 양식 SR_ItemCarryIn_H / SR_ItemCarryIn_D 와 같은 구조로 Oracle 스테이징에 만든 뒤 전달)
   - 신고구분(declaration_type): Z 기초재고반입 (정상) / Y 미인도물품재고반입 (미인도, 교환권번호 기재)
   - 문서구분(doc_type): DLG 물품반입검사신청,  상태(status): A1 생성
   - 신고 1건당 품목은 1~9999 → 9999 품목씩 나눠 여러 건으로
   - carryin_loc(반입장치장소): 통합물류창고 등 다른 장치장일 때만 입력, 자기 장치장이면 NULL
   ※ 미확정: 세관(3)·과(2) 코드, 일련번호 규칙, 상품 정보(품명·규격·HS·브랜드·판매가·단위) 원천 테이블
   바인드: :RUN_ID, :DECL_DT (신고일자 YYYYMMDD), :SEQ_PREFIX (일련번호 첫 글자, 면세점 A~T 중 고객 지정)
   ===================================================================== */

CREATE TABLE MIG_DECL_H (
    MIG_RUN_ID        VARCHAR2(20) NOT NULL,
    DECLARATION_NO    VARCHAR2(27) NOT NULL,   -- 세관(3)+과(2)+보세구역(8)+년도(2)+구분코드 'A'(1)+일련번호(8)
    WH_CODE           VARCHAR2(8)  NOT NULL,   -- 신고지점 보세구역코드
    DOC_TYPE          CHAR(3)      NOT NULL,   -- DLG
    DECLARATION_DATE  VARCHAR2(8)  NOT NULL,
    AMEND_TYPE        VARCHAR2(3),             -- DLH(정정)만
    CARRYIN_LOC       VARCHAR2(8),             -- 반입장치장소 (통합물류 등)
    REFERENCE_NO      VARCHAR2(24),
    DECLARATION_TYPE  CHAR(1)      NOT NULL,   -- Z / Y
    STATUS            VARCHAR2(2)  NOT NULL,   -- A1
    INTERNATIONAL_MAIL_YN CHAR(1),
    CONSTRAINT MIG_DECL_H_PK PRIMARY KEY (MIG_RUN_ID, DECLARATION_NO, WH_CODE, DOC_TYPE)
);

CREATE TABLE MIG_DECL_D (
    MIG_RUN_ID        VARCHAR2(20)  NOT NULL,
    DECLARATION_NO    VARCHAR2(27)  NOT NULL,
    WH_CODE           VARCHAR2(8)   NOT NULL,
    DOC_TYPE          VARCHAR2(3)   NOT NULL,
    DOC_SEQ           NUMBER(4)     NOT NULL,  -- 1 ~ 9999
    ITEM_TYPE         CHAR(1)       NOT NULL,  -- T 수입 / W 환급 / H 보세공장·수출자유무역 / D 내국
    HS_CODE           VARCHAR2(10)  NOT NULL,
    ITEM_CODE         VARCHAR2(24)  NOT NULL,
    ITEM_NAME         VARCHAR2(200) NOT NULL,
    ITEM_NORM         VARCHAR2(50)  NOT NULL,  -- 규격
    ITEM_QTY          NUMBER(10)    NOT NULL,
    ITEM_COST         NUMBER(16,2)  NOT NULL,  -- 단가(미화) = 판매가, GWP 0 가능
    ITEM_AMOUNT       NUMBER(16,2)  NOT NULL,
    CAPACITY          NUMBER(7,2),
    BRAND_CODE        VARCHAR2(10)  NOT NULL,
    BRAND_NAME        VARCHAR2(200) NOT NULL,
    UNIT_CODE         CHAR(2),                 -- 용량단위
    GWP_PRODUCT_GRADE CHAR(1),
    REGISTER_NO       VARCHAR2(24),            -- Y(미인도물품재고반입)일 때 교환권번호
    ITEM_COST_KRW     NUMBER(18),
    QTY_UNIT_CODE     VARCHAR2(10)  NOT NULL,  -- 수량단위
    CONSTRAINT MIG_DECL_D_PK PRIMARY KEY (MIG_RUN_ID, DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ)
);

-- 보세구역별 세관·과 코드 (고객 제공)
CREATE TABLE MIG_MAP_CSTM_OFFICE (
    WH_CODE   VARCHAR2(8) NOT NULL PRIMARY KEY,   -- 01022006 / 04021040 / 04021041
    CSTM_CD   VARCHAR2(3) NOT NULL,               -- 세관코드
    DEPT_CD   VARCHAR2(2) NOT NULL                -- 과코드
);

/* 상품 정보 뷰 — 상품마스터 테이블 확인 후 작성 (가칭 GOODS_MASTER) */
-- CREATE OR REPLACE VIEW MIG_V_GOOS_INFO AS
-- SELECT GOOS_CD, HS_CD, GOOS_NM, GOOS_NORM, BRAN_CD, BRAN_NM, SALE_DOLR_UCST, SALE_WON_UCST,
--        CAPACITY, CAPA_UNIT_CD, QTY_UNIT_CD, GWP_GRADE
--   FROM GOODS_MASTER;

/* 1) 신고 단위(Header) 와 품목 순번(Detail) 배정: (보세구역, 장치장, 신고구분) 별로 9999 품목씩 */
-- (CTAS 에는 바인드 변수를 쓸 수 없어서 구조만 만들고 INSERT)
CREATE TABLE MIG_DECL_WORK AS
SELECT B.*, CAST(NULL AS CHAR(1)) DECL_TYPE, CAST(NULL AS NUMBER) RN,
       CAST(NULL AS NUMBER) DECL_GRP, CAST(NULL AS NUMBER) DOC_SEQ, CAST(NULL AS VARCHAR2(27)) DECLARATION_NO
  FROM MIG_BASE_STOC B WHERE 1 = 0;

INSERT INTO MIG_DECL_WORK
SELECT X.MIG_RUN_ID, X.BASE_DT, X.COMP_CD, X.WH_CODE, X.SHED_CD, X.ITEM_TYPE, X.STOC_TYPE,
       X.CSTM_ITEM_TYPE, X.GOOS_CD, X.REGISTER_NO, X.QTY,
       CASE X.STOC_TYPE WHEN 'U' THEN 'Y' ELSE 'Z' END,      -- DECL_TYPE
       X.RN, CEIL(X.RN / 9999), MOD(X.RN - 1, 9999) + 1,     -- RN, DECL_GRP, DOC_SEQ
       NULL                                                  -- DECLARATION_NO (아래 MERGE)
  FROM (SELECT B.*,
               ROW_NUMBER() OVER (PARTITION BY B.WH_CODE, B.SHED_CD, B.STOC_TYPE
                                  ORDER BY B.ITEM_TYPE, B.CSTM_ITEM_TYPE, B.GOOS_CD, B.REGISTER_NO) RN
          FROM MIG_BASE_STOC B
         WHERE B.MIG_RUN_ID = :RUN_ID
           AND B.QTY > 0) X;                         -- 음수는 07 검증에서 해결 후 진행

-- 신고번호: (보세구역, 장치장, 신고구분, 그룹) 마다 하나. 일련번호 = 접두문자 + 7자리 순번 (규칙 고객 확인)
MERGE INTO MIG_DECL_WORK W
USING (SELECT G.WH_CODE, G.SHED_CD, G.STOC_TYPE, G.DECL_GRP,
              O.CSTM_CD || O.DEPT_CD || G.WH_CODE || SUBSTR(:DECL_DT, 3, 2) || 'A'
              || :SEQ_PREFIX || LPAD(ROW_NUMBER() OVER (PARTITION BY G.WH_CODE
                                                        ORDER BY G.SHED_CD, G.STOC_TYPE, G.DECL_GRP), 7, '0') AS DECL_NO
         FROM (SELECT DISTINCT WH_CODE, SHED_CD, STOC_TYPE, DECL_GRP FROM MIG_DECL_WORK) G
         JOIN MIG_MAP_CSTM_OFFICE O ON O.WH_CODE = G.WH_CODE) N
   ON (W.WH_CODE = N.WH_CODE AND W.SHED_CD = N.SHED_CD AND W.STOC_TYPE = N.STOC_TYPE AND W.DECL_GRP = N.DECL_GRP)
 WHEN MATCHED THEN UPDATE SET W.DECLARATION_NO = N.DECL_NO;

/* 2) Header */
INSERT INTO MIG_DECL_H (MIG_RUN_ID, DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, CARRYIN_LOC,
                        DECLARATION_TYPE, STATUS, INTERNATIONAL_MAIL_YN)
SELECT DISTINCT :RUN_ID, W.DECLARATION_NO, W.WH_CODE, 'DLG', :DECL_DT,
       CASE WHEN W.SHED_CD = W.WH_CODE THEN NULL ELSE W.SHED_CD END,   -- 통합물류 장치장일 때만
       W.DECL_TYPE, 'A1', 'N'
  FROM MIG_DECL_WORK W;

/* 3) Detail */
INSERT INTO MIG_DECL_D (MIG_RUN_ID, DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, ITEM_TYPE, HS_CODE, ITEM_CODE,
                        ITEM_NAME, ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME,
                        UNIT_CODE, GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE)
SELECT :RUN_ID, W.DECLARATION_NO, W.WH_CODE, 'DLG', W.DOC_SEQ,
       W.CSTM_ITEM_TYPE, G.HS_CD, W.GOOS_CD, G.GOOS_NM, NVL(G.GOOS_NORM, '-'),
       W.QTY,
       CASE W.ITEM_TYPE WHEN 'W' THEN 0 ELSE G.SALE_DOLR_UCST END,                 -- GWP 0 가능
       W.QTY * CASE W.ITEM_TYPE WHEN 'W' THEN 0 ELSE G.SALE_DOLR_UCST END,
       NVL(G.CAPACITY, 0), G.BRAN_CD, G.BRAN_NM, G.CAPA_UNIT_CD, G.GWP_GRADE,
       CASE WHEN W.DECL_TYPE = 'Y' THEN W.REGISTER_NO END,                        -- 교환권번호
       CASE W.ITEM_TYPE WHEN 'W' THEN 0 ELSE G.SALE_WON_UCST END,
       G.QTY_UNIT_CD
  FROM MIG_DECL_WORK W
  JOIN MIG_V_GOOS_INFO G ON G.GOOS_CD = W.GOOS_CD;

/* 4) 검증 */
-- 필수값 누락 (상품정보 미존재 → Detail 에서 빠짐)
SELECT W.GOOS_CD, SUM(W.QTY) QTY FROM MIG_DECL_WORK W
 WHERE NOT EXISTS (SELECT 1 FROM MIG_V_GOOS_INFO G WHERE G.GOOS_CD = W.GOOS_CD)
 GROUP BY W.GOOS_CD;

-- 신고별 품목수 / 수량 (보세구역·장치장·신고구분별 합계가 MIG_BASE_STOC 와 같아야 함)
SELECT H.WH_CODE, H.CARRYIN_LOC, H.DECLARATION_TYPE, H.DECLARATION_NO,
       COUNT(D.DOC_SEQ) ITEM_CNT, SUM(D.ITEM_QTY) QTY, SUM(D.ITEM_AMOUNT) AMT_USD
  FROM MIG_DECL_H H JOIN MIG_DECL_D D
    ON D.MIG_RUN_ID = H.MIG_RUN_ID AND D.DECLARATION_NO = H.DECLARATION_NO AND D.WH_CODE = H.WH_CODE
 WHERE H.MIG_RUN_ID = :RUN_ID
 GROUP BY H.WH_CODE, H.CARRYIN_LOC, H.DECLARATION_TYPE, H.DECLARATION_NO
 ORDER BY 1, 2, 3, 4;
