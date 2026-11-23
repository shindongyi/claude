/* =====================================================================
   STEP 1. 상품 기초 — 본점 / T1-DF4 / T2-DF4 : HS세관재고 집계 기준
           (환급코드 분리 → 집계, 구코드 정리)    기준일 2026-11-30
           본점은 미인도반입면장 교환권(판매취소 아닌 것) 판매수량을 뺌 (−) — 미인도는 STEP 4 에서 Y 로 따로 신고
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
   - 테이블 생성 없음. [확인] 4개 → [Detail] → [Header] → [점검] 순서로 실행
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




/* ---------------------------------------------------------------------
   [확인 4] 세관재고의 환급구분 D 가 GWP 인지 일반상품(국산)인지
     - GWP 여부: GWP 마스터(WM0310C)에 있거나 MA9301C.GWP_YN = 'Y'
     - D 가 전부 GWP 면 → 세관재고에 GWP 가 섞여 있는 것. 상품 기초(STEP 1)에서는 빼고 GWP 단계에서 따로
     - D 에 일반상품이 있으면 → 상품 마이그 규칙(GOOS_TYPE_CD ≠ 1 → D, 국산 내국물품) 대로인 것
   --------------------------------------------------------------------- */
SELECT L.BOND_GRN_CD, L.CSTM_ITEM_CLS_CD,
       CASE WHEN EXISTS (SELECT 1 FROM WM0310C W WHERE W.COMP_CD = '01' AND W.GOOS_CD = L.GOOS_CD)
              OR EXISTS (SELECT 1 FROM MA9301C R WHERE R.COMP_CD = '01' AND R.GOOS_CD = L.GOOS_CD AND R.GWP_YN = 'Y')
            THEN 'GWP' ELSE '상품' END                         AS GOOS_GWP,
       (SELECT MAX(M.GOOS_TYPE_CD) FROM MA0040C M WHERE M.COMP_CD = '01' AND M.GOOS_CD = L.GOOS_CD) AS GOOS_TYPE_CD,
       COUNT(DISTINCT L.GOOS_CD) GOOS_CNT,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L
 WHERE L.COMP_CD = '01'
   AND L.BOND_GRN_CD IN ('01022006', '04021040', '04021041')
   AND L.EDI_REPA_DT <= '20261130'
 GROUP BY L.BOND_GRN_CD, L.CSTM_ITEM_CLS_CD,
          CASE WHEN EXISTS (SELECT 1 FROM WM0310C W WHERE W.COMP_CD = '01' AND W.GOOS_CD = L.GOOS_CD)
                 OR EXISTS (SELECT 1 FROM MA9301C R WHERE R.COMP_CD = '01' AND R.GOOS_CD = L.GOOS_CD AND R.GWP_YN = 'Y')
               THEN 'GWP' ELSE '상품' END,
          (SELECT MAX(M.GOOS_TYPE_CD) FROM MA0040C M WHERE M.COMP_CD = '01' AND M.GOOS_CD = L.GOOS_CD)
 ORDER BY 1, 2, 3, 4;



