/* =====================================================================
   06. C01 HS세관재고 (본점, T1-DF4, T2-DF4 상품) / C02 수불기말재고 (통물 상품, GWP)
       + 변환(환급분리 → 구코드) + 최종 집계
   ※ 원천 테이블 단위가 확정되지 않아 초안. 확인 사항:
     - WM0121S 에 GOOS_CD 가 있는지 (없으면 WM0121L 기준으로 산출)
     - 집계 프로시저(SP_WMCM_CSTM_RPT_LIST_5_SUM / _8)를 기준일까지 돌린 뒤 사용하는지
     - 환급 분리 기준 컬럼 (CSTM_ITEM_CLS_CD 가정)
     - 수불: 상품 WM0052L(일)/WM0053L(월), GWP WM0352L(일)/WM0353L(월). QTY 가 잔량인지 증감인지 아래 판별 쿼리로 확인
   바인드: :RUN_ID, :COMP_CD, :BASE_DT
   ===================================================================== */

/* ---------- C01: HS세관재고 = WM0121L 반입-반출 누계 (WM0121S 에는 GOOS_CD/HS_CD 없음 확인 → 대사용) ---------- */
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, BOND_GRN_CD, SHED_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, REFUND_CLS, QTY)
SELECT :RUN_ID, :BASE_DT, L.COMP_CD,
       MS.STOR_CD,                                   -- 보세구역 → 점 매핑 (매핑표 필요, 가칭 MIG_MAP_BOND)
       L.BOND_GRN_CD, L.SHED_CD, 'G', 'N', 'C01', +1,
       L.GOOS_CD,
       L.CSTM_ITEM_CLS_CD,                           -- 환급 분리 기준 (가정) — 집계 전에 보존
       SUM(NVL(L.CARI_QTY,0) - NVL(L.TAKE_OUT_QTY,0))
  FROM WM0121L L
  JOIN MIG_MAP_BOND MS                               -- TODO: (BOND_GRN_CD, SHED_CD) → STOR_CD 매핑표
    ON MS.BOND_GRN_CD = L.BOND_GRN_CD AND MS.SHED_CD = L.SHED_CD
 WHERE L.COMP_CD = :COMP_CD
   AND L.EDI_REPA_DT <= :BASE_DT                     -- 세관 수리일 기준 컷오프
   -- AND L.TOT_YN = 'Y'                             -- 집계유무 의미 확인
 GROUP BY L.COMP_CD, MS.STOR_CD, L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_ITEM_CLS_CD
HAVING SUM(NVL(L.CARI_QTY,0) - NVL(L.TAKE_OUT_QTY,0)) <> 0;

-- 세관재고 산출값 검증: 위 결과를 보세구역 단위로 합산 → WM0121S 누적(ACUM_CARI_QTY-ACUM_TAKE_OUT_QTY)과 비교
SELECT C.BOND_GRN_CD, C.SHED_CD, SUM(C.QTY) CALC_QTY, S.CSTM_QTY, SUM(C.QTY) - S.CSTM_QTY DIFF
  FROM MIG_STOC_COMP C
  LEFT JOIN (SELECT BOND_GRN_CD, SHED_CD, SUM(ACUM_CARI_QTY - ACUM_TAKE_OUT_QTY) CSTM_QTY
               FROM WM0121S
              WHERE COMP_CD = :COMP_CD
                AND EDI_REPA_DT = (SELECT MAX(EDI_REPA_DT) FROM WM0121S WHERE COMP_CD = :COMP_CD AND EDI_REPA_DT <= :BASE_DT)
              GROUP BY BOND_GRN_CD, SHED_CD) S
    ON S.BOND_GRN_CD = C.BOND_GRN_CD AND S.SHED_CD = C.SHED_CD
 WHERE C.MIG_RUN_ID = :RUN_ID AND C.COMP_TYPE = 'C01'
 GROUP BY C.BOND_GRN_CD, C.SHED_CD, S.CSTM_QTY;

/* ---------- C02: 수불재고 ----------
   상품: WM0052L(일수불) / WM0053L(월수불)    GWP: WM0352L(일수불) / WM0353L(월수불)
   대상: 통물 상품, 본점/통물 GWP(계산재고 베이스), T1·T2 GWP(수불재고 그대로)
   ※ QTY 의미에 따라 방식 A / B 중 하나 사용 → 먼저 [판별] 실행                                    */

