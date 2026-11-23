/* =====================================================================
   STEP 1. 상품 기초 — 본점 / T1-DF4 / T2-DF4 : HS세관재고 집계 기준
           (환급코드 분리 → 집계, 구코드 정리)    기준일 2026-11-30
   ---------------------------------------------------------------------
   - 세관재고(WM0121L/S)에는 점코드가 없고 보세구역코드(BOND_GRN_CD)로만 나뉨
     → 점을 보세구역으로 바꿔서 조회 (고객 설명, 11/20 HS 세관재고 기준)
          본점    STOR_CD 05 = 보세구역 01022006
          T1-DF4  STOR_CD 15 = 보세구역 04021040
          T2-DF4  STOR_CD 17 = 보세구역 04021041
     신고서 신고지점(wh_code)도 이 보세구역코드
   ---------------------------------------------------------------------
   - 환급코드 = MA9301C(마스터_세관신고 상품코드).CSTM_GOODS_TYPE_CD
       T 수입 / D 내국 / W 환급   (상품 마이그에서 MA0042L 바코드 AGIG_CD 6번째 자리 = 1 이면 W)
     W 는 세관신고 상품코드가 따로 있음: CSTM_GOOS_CD = (수입 5 / 국산 6) || SUBSTR(GOOS_CD, 2)
   - 그래서 신고서 품목코드(item_code)는 GOOS_CD 가 아니라 MA9301C.CSTM_GOOS_CD
   - 순서: ① 세관재고(WM0121L) 행마다 환급코드를 먼저 붙이고 → ② 세관상품코드 단위로 집계
   - 테이블 생성 없음. [확인] 3개 → [Detail] → [Header] → [점검] 순서로 실행
   - [Detail]·[Header] 는 신고 양식(SR_ItemCarryIn_D / _H) 컬럼 순서 그대로, 못 찾은 항목은 NULL
   ===================================================================== */


/* ---------------------------------------------------------------------
   [확인 1] 본점·T1·T2 세관재고의 세관상품코드가 어떻게 생겼는지
     - CSTM_GOOS_CD 가 GOOS_CD 와 다르고 5/6 으로 시작하면 → 세관재고에 이미 환급코드가 들어 있음
     - 전부 GOOS_CD 와 같으면 → 세관재고만으로는 환급분을 못 나눔 (고객에게 분리 기준 확인 필요)
   --------------------------------------------------------------------- */
SELECT L.BOND_GRN_CD,
       CASE WHEN L.CSTM_GOOS_CD = L.GOOS_CD THEN '같음'
            WHEN L.CSTM_GOOS_CD IS NULL     THEN '비어있음'
            ELSE '다름(첫자리 ' || SUBSTR(L.CSTM_GOOS_CD, 1, 1) || ')' END AS CSTM_VS_GOOS,
       L.CSTM_ITEM_CLS_CD,                                     -- 세관물품구분 (MA071)
       COUNT(*) ROW_CNT, COUNT(DISTINCT L.GOOS_CD) GOOS_CNT,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L
 WHERE L.COMP_CD = '01'
   AND L.BOND_GRN_CD IN ('01022006', '04021040', '04021041')   -- 본점 / T1-DF4 / T2-DF4
   AND L.EDI_REPA_DT <= '20261130'
 GROUP BY L.BOND_GRN_CD,
          CASE WHEN L.CSTM_GOOS_CD = L.GOOS_CD THEN '같음'
               WHEN L.CSTM_GOOS_CD IS NULL     THEN '비어있음'
               ELSE '다름(첫자리 ' || SUBSTR(L.CSTM_GOOS_CD, 1, 1) || ')' END,
          L.CSTM_ITEM_CLS_CD
 ORDER BY 1, 2, 3;

/* ---------------------------------------------------------------------
   [확인 2] MA9301C 상태: 상품 하나에 환급코드가 몇 개씩 있는지
   --------------------------------------------------------------------- */
SELECT TYPE_SET, COUNT(*) GOOS_CNT
  FROM (SELECT GOOS_CD, LISTAGG(CSTM_GOODS_TYPE_CD, '+') WITHIN GROUP (ORDER BY CSTM_GOODS_TYPE_CD) TYPE_SET
          FROM MA9301C
         WHERE COMP_CD = '01' AND USE_YN = 'Y'
         GROUP BY GOOS_CD)
 GROUP BY TYPE_SET
 ORDER BY 2 DESC;                                              -- 예: T / D / W / T+W / D+W ...