/* =====================================================================
   [Detail] SR_ItemCarryIn_D 양식 순서   — 못 찾은 항목은 NULL (직접 조인해서 채우기)
            양식 컬럼 뒤에 "참고" 컬럼 몇 개를 붙였음 (검토용, 적재 땐 제외)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),   -- 기준일 / 신고일자
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료
    -- 세관코드(CSTM_CD): 고객 확인 (05 → 010, 15·17 → 040)
    -- 과코드(DEPT_CD)  : 보세구역코드 4~5번째 자리로 추정 (01022006 → 22, 04021040 → 21)  ※ 확인 필요
    -- 일련번호 접두문자 : 미정 '?'
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),

-- ① HS세관재고 11/30 : 보세구역 × 장치장 × 상품·세관상품코드 (반입 − 반출 누계)
CSTM AS (
    SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD,
           L.CSTM_ITEM_CLS_CD,                                     -- 세관재고 자체의 환급구분 T/D/W (조회 결과로 확인)
           SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
      FROM WM0121L L, PRM P
     WHERE L.COMP_CD = P.COMP_CD
       AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
       AND L.EDI_REPA_DT <= P.BASE_DT
       -- AND L.SHED_CD = L.BOND_GRN_CD          -- 자기 장치장만 (통물 장치장 04077090/04077137 제외할 때)
     GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD
),

-- 환급코드 마스터 (상품 마이그에서 등록한 MA9301C) — 상품 하나에 T+W 처럼 여러 개 있을 수 있음
REFU AS (
    SELECT R.GOOS_CD, R.CSTM_GOODS_TYPE_CD, R.CSTM_GOOS_CD
      FROM MA9301C R
     WHERE R.COMP_CD = '01' AND R.USE_YN = 'Y'
),

-- ⓤ 미인도 (−) : 미인도반입면장 교환권 중 판매취소 아닌 교환권의 상품 판매수량 (STEP 4 와 같은 조건)
--    위치 = 반입면장 EDI 도착보세구역·도착장치장 (없으면 판매점 보세구역)
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD) ARRV_BOND, MAX(IM.ARRV_SHED_CD) ARRV_SHED
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                          /* 확정통보 */
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')               /* 미인도반입 / 국산미인도반입 / 외국인국산미인도반입 */
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
),
UDLV AS (
    SELECT NVL(U.ARRV_BOND, B.BOND_GRN_CD)                       WH_CODE,
           NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD))     SHED_CD,
           C.GOOS_CD,
           CASE WHEN SUBSTR(C.AGIG_CD, 6, 1) = '1' THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                ELSE 'D' END                                      CSTM_GOODS_TYPE_CD,
           G.GOOS_CD MST_GOOS_CD, G.GOOS_TYPE_CD,
           C.GOOS_QTY QTY
      FROM SA0100M A, SA0103D C, U_BILL U, PRM P, BOND B, MA0040C G
     WHERE A.COMP_CD = C.COMP_CD AND A.STOR_CD = C.STOR_CD AND A.SALE_DT = C.SALE_DT
       AND A.POS_NO = C.POS_NO AND A.RCPT_NO = C.RCPT_NO
       AND A.COMP_CD = U.COMP_CD AND A.STOR_CD = U.STOR_CD AND A.BILL_NO = U.BILL_NO
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                  -- 판매취소가 아닌것
                        WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
       AND B.STOR_CD (+) = A.STOR_CD
       AND G.COMP_CD (+) = C.COMP_CD AND G.GOOS_CD (+) = C.GOOS_CD
),
UDLV_SCOPED AS (                             -- STEP 1 에서는 본점 자기 장치장 분만 뺌 (통물 장치장 분은 STEP 2 에서 뺌)
    SELECT * FROM UDLV WHERE WH_CODE = '01022006' AND SHED_CD = '01022006'
),

