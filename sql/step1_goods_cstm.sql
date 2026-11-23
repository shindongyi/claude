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
   - 테이블 생성 없음. 아래 [확인] 3개 → [본 쿼리] → [점검] 순서로 실행
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
   [본 쿼리] 본점 / T1-DF4 / T2-DF4 상품 기초재고 — 신고 Detail 양식 형태
             특정 점만 보려면 BOND 블록에서 줄을 지우면 됨
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040'             FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041'             FROM DUAL
),

-- ① HS세관재고 11/30 : 보세구역 × 장치장 × 상품·세관상품코드 (반입 − 반출 누계)
CSTM AS (
    SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD,
           SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
      FROM WM0121L L, PRM P
     WHERE L.COMP_CD = P.COMP_CD
       AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
       AND L.EDI_REPA_DT <= P.BASE_DT
       -- AND L.SHED_CD = L.BOND_GRN_CD          -- 자기 장치장만 볼 때 (통물 장치장 04077090/04077137 제외)
     GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD
),

-- 환급코드 마스터 (상품 마이그에서 등록)
REFU AS (
    SELECT R.GOOS_CD, R.CSTM_GOODS_TYPE_CD, R.CSTM_GOOS_CD,
           COUNT(*) OVER (PARTITION BY R.GOOS_CD) CODE_CNT        -- 상품 하나에 환급코드 몇 개
      FROM MA9301C R
     WHERE R.COMP_CD = '01' AND R.USE_YN = 'Y'
),

-- ② 환급코드 먼저 반영 (행 단위)
--    1순위: 세관재고의 세관상품코드 = MA9301C 세관상품코드  (환급 W 코드가 이미 세관재고에 있는 경우)
--    2순위: 상품코드로 붙이되 그 상품의 환급코드가 1개뿐일 때만 (여러 개면 어느 쪽인지 모르므로 미매칭)
TAGGED AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.GOOS_CD, C.CSTM_GOOS_CD ORG_CSTM_GOOS_CD, C.HS_CD, C.CSTM_ITEM_CLS_CD, C.QTY,
           COALESCE(R1.CSTM_GOODS_TYPE_CD, R2.CSTM_GOODS_TYPE_CD) CSTM_GOODS_TYPE_CD,
           COALESCE(R1.CSTM_GOOS_CD,       R2.CSTM_GOOS_CD)       NEW_CSTM_GOOS_CD,
           CASE WHEN R1.CSTM_GOOS_CD IS NOT NULL THEN 'CSTM_CD'
                WHEN R2.CSTM_GOOS_CD IS NOT NULL THEN 'GOOS_CD'
                ELSE 'NONE' END                                    MATCH_BY
      FROM CSTM C
      LEFT JOIN REFU R1 ON R1.CSTM_GOOS_CD = C.CSTM_GOOS_CD
      LEFT JOIN REFU R2 ON R1.CSTM_GOOS_CD IS NULL AND R2.GOOS_CD = C.GOOS_CD AND R2.CODE_CNT = 1
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드
AGG AS (
    SELECT T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY,
           MAX(T.HS_CD) HS_CD, SUM(T.QTY) QTY
      FROM TAGGED T
     GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD, T.MATCH_BY
)

SELECT D.STOR_NM,                                                                 -- (참고) 점
       A.BOND_GRN_CD                                         AS WH_CODE,         -- 신고지점 (보세구역)
       CASE WHEN A.SHED_CD = A.BOND_GRN_CD THEN NULL ELSE A.SHED_CD END AS CARRYIN_LOC,  -- 통물 장치장이면 값
       'Z'                                                   AS DECLARATION_TYPE, -- 기초재고반입
       A.CSTM_GOODS_TYPE_CD                                  AS ITEM_TYPE,        -- T / D / W (환급코드)
       A.NEW_CSTM_GOOS_CD                                    AS ITEM_CODE,        -- 세관신고 상품코드
       A.GOOS_CD,                                                                 -- (참고) 원 상품코드
       A.HS_CD                                               AS HS_CODE,
       B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM      AS ITEM_NAME,        -- GWP 마이그의 세관상품명 규칙과 동일 (컬럼 확인)
       M.BRAN_CD                                             AS BRAND_CODE,
       B.BRAN_NM                                             AS BRAND_NAME,
       A.QTY                                                 AS ITEM_QTY,
       V.GOOS_CAPA                                           AS CAPACITY,         -- 신고용량 (MA3118I)
       A.MATCH_BY,                                                                -- 환급코드를 어떻게 붙였는지
       CASE WHEN M.GOOS_CD IS NULL THEN 'Y' END              AS OLD_CODE_YN       -- 상품마스터에 없음 = 구코드 후보
       -- item_norm(규격), item_cost(판매가), unit_code, qty_unit_code 는 필요한 조인 추가
  FROM AGG A
  JOIN BOND D ON D.BOND_GRN_CD = A.BOND_GRN_CD
  CROSS JOIN PRM P
  LEFT JOIN MA0040C M ON M.COMP_CD = P.COMP_CD AND M.GOOS_CD = A.GOOS_CD        -- 상품마스터
  LEFT JOIN MA0030C B ON B.COMP_CD = M.COMP_CD AND B.BRAN_CD = M.BRAN_CD        -- 브랜드
  LEFT JOIN MA3118I V ON V.COMP_CD = P.COMP_CD AND V.GOOS_CD = A.GOOS_CD        -- 상품용량추가정보
 WHERE A.QTY <> 0
 ORDER BY WH_CODE, CARRYIN_LOC NULLS FIRST, ITEM_TYPE, ITEM_CODE;



/* =====================================================================
   [점검] 본 쿼리를 감싸서 (WITH ... 마지막 SELECT 를 FROM ( ) 안에 넣어서) 확인
   =====================================================================
   SELECT STOR_NM, CARRYIN_LOC, ITEM_TYPE, MATCH_BY, OLD_CODE_YN,
          COUNT(*) ROW_CNT, SUM(ITEM_QTY) QTY,
          SUM(CASE WHEN ITEM_QTY < 0 THEN 1 ELSE 0 END) MINUS_CNT
     FROM ( <본 쿼리> )
    GROUP BY STOR_NM, CARRYIN_LOC, ITEM_TYPE, MATCH_BY, OLD_CODE_YN
    ORDER BY 1, 2 NULLS FIRST, 3, 4, 5;

   - MATCH_BY = 'NONE'   → 환급코드를 못 붙임 (MA9301C 미등록이거나, 상품에 T/W 둘 다 있어서 어느 쪽인지 모름)
   - OLD_CODE_YN = 'Y'   → 구코드 정리 대상 (신코드 매핑 필요)
   - 보세구역·장치장별 합계는 WM0121S 11/30 집계와 같아야 함 (sql/12 [D])
*/