/* ---------------------------------------------------------------------
   [확인 3] 세관재고 상품이 MA9301C 에 붙는 비율 (세관상품코드로 / 상품코드로)
   --------------------------------------------------------------------- */
SELECT C.BOND_GRN_CD,
       COUNT(DISTINCT C.CSTM_GOOS_CD)                                                     CSTM_CODES,
       COUNT(DISTINCT CASE WHEN R1.CSTM_GOOS_CD IS NOT NULL THEN C.CSTM_GOOS_CD END)      MATCH_BY_CSTM_CD,
       COUNT(DISTINCT C.GOOS_CD)                                                          GOOS_CODES,
       COUNT(DISTINCT CASE WHEN R2.GOOS_CD IS NOT NULL THEN C.GOOS_CD END)                MATCH_BY_GOOS_CD,
       COUNT(DISTINCT CASE WHEN M.GOOS_CD IS NULL THEN C.GOOS_CD END)                     NOT_IN_MA0040C   -- 구코드 후보
  FROM (SELECT DISTINCT BOND_GRN_CD, GOOS_CD, CSTM_GOOS_CD FROM WM0121L
         WHERE COMP_CD = '01' AND BOND_GRN_CD IN ('01022006', '04021040', '04021041') AND EDI_REPA_DT <= '20261130') C
  LEFT JOIN MA9301C R1 ON R1.COMP_CD = '01' AND R1.USE_YN = 'Y' AND R1.CSTM_GOOS_CD = C.CSTM_GOOS_CD
  LEFT JOIN MA9301C R2 ON R2.COMP_CD = '01' AND R2.USE_YN = 'Y' AND R2.GOOS_CD = C.GOOS_CD
  LEFT JOIN MA0040C M  ON M.COMP_CD = '01' AND M.GOOS_CD = C.GOOS_CD
 GROUP BY C.BOND_GRN_CD
 ORDER BY 1;