-- ② 환급코드 먼저 반영 (행 단위)
--    환급구분 = 세관재고의 CSTM_ITEM_CLS_CD (T/D/W)
--    세관상품코드 = MA9301C 에서 상품코드 + 같은 환급구분 행
--    MA9301C 에 그 환급구분이 없는 W 는 상품 마이그 규칙으로 생성: (수입 5 / 국산 6) || SUBSTR(상품코드, 2)
TAGGED AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.HS_CD, C.QTY,
           C.GOOS_CD,
           C.CSTM_ITEM_CLS_CD                                      CSTM_GOODS_TYPE_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL
                     THEN DECODE(G.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(G.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN W.GOOS_CD IS NOT NULL THEN 'GWP' ELSE '상품' END GOOS_GWP,   -- [확인 4] 결과에 따라 GWP 제외
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL THEN 'W_RULE'   -- MA9301C 에 W 행 없음 → 규칙으로 생성
                WHEN G.GOOS_CD IS NULL THEN 'NO_MASTER'                                 -- 상품마스터에 없음 (구코드)
                ELSE 'NO_TYPE' END                                 MATCH_BY            -- 상품은 있으나 그 환급구분(T/D) 코드 없음
      FROM CSTM C
      LEFT JOIN MA0040C G  ON G.COMP_CD = '01' AND G.GOOS_CD = C.GOOS_CD
      LEFT JOIN REFU R     ON R.GOOS_CD = C.GOOS_CD
                          AND R.CSTM_GOODS_TYPE_CD = C.CSTM_ITEM_CLS_CD
      LEFT JOIN (SELECT DISTINCT GOOS_CD FROM WM0310C WHERE COMP_CD = '01') W   -- GWP 마스터
                           ON W.GOOS_CD = C.GOOS_CD
     -- WHERE W.GOOS_CD IS NULL                    -- ← [확인 4] 에서 D 가 GWP 로 나오면 주석 해제 (상품 기초에서 GWP 제외)
),

-- ②-1 세관재고(+) 와 미인도(−) 합치기 — 같은 환급코드 규칙으로 코드 맞춤
TAGGED_ALL AS (
    SELECT 'CSTM' SRC, T.BOND_GRN_CD, T.SHED_CD, T.HS_CD, T.QTY, T.GOOS_CD, T.CSTM_GOODS_TYPE_CD,
           T.NEW_CSTM_GOOS_CD, T.GOOS_GWP, T.MATCH_BY
      FROM TAGGED T
    UNION ALL
    SELECT 'UDLV', U.WH_CODE, U.SHED_CD, NULL, -U.QTY, U.GOOS_CD, U.CSTM_GOODS_TYPE_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN U.CSTM_GOODS_TYPE_CD = 'W' AND U.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(U.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(U.GOOS_CD, 2) END,
           '상품', NULL
      FROM UDLV_SCOPED U
      LEFT JOIN REFU R ON R.GOOS_CD = U.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = U.CSTM_GOODS_TYPE_CD
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드
--    (행 단위로는 음수인 코드가 있음 — 조회상 본점 W −26, T2 W −143 — 매핑 후 합치면 상쇄되는지가 핵심)
--    합쳐도 0 이하인 것은 신고 대상 아님 → [점검]에서 확인
AGG AS (
    SELECT T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD,
           MAX(T.GOOS_GWP) GOOS_GWP, MAX(T.MATCH_BY) MATCH_BY, MAX(T.HS_CD) HS_CD,
           SUM(T.QTY) QTY,                                                     -- 세관재고 − 미인도
           SUM(CASE WHEN T.SRC = 'CSTM' THEN T.QTY ELSE 0 END) Q_CSTM,
           SUM(CASE WHEN T.SRC = 'UDLV' THEN T.QTY ELSE 0 END) Q_UDLV
      FROM TAGGED_ALL T
     GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD
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
       X.MATCH_BY                                         AS REF_MATCH_BY,       -- MA9301C / W_RULE / NO_TYPE / NO_MASTER(구코드)
       X.GOOS_GWP                                         AS REF_GOOS_GWP,       -- 상품 / GWP
       X.Q_CSTM                                           AS REF_Q_CSTM,         -- HS세관재고
       X.Q_UDLV                                           AS REF_Q_UDLV          -- 미인도 (−, 음수로 표시)
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
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료
    -- 세관코드(CSTM_CD): 고객 확인 (05 → 010, 15·17 → 040)
    -- 과코드(DEPT_CD)  : 보세구역코드 4~5번째 자리로 추정 (01022006 → 22, 04021040 → 21)  ※ 확인 필요
    -- 일련번호 접두문자 : 미정 '?'
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),

-- ① HS세관재고 11/30 : 보세구역 × 장치장 × 상품·세관상품코드 (반입 − 반출 누계)
CSTM AS (
    SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD,
           L.CSTM_ITEM_CLS_CD,                                     -- 세관재고 자체의 환급구분 T/D/W (조회 결과로 확인)
           SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
      FROM WM0121L L, PRM P
     WHERE L.COMP_CD = P.COMP_CD
       AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
       AND L.EDI_REPA_DT <= P.BASE_DT
       -- AND L.SHED_CD = L.BOND_GRN_CD          -- 자기 장치장만 (통물 장치장 04077090/04077137 제외할 때)
     GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD
),

-- 환급코드 마스터 (상품 마이그에서 등록한 MA9301C) — 상품 하나에 T+W 처럼 여러 개 있을 수 있음
REFU AS (
    SELECT R.GOOS_CD, R.CSTM_GOODS_TYPE_CD, R.CSTM_GOOS_CD
      FROM MA9301C R
     WHERE R.COMP_CD = '01' AND R.USE_YN = 'Y'
),

-- ⓤ 미인도 (−) : 미인도반입면장 교환권 중 판매취소 아닌 교환권의 상품 판매수량 (STEP 4 와 같은 조건)
--    위치 = 반입면장 EDI 도착보세구역·도착장치장 (없으면 판매점 보세구역)
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD) ARRV_BOND, MAX(IM.ARRV_SHED_CD) ARRV_SHED
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                          /* 확정통보 */
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')               /* 미인도반입 / 국산미인도반입 / 외국인국산미인도반입 */
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
),
UDLV AS (
    SELECT NVL(U.ARRV_BOND, B.BOND_GRN_CD)                       WH_CODE,
           NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD))     SHED_CD,
           C.GOOS_CD,
           CASE WHEN SUBSTR(C.AGIG_CD, 6, 1) = '1' THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                ELSE 'D' END                                      CSTM_GOODS_TYPE_CD,
           G.GOOS_CD MST_GOOS_CD, G.GOOS_TYPE_CD,
           C.GOOS_QTY QTY
      FROM SA0100M A, SA0103D C, U_BILL U, PRM P, BOND B, MA0040C G
     WHERE A.COMP_CD = C.COMP_CD AND A.STOR_CD = C.STOR_CD AND A.SALE_DT = C.SALE_DT
       AND A.POS_NO = C.POS_NO AND A.RCPT_NO = C.RCPT_NO
       AND A.COMP_CD = U.COMP_CD AND A.STOR_CD = U.STOR_CD AND A.BILL_NO = U.BILL_NO
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                  -- 판매취소가 아닌것
                        WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
       AND B.STOR_CD (+) = A.STOR_CD
       AND G.COMP_CD (+) = C.COMP_CD AND G.GOOS_CD (+) = C.GOOS_CD
),
UDLV_SCOPED AS (                             -- STEP 1 에서는 본점 자기 장치장 분만 뺌 (통물 장치장 분은 STEP 2 에서 뺌)
    SELECT * FROM UDLV WHERE WH_CODE = '01022006' AND SHED_CD = '01022006'
),