/* [판별] 마감된 달 하나(:YMON, 예 '202610')로 점별 총량 비교
   - CHK_A 의 두 값이 같으면  → 일수불 QTY = 그날 잔량            → 방식 A
   - CHK_B 의 두 값이 같으면  → 월수불 = 월말 잔량, 일수불 = 증감  → 방식 B            */
WITH M AS (SELECT STOR_CD, SUM(QTY) Q FROM WM0053L WHERE COMP_CD = :COMP_CD AND YMON = :YMON GROUP BY STOR_CD),
     P AS (SELECT STOR_CD, SUM(QTY) Q FROM WM0053L WHERE COMP_CD = :COMP_CD
                                       AND YMON = TO_CHAR(ADD_MONTHS(TO_DATE(:YMON,'YYYYMM'),-1),'YYYYMM') GROUP BY STOR_CD),
     DL AS (SELECT STOR_CD, SUM(QTY) Q FROM WM0052L WHERE COMP_CD = :COMP_CD
                                        AND RD_DT = TO_CHAR(LAST_DAY(TO_DATE(:YMON,'YYYYMM')),'YYYYMMDD') GROUP BY STOR_CD),
     DS AS (SELECT STOR_CD, SUM(QTY) Q FROM WM0052L WHERE COMP_CD = :COMP_CD
                                        AND RD_DT LIKE :YMON || '%' GROUP BY STOR_CD)
SELECT M.STOR_CD,
       M.Q AS MONTH_QTY,
       DL.Q AS CHK_A_LASTDAY_QTY,                     -- 방식 A 이면 MONTH_QTY 와 같음
       NVL(P.Q,0) + NVL(DS.Q,0) AS CHK_B_PREV_PLUS_DAYS  -- 방식 B 이면 MONTH_QTY 와 같음
  FROM M LEFT JOIN P ON P.STOR_CD = M.STOR_CD
         LEFT JOIN DL ON DL.STOR_CD = M.STOR_CD
         LEFT JOIN DS ON DS.STOR_CD = M.STOR_CD
 ORDER BY 1;
-- GWP 도 같은 방법으로 WM0353L / WM0352L 비교

/* [방식 A] 일수불 QTY = 그날 잔량 → 기준일 행을 그대로 사용 (상품) */
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, REFUND_CLS, STOC_CLS_CD, FALT_CLS_CD, AGIG_CD, QTY, SRC_KEY)
SELECT :RUN_ID, :BASE_DT, S.COMP_CD, S.STOR_CD, S.CORN_CD, 'G',
       'N',                                           -- TODO: STOC_CLS_CD(WM014) 값별 정상/미인도 매핑
       'C02', +1,
       S.GOOS_CD, S.REFU_CLS_CD, S.STOC_CLS_CD, S.FALT_CLS_CD, S.AGIG_CD,
       S.QTY, 'WM0052L|' || S.RD_DT
  FROM WM0052L S
 WHERE S.COMP_CD = :COMP_CD
   AND S.RD_DT = :BASE_DT
   AND S.QTY <> 0;
-- ※ 잔량 방식이라도 "변동 있는 날만 행이 생기는" 구조면 기준일에 행이 없는 상품이 빠짐
--    → 그 경우 상품·코너별 RD_DT <= :BASE_DT 중 최신 행을 사용 (ROW_NUMBER() OVER (PARTITION BY ... ORDER BY RD_DT DESC))

/* [방식 B] 월수불 = 월말 잔량, 일수불 = 증감 → 전월말 + 당월 1일~기준일 (상품) */
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, REFUND_CLS, STOC_CLS_CD, FALT_CLS_CD, AGIG_CD, QTY, SRC_KEY)
SELECT :RUN_ID, :BASE_DT, COMP_CD, STOR_CD, CORN_CD, 'G', 'N', 'C02', +1,
       GOOS_CD, REFU_CLS_CD, STOC_CLS_CD, FALT_CLS_CD, AGIG_CD, SUM(QTY), 'PREV_MONTH+DAYS'
  FROM (SELECT COMP_CD, STOR_CD, CORN_CD, GOOS_CD, AGIG_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD, QTY
          FROM WM0053L
         WHERE COMP_CD = :COMP_CD
           AND YMON = TO_CHAR(ADD_MONTHS(TO_DATE(:BASE_DT,'YYYYMMDD'),-1),'YYYYMM')
        UNION ALL
        SELECT COMP_CD, STOR_CD, CORN_CD, GOOS_CD, AGIG_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD, QTY
          FROM WM0052L
         WHERE COMP_CD = :COMP_CD
           AND RD_DT BETWEEN SUBSTR(:BASE_DT,1,6) || '01' AND :BASE_DT)
 GROUP BY COMP_CD, STOR_CD, CORN_CD, GOOS_CD, AGIG_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD
HAVING SUM(QTY) <> 0;

/* GWP: 위 A 또는 B 와 같은 구조로 WM0352L / WM0353L 사용, ITEM_TYPE = 'W'
   (REFU_CLS_CD, FALT_CLS_CD 컬럼 없음 → NULL)                                                       */

-- C02 점검: 수불에 어떤 점/코너/구분값이 있는지 (통물·본점·T1·T2 포함 여부)
SELECT 'G' ITEM_TYPE, STOR_CD, CORN_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD,
       COUNT(*) ROW_CNT, COUNT(DISTINCT GOOS_CD) GOOS_CNT, SUM(QTY) QTY
  FROM WM0053L WHERE COMP_CD = :COMP_CD AND YMON = :YMON
 GROUP BY STOR_CD, CORN_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD
UNION ALL
SELECT 'W', STOR_CD, CORN_CD, STOC_CLS_CD, NULL, NULL,
       COUNT(*), COUNT(DISTINCT GOOS_CD), SUM(QTY)
  FROM WM0353L WHERE COMP_CD = :COMP_CD AND YMON = :YMON
 GROUP BY STOR_CD, CORN_CD, STOC_CLS_CD
 ORDER BY 1, 2, 3, 4;

-- GWP 매출(SA0109D)의 GOOS_CD 가 GWP 수불(WM0353L)에 있는지 → GWP 재고 키 확인
SELECT COUNT(DISTINCT G.GOOS_CD) SALE_GWP_GOOS,
       COUNT(DISTINCT CASE WHEN EXISTS (SELECT 1 FROM WM0353L W WHERE W.COMP_CD = G.COMP_CD AND W.GOOS_CD = G.GOOS_CD)
                           THEN G.GOOS_CD END) FOUND_IN_GWP_SUBUL
  FROM SA0109D G
 WHERE G.COMP_CD = :COMP_CD AND G.SALE_DT LIKE :YMON || '%';

/* ---------- 변환 1: 환급코드 분리 (집계 전, REFUND_CLS 보존 상태에서) ---------- */
UPDATE MIG_STOC_COMP C
   SET C.GOOS_CD = NVL((SELECT R.GOOS_CD_REF FROM MIG_MAP_REFUND R
                         WHERE R.GOOS_CD_ORG = C.GOOS_CD_ORG AND R.REFUND_CLS = C.REFUND_CLS),
                       C.GOOS_CD_ORG)
 WHERE C.MIG_RUN_ID = :RUN_ID;

/* ---------- 변환 2: 구코드 정리 ---------- */
UPDATE MIG_STOC_COMP C
   SET C.GOOS_CD = (SELECT G.NEW_GOOS_CD FROM MIG_MAP_GOOS G WHERE G.OLD_GOOS_CD = C.GOOS_CD)
 WHERE C.MIG_RUN_ID = :RUN_ID
   AND EXISTS (SELECT 1 FROM MIG_MAP_GOOS G WHERE G.OLD_GOOS_CD = C.GOOS_CD);

/* ---------- 최종 집계: 고객 규칙 매트릭스 적용 → 세관 신고 단위 ----------
   - 세관재고(C01)는 (보세구역, 장치장) 그대로, 나머지는 (재고점, 재고코너) → MIG_MAP_STOR 로 보세구역/장치장 결정
   - 규칙 (해석, 고객 확인 필요):
       자기 장치장(MAIN/T1/T2) 상품 = HS세관재고(C01)                       − 미인도(C05, 본점만)
       통물 장치장(LOGI)      상품 = 수불(C02) + 교환권(C03) − H재반입(C04) − 미인도(C05)
       GWP  본점·통물          = 수불 + 교환권 − H재반입 − 미인도 /  T1·T2 = 수불
       미인도(C05)는 정상재고에서 빼고(Z), 같은 수량을 교환권번호별로 Y(미인도물품재고반입)로 따로 적재  */
INSERT INTO MIG_BASE_STOC
      (MIG_RUN_ID, BASE_DT, COMP_CD, WH_CODE, SHED_CD, ITEM_TYPE, STOC_TYPE, CSTM_ITEM_TYPE, GOOS_CD, REGISTER_NO, QTY)