/* =====================================================================
   [Detail] SR_ItemCarryIn_D 양식 순서   — 못 찾은 항목은 NULL (직접 조인해서 채우기)
            양식 컬럼 뒤에 "참고" 컬럼 몇 개를 붙였음 (검토용, 적재 땐 제외)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),   -- 기준일 / 신고일자
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (??? 는 고객 확인 후 채움)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '???' CSTM_CD, '??' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '???',          '??',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '???',          '??',         '?'            FROM DUAL
),

-- ① HS세관재고 11/30 : 보세구역 × 장치장 × 상품·세관상품코드 (반입 − 반출 누계)
CSTM AS (
    SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD,
           SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
      FROM WM0121L L, PRM P
     WHERE L.COMP_CD = P.COMP_CD
       AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
       AND L.EDI_REPA_DT <= P.BASE_DT
       -- AND L.SHED_CD = L.BOND_GRN_CD          -- 자기 장치장만 (통물 장치장 04077090/04077137 제외할 때)
     GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD
),

-- 환급코드 마스터 (상품 마이그에서 등록한 MA9301C)
REFU AS (
    SELECT R.GOOS_CD, R.CSTM_GOODS_TYPE_CD, R.CSTM_GOOS_CD,
           COUNT(*) OVER (PARTITION BY R.GOOS_CD) CODE_CNT
      FROM MA9301C R
     WHERE R.COMP_CD = '01' AND R.USE_YN = 'Y'
),

-- ② 환급코드 먼저 반영 (행 단위)
--    1순위 세관상품코드로 매칭 / 2순위 상품코드로 매칭(그 상품의 환급코드가 1개일 때만)
TAGGED AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.GOOS_CD, C.HS_CD, C.QTY,
           COALESCE(R1.CSTM_GOODS_TYPE_CD, R2.CSTM_GOODS_TYPE_CD) CSTM_GOODS_TYPE_CD,
           COALESCE(R1.CSTM_GOOS_CD,       R2.CSTM_GOOS_CD)       NEW_CSTM_GOOS_CD,
           CASE WHEN R1.CSTM_GOOS_CD IS NOT NULL THEN 'CSTM_CD'
                WHEN R2.CSTM_GOOS_CD IS NOT NULL THEN 'GOOS_CD'
                ELSE 'NONE' END MATCH_BY
      FROM CSTM C
      LEFT JOIN REFU R1 ON R1.CSTM_GOOS_CD = C.CSTM_GOOS_CD
      LEFT JOIN REFU R2 ON R1.CSTM_GOOS_CD IS NULL AND R2.GOOS_CD = C.GOOS_CD AND R2.CODE_CNT = 1
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드  (0 이하는 신고 대상 아님 → [점검]에서 확인)
AGG AS (
    SELECT T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY,
           MAX(T.HS_CD) HS_CD, SUM(T.QTY) QTY
      FROM TAGGED T
     GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY
    HAVING SUM(T.QTY) > 0
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다 신고서, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.BOND_GRN_CD, A.SHED_CD
                              ORDER BY A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                              ORDER BY N.SHED_CD, CEIL(N.RN / 9999)) DECL_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'A' + 일련번호(8: 접두문자 + 케이스 '1'(상품 세관재고) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '1' || LPAD(DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      JOIN BOND D ON D.BOND_GRN_CD = N.BOND_GRN_CD
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,     --  1 신고번호
       X.BOND_GRN_CD                                      AS WH_CODE,            --  2 신고지점
       'DLG'                                              AS DOC_TYPE,           --  3 문서구분
       X.DOC_SEQ                                          AS DOC_SEQ,            --  4 품목일련번호
       NULL                                               AS RAMEND_TYPE,        --  5 란정정구분 (DLH 만)
       X.CSTM_GOODS_TYPE_CD                               AS ITEM_TYPE,          --  6 물품구분 T/D/W (환급코드)
       X.HS_CD                                            AS HS_CODE,            --  7 HS코드 (세관재고 WM0121L)
       X.NEW_CSTM_GOOS_CD                                 AS ITEM_CODE,          --  8 상품코드 = 세관신고 상품코드 (MA9301C)
       B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM   AS ITEM_NAME,          --  9 품명 (GWP 마이그 세관상품명 규칙, 컬럼 확인)
       NULL                                               AS ITEM_NORM,          -- 10 규격
       X.QTY                                              AS ITEM_QTY,           -- 11 수량
       NULL                                               AS ITEM_COST,          -- 12 단가(미화)
       NULL                                               AS ITEM_AMOUNT,        -- 13 금액 (= 수량 × 단가)
       V.GOOS_CAPA                                        AS CAPACITY,           -- 14 용량 (MA3118I 신고용량)
       M.BRAN_CD                                          AS BRAND_CODE,         -- 15 브랜드코드
       B.BRAN_NM                                          AS BRAND_NAME,         -- 16 브랜드명 (MA0030C)
       NULL                                               AS UNIT_CODE,          -- 17 용량단위
       NULL                                               AS GWP_PRODUCT_GRADE,  -- 18 GWP물품등급 (상품은 공백)
       NULL                                               AS REGISTER_NO,        -- 19 참조번호 (기초재고 Z 는 공백)
       NULL                                               AS ITEM_COST_KRW,      -- 20 단가(원화)
       NULL                                               AS QTY_UNIT_CODE,      -- 21 수량단위
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       X.SHED_CD                                          AS REF_SHED_CD,
       X.GOOS_CD                                          AS REF_GOOS_CD,
       X.MATCH_BY                                         AS REF_MATCH_BY,       -- NONE = 환급코드 못 붙임
       CASE WHEN M.GOOS_CD IS NULL THEN 'Y' END           AS REF_OLD_CODE_YN     -- Y = 구코드 정리 대상
  FROM DECL X
  LEFT JOIN MA0040C M ON M.COMP_CD = '01' AND M.GOOS_CD = X.GOOS_CD        -- 상품마스터
  LEFT JOIN MA0030C B ON B.COMP_CD = M.COMP_CD AND B.BRAN_CD = M.BRAN_CD   -- 브랜드
  LEFT JOIN MA3118I V ON V.COMP_CD = '01' AND V.GOOS_CD = X.GOOS_CD        -- 상품용량추가정보
 ORDER BY X.DECLARATION_NO, X.DOC_SEQ;


/* =====================================================================
   [Header] SR_ItemCarryIn_H 양식 순서   — 신고서마다 1행 (Detail 과 같은 WITH, 마지막 SELECT 만 다름)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),   -- 기준일 / 신고일자
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (??? 는 고객 확인 후 채움)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '???' CSTM_CD, '??' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '???',          '??',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '???',          '??',         '?'            FROM DUAL
),

-- ① HS세관재고 11/30 : 보세구역 × 장치장 × 상품·세관상품코드 (반입 − 반출 누계)
CSTM AS (
    SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD,
           SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
      FROM WM0121L L, PRM P
     WHERE L.COMP_CD = P.COMP_CD
       AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
       AND L.EDI_REPA_DT <= P.BASE_DT
       -- AND L.SHED_CD = L.BOND_GRN_CD          -- 자기 장치장만 (통물 장치장 04077090/04077137 제외할 때)
     GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD
),

-- 환급코드 마스터 (상품 마이그에서 등록한 MA9301C)
REFU AS (
    SELECT R.GOOS_CD, R.CSTM_GOODS_TYPE_CD, R.CSTM_GOOS_CD,
           COUNT(*) OVER (PARTITION BY R.GOOS_CD) CODE_CNT
      FROM MA9301C R
     WHERE R.COMP_CD = '01' AND R.USE_YN = 'Y'
),

-- ② 환급코드 먼저 반영 (행 단위)
--    1순위 세관상품코드로 매칭 / 2순위 상품코드로 매칭(그 상품의 환급코드가 1개일 때만)
TAGGED AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.GOOS_CD, C.HS_CD, C.QTY,
           COALESCE(R1.CSTM_GOODS_TYPE_CD, R2.CSTM_GOODS_TYPE_CD) CSTM_GOODS_TYPE_CD,
           COALESCE(R1.CSTM_GOOS_CD,       R2.CSTM_GOOS_CD)       NEW_CSTM_GOOS_CD,
           CASE WHEN R1.CSTM_GOOS_CD IS NOT NULL THEN 'CSTM_CD'
                WHEN R2.CSTM_GOOS_CD IS NOT NULL THEN 'GOOS_CD'
                ELSE 'NONE' END MATCH_BY
      FROM CSTM C
      LEFT JOIN REFU R1 ON R1.CSTM_GOOS_CD = C.CSTM_GOOS_CD
      LEFT JOIN REFU R2 ON R1.CSTM_GOOS_CD IS NULL AND R2.GOOS_CD = C.GOOS_CD AND R2.CODE_CNT = 1
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드  (0 이하는 신고 대상 아님 → [점검]에서 확인)
AGG AS (
    SELECT T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY,
           MAX(T.HS_CD) HS_CD, SUM(T.QTY) QTY
      FROM TAGGED T
     GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY
    HAVING SUM(T.QTY) > 0
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다 신고서, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.BOND_GRN_CD, A.SHED_CD
                              ORDER BY A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                              ORDER BY N.SHED_CD, CEIL(N.RN / 9999)) DECL_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'A' + 일련번호(8: 접두문자 + 케이스 '1'(상품 세관재고) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '1' || LPAD(DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      JOIN BOND D ON D.BOND_GRN_CD = N.BOND_GRN_CD
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,        --  1 신고번호
       X.BOND_GRN_CD                                      AS WH_CODE,               --  2 신고지점
       'DLG'                                              AS DOC_TYPE,              --  3 문서구분
       P.DECL_DT                                          AS DECLARATION_DATE,      --  4 신고일자
       NULL                                               AS AMEND_TYPE,            --  5 정정구분 (DLH 만)
       CASE WHEN X.SHED_CD = X.BOND_GRN_CD THEN NULL
            ELSE X.SHED_CD END                            AS CARRYIN_LOC,           --  6 반입장치장소 (통물 장치장일 때만)
       NULL                                               AS REFERENCE_NO,          --  7 근거번호
       'Z'                                                AS DECLARATION_TYPE,      --  8 신고구분 Z 기초재고반입
       'A1'                                               AS STATUS,                --  9 상태 A1 생성
       SYSDATE                                            AS C_DATETIME,            -- 10 생성일시
       NULL                                               AS INTERNATIONAL_MAIL_YN, -- 11 국제우편여부
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       COUNT(*)                                           AS REF_ITEM_CNT,
       SUM(X.QTY)                                         AS REF_QTY
  FROM DECL X
  CROSS JOIN PRM P
 GROUP BY X.DECLARATION_NO, X.BOND_GRN_CD, P.DECL_DT, X.SHED_CD, X.STOR_NM
 ORDER BY X.DECLARATION_NO;


/* =====================================================================
   [점검] 신고에서 빠지거나 비는 것
   ===================================================================== */
-- 0 이하 재고 (신고 제외됨) / 환급코드 못 붙임 / 구코드 — Detail 쿼리의 참고 컬럼으로도 확인 가능
SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L
 WHERE L.COMP_CD = '01'
   AND L.BOND_GRN_CD IN ('01022006', '04021040', '04021041')
   AND L.EDI_REPA_DT <= '20261130'
 GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD
HAVING SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) < 0
 ORDER BY 1, 2, 3;

-- Header 합계(REF_QTY) 를 보세구역·장치장별로 모으면 WM0121S 11/30 집계와 같아야 함 (sql/12 [D])