-- ② 환급코드 먼저 반영 (행 단위)
--    환급구분 = 세관재고의 CSTM_ITEM_CLS_CD (T/D/W)
--    세관상품코드 = MA9301C 에서 상품코드 + 같은 환급구분 행
--    MA9301C 에 그 환급구분이 없는 W 는 상품 마이그 규칙으로 생성: (수입 5 / 국산 6) || SUBSTR(상품코드, 2)
TAGGED AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.HS_CD, C.QTY,
           C.GOOS_CD,
           C.CSTM_ITEM_CLS_CD                                      CSTM_GOODS_TYPE_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL
                     THEN DECODE(G.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(G.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN W.GOOS_CD IS NOT NULL THEN 'GWP' ELSE '상품' END GOOS_GWP,   -- [확인 4] 결과에 따라 GWP 제외
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL THEN 'W_RULE'   -- MA9301C 에 W 행 없음 → 규칙으로 생성
                WHEN G.GOOS_CD IS NULL THEN 'NO_MASTER'                                 -- 상품마스터에 없음 (구코드)
                ELSE 'NO_TYPE' END                                 MATCH_BY            -- 상품은 있으나 그 환급구분(T/D) 코드 없음
      FROM CSTM C
      LEFT JOIN MA0040C G  ON G.COMP_CD = '01' AND G.GOOS_CD = C.GOOS_CD
      LEFT JOIN REFU R     ON R.GOOS_CD = C.GOOS_CD
                          AND R.CSTM_GOODS_TYPE_CD = C.CSTM_ITEM_CLS_CD
      LEFT JOIN (SELECT DISTINCT GOOS_CD FROM WM0310C WHERE COMP_CD = '01') W   -- GWP 마스터
                           ON W.GOOS_CD = C.GOOS_CD
     -- WHERE W.GOOS_CD IS NULL                    -- ← [확인 4] 에서 D 가 GWP 로 나오면 주석 해제 (상품 기초에서 GWP 제외)
),

-- ②-1 세관재고(+) 와 미인도(−) 합치기 — 같은 환급코드 규칙으로 코드 맞춤
TAGGED_ALL AS (
    SELECT 'CSTM' SRC, T.BOND_GRN_CD, T.SHED_CD, T.HS_CD, T.QTY, T.GOOS_CD, T.CSTM_GOODS_TYPE_CD,
           T.NEW_CSTM_GOOS_CD, T.GOOS_GWP, T.MATCH_BY
      FROM TAGGED T
    UNION ALL
    SELECT 'UDLV', U.WH_CODE, U.SHED_CD, NULL, -U.QTY, U.GOOS_CD, U.CSTM_GOODS_TYPE_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN U.CSTM_GOODS_TYPE_CD = 'W' AND U.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(U.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(U.GOOS_CD, 2) END,
           '상품', NULL
      FROM UDLV_SCOPED U
      LEFT JOIN REFU R ON R.GOOS_CD = U.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = U.CSTM_GOODS_TYPE_CD
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드
--    (행 단위로는 음수인 코드가 있음 — 조회상 본점 W −26, T2 W −143 — 매핑 후 합치면 상쇄되는지가 핵심)
--    합쳐도 0 이하인 것은 신고 대상 아님 → [점검]에서 확인
AGG AS (
    SELECT T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD,
           MAX(T.GOOS_GWP) GOOS_GWP, MAX(T.MATCH_BY) MATCH_BY, MAX(T.HS_CD) HS_CD,
           SUM(T.QTY) QTY,                                                     -- 세관재고 − 미인도
           SUM(CASE WHEN T.SRC = 'CSTM' THEN T.QTY ELSE 0 END) Q_CSTM,
           SUM(CASE WHEN T.SRC = 'UDLV' THEN T.QTY ELSE 0 END) Q_UDLV
      FROM TAGGED_ALL T
     GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD
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
       SUM(X.QTY)                                         AS REF_QTY,
       SUM(X.Q_CSTM)                                      AS REF_Q_CSTM,
       SUM(X.Q_UDLV)                                      AS REF_Q_UDLV
  FROM DECL X
  CROSS JOIN PRM P
 GROUP BY X.DECLARATION_NO, X.BOND_GRN_CD, P.DECL_DT, X.SHED_CD, X.STOR_NM
 ORDER BY X.DECLARATION_NO;


/* =====================================================================
   [점검]
   ===================================================================== */
-- 점검 1) 구코드 목록 — 상품마스터(MA0040C)에 없는 세관재고 상품코드 (조회상 본점 42, T2 5)
--         → Detail 에서 REF_MATCH_BY = 'NO_MASTER' 로 표시됨, 처리 방법은 고객 확인
SELECT L.BOND_GRN_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.CSTM_ITEM_CLS_CD, MAX(L.HS_CD) HS_CD,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L
 WHERE L.COMP_CD = '01'
   AND L.BOND_GRN_CD IN ('01022006', '04021040', '04021041')
   AND L.EDI_REPA_DT <= '20261130'
   AND NOT EXISTS (SELECT 1 FROM MA0040C M WHERE M.COMP_CD = '01' AND M.GOOS_CD = L.GOOS_CD)
 GROUP BY L.BOND_GRN_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.CSTM_ITEM_CLS_CD
 ORDER BY 1, 2;

-- 점검 2) Detail 쿼리 결과 요약 — Detail 쿼리의 WITH ~ 마지막 SELECT 를 < > 자리에 넣어서
--   SELECT REF_STOR_NM, ITEM_TYPE, REF_MATCH_BY, COUNT(*) ROW_CNT, SUM(ITEM_QTY) QTY
--     FROM ( < Detail 쿼리 > )
--    GROUP BY REF_STOR_NM, ITEM_TYPE, REF_MATCH_BY ORDER BY 1, 2, 3;
--   - W_RULE    : MA9301C 에 W 코드가 없어 규칙으로 만든 것 → 상품 마이그 때 MA9301C 에 W 등록이 빠졌을 수 있음
--   - NO_TYPE   : 세관재고는 T 인데 MA9301C 는 D 만 있는 식 (상품구분 변경) → ITEM_CODE 공백, 확인 필요
--   - NO_MASTER : 구코드 → 점검 1

-- 점검 3) 환급구분을 반영해서 합쳐도 음수로 남는 것 (신고 제외됨) — 상쇄 안 되는 음수는 원인 확인
SELECT BOND_GRN_CD, SHED_CD, CSTM_ITEM_CLS_CD, GOOS_CD, SUM(QTY) QTY
  FROM (SELECT L.BOND_GRN_CD, L.SHED_CD, L.CSTM_ITEM_CLS_CD, L.GOOS_CD,
               NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0) QTY
          FROM WM0121L L
         WHERE L.COMP_CD = '01'
           AND L.BOND_GRN_CD IN ('01022006', '04021040', '04021041')
           AND L.EDI_REPA_DT <= '20261130')
 GROUP BY BOND_GRN_CD, SHED_CD, CSTM_ITEM_CLS_CD, GOOS_CD