WITH MAPPED AS (
    SELECT C.COMP_TYPE, C.SIGN, C.QTY, C.COMP_CD, C.BASE_DT, C.ITEM_TYPE, C.GOOS_CD, C.REFUND_CLS, C.SRC_BILL_NO,
           B.SITE_GRP, B.BOND_GRN_CD AS WH_CODE, B.SHED_CD AS SHED
      FROM MIG_STOC_COMP C
      JOIN MIG_MAP_BOND B ON B.BOND_GRN_CD = C.BOND_GRN_CD AND B.SHED_CD = C.SHED_CD
     WHERE C.MIG_RUN_ID = :RUN_ID AND C.COMP_TYPE = 'C01'
    UNION ALL
    SELECT C.COMP_TYPE, C.SIGN, C.QTY, C.COMP_CD, C.BASE_DT, C.ITEM_TYPE, C.GOOS_CD, C.REFUND_CLS, C.SRC_BILL_NO,
           M.SITE_GRP, M.WH_CODE, M.SHED_CD
      FROM MIG_STOC_COMP C
      JOIN MIG_MAP_STOR M
        ON M.COMP_CD = C.COMP_CD AND M.STOR_CD = C.STOR_CD
       AND M.CORN_CD = (SELECT NVL(MAX(M2.CORN_CD), '*') FROM MIG_MAP_STOR M2     -- 코너 매핑 우선, 없으면 점 전체
                         WHERE M2.COMP_CD = C.COMP_CD AND M2.STOR_CD = C.STOR_CD AND M2.CORN_CD = C.CORN_CD)
     WHERE C.MIG_RUN_ID = :RUN_ID AND C.COMP_TYPE <> 'C01'
),
EXPANDED AS (   -- C05 는 정상(N)에서 차감 + 미인도(U)로 양수 적재
    SELECT X.*, 'N' AS STOC_TYPE, X.SIGN * X.QTY AS SQTY, '-' AS REGISTER_NO FROM MAPPED X
    UNION ALL
    SELECT X.*, 'U', X.QTY, X.SRC_BILL_NO FROM MAPPED X WHERE X.COMP_TYPE = 'C05'
)
SELECT :RUN_ID, E.BASE_DT, E.COMP_CD, E.WH_CODE, E.SHED, E.ITEM_TYPE, E.STOC_TYPE,
       COALESCE(I.CSTM_ITEM_TYPE, G.CSTM_ITEM_TYPE, '?'),     -- '?' 는 검증에서 0건이어야 함
       E.GOOS_CD, E.REGISTER_NO, SUM(E.SQTY)
  FROM EXPANDED E
  LEFT JOIN MIG_MAP_ITEM_CLS I
    ON I.SRC_TYPE = CASE WHEN E.COMP_TYPE = 'C01' THEN 'CSTM' ELSE 'REFU' END AND I.SRC_VAL = E.REFUND_CLS
  LEFT JOIN MIG_MAP_GOOS_ITEM_TYPE G ON G.GOOS_CD = E.GOOS_CD
 WHERE (   (E.ITEM_TYPE = 'G' AND E.STOC_TYPE = 'N' AND E.SITE_GRP IN ('MAIN','T1','T2') AND E.COMP_TYPE = 'C01')
        OR (E.ITEM_TYPE = 'G' AND E.STOC_TYPE = 'N' AND E.SITE_GRP = 'MAIN' AND E.COMP_TYPE = 'C05')
        OR (E.ITEM_TYPE = 'G' AND E.STOC_TYPE = 'N' AND E.SITE_GRP = 'LOGI' AND E.COMP_TYPE IN ('C02','C03','C04','C05'))
        OR (E.ITEM_TYPE = 'W' AND E.STOC_TYPE = 'N' AND E.SITE_GRP IN ('MAIN','LOGI') AND E.COMP_TYPE IN ('C02','C03','C04','C05'))  -- Q3
        OR (E.ITEM_TYPE = 'W' AND E.STOC_TYPE = 'N' AND E.SITE_GRP IN ('T1','T2') AND E.COMP_TYPE = 'C02')
        OR (E.STOC_TYPE = 'U' AND E.SITE_GRP IN ('MAIN','LOGI'))
       )
 GROUP BY E.BASE_DT, E.COMP_CD, E.WH_CODE, E.SHED, E.ITEM_TYPE, E.STOC_TYPE,
          COALESCE(I.CSTM_ITEM_TYPE, G.CSTM_ITEM_TYPE, '?'), E.GOOS_CD, E.REGISTER_NO
HAVING SUM(E.SQTY) <> 0;