HAVING SUM(QTY) < 0
 ORDER BY 1, 2, 3, 4;

-- 점검 4) "누계 = 재고" 검증 : WM0121L 처음~기준일 누계 vs 고객이 보는 WM0121S 그날 누적
--   ※ 11/30 데이터가 생기기 전엔 기준일을 20261120 처럼 이미 있는 날로 바꿔서 실행. DIFF 가 0 이면 누계 방식 확정
SELECT NVL(L.BOND_GRN_CD, S.BOND_GRN_CD) BOND_GRN_CD, NVL(L.SHED_CD, S.SHED_CD) SHED_CD,
       L.MIN_DT, L.QTY L_QTY, S.QTY S_QTY, NVL(L.QTY, 0) - NVL(S.QTY, 0) DIFF
  FROM (SELECT BOND_GRN_CD, SHED_CD, MIN(EDI_REPA_DT) MIN_DT,                 -- 이력 시작일
               SUM(NVL(CARI_QTY, 0) - NVL(TAKE_OUT_QTY, 0)) QTY
          FROM WM0121L
         WHERE COMP_CD = '01' AND BOND_GRN_CD IN ('01022006', '04021040', '04021041')
           AND EDI_REPA_DT <= '20261120'
         GROUP BY BOND_GRN_CD, SHED_CD) L
  FULL OUTER JOIN
       (SELECT BOND_GRN_CD, SHED_CD, SUM(ACUM_CARI_QTY - ACUM_TAKE_OUT_QTY) QTY
          FROM WM0121S
         WHERE COMP_CD = '01' AND BOND_GRN_CD IN ('01022006', '04021040', '04021041')
           AND EDI_REPA_DT = '20261120'
         GROUP BY BOND_GRN_CD, SHED_CD) S
    ON S.BOND_GRN_CD = L.BOND_GRN_CD AND S.SHED_CD = L.SHED_CD
 ORDER BY 1, 2;

-- Header 의 REF_QTY 를 보세구역·장치장별로 모으면 WM0121S 11/30 집계와 같아야 함 (단, 음수 제외분만큼 차이)
