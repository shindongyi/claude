/* =====================================================================
   STEP 4. 상품 및 GWP 미인도 기초                                기준일 2026-11-30
   ---------------------------------------------------------------------
   고객 정리 : 본점 / 통물 = 미인도반입면장 교환권 중 판매취소 아닌 교환권의 판매수량 (−)
               T1-DF4 / T2-DF4 = 없음
   신고 양식 : 신고구분 Y (미인도물품재고반입), 품목마다 참조번호(register_no) = 교환권번호
   → 이 STEP 은 Y 신고분(양수)을 뽑음. 같은 수량(상품분)을 Z(정상재고)에서 뺌:
       본점 자기 장치장 분 → STEP 1,  통물 장치장 분 → STEP 2   (각 쿼리의 UDLV 블록, 조건 동일)

   - 미인도반입면장 : 보세운송(BO0110M) 면장구분 06 미인도반입 / 76 국산미인도반입 / 86 외국인국산미인도반입
                      + EDI(IFWM11M) 확정통보 G1, 삭제 제외, 11/30 까지
   - 위치 : 점·코너 매핑 대신 반입면장 EDI 의 도착보세구역(ARRV_BOND_RGN_CD)·도착장치장(ARRV_SHED_CD) 사용
            비어 있으면 판매점의 보세구역
   - 수량 : 상품 SA0103D.GOOS_QTY / GWP SA0109D.PMNT_QTY (판매취소 아닌 빌, 다른 날 취소 포함 제외)
   - 환급코드 : 상품 = 상품 마이그 규칙 (에이징 6번째 1 → W / 상품구분 1 → T / 그 외 D)
                GWP  = D (GWP 마이그에서 MA9301C 에 D 로 등록)
   - 테이블 생성 없음. [확인] → [Detail] → [Header] → [점검]
   ===================================================================== */


/* ---------------------------------------------------------------------
   [확인 1] 미인도반입면장 빌이 어디로(도착 보세구역·장치장) 들어갔고, 지금 빌 상태가 뭔지
     - 빌상태(BO015) 04 고객인도 가 있으면 → 반입 후 다시 인도된 것 (재고 아님 → 제외할지 확인)
     - 08 판매취소 는 판매취소 판정으로 빠짐
   --------------------------------------------------------------------- */
SELECT IM.ARRV_BOND_RGN_CD, IM.ARRV_SHED_CD, BD.STOR_CD,
       SA.BILL_PROC_CLS_CD, SA.GOOS_LOC_CLS_CD,
       COUNT(DISTINCT BD.BILL_NO) BILL_CNT
  FROM BO0110M BM, BO0110D BD, IFWM11M IM, SA0100M SA
 WHERE BM.COMP_CD = BD.COMP_CD
   AND BM.STOR_CD = BD.STOR_CD
   AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
   AND BM.COMP_CD = IM.COMP_CD
   AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
   AND IM.EDI_DOC_STAT_CD = 'G1'
   AND BM.PMIT_CLS_CD IN ('06', '76', '86')
   AND NVL(BM.DEL_YN, 'N') = 'N'
   AND IM.EDI_RPT_DT <= '20261130'
   AND SA.COMP_CD = BD.COMP_CD AND SA.STOR_CD = BD.STOR_CD AND SA.BILL_NO = BD.BILL_NO
   AND SA.SALE_TYPE_CD = '1'
 GROUP BY IM.ARRV_BOND_RGN_CD, IM.ARRV_SHED_CD, BD.STOR_CD, SA.BILL_PROC_CLS_CD, SA.GOOS_LOC_CLS_CD
 ORDER BY 1, 2, 3, 4, 5;

/* ---------------------------------------------------------------------
   [확인 2] 같은 빌이 미인도반입면장 여러 건에 걸린 경우 (재반입 반복 → 도착지가 여러 개일 수 있음)
   --------------------------------------------------------------------- */
SELECT PMIT_CNT, COUNT(*) BILL_CNT
  FROM (SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO, COUNT(DISTINCT BM.BOND_TRAN_MNGE_NO) PMIT_CNT
          FROM BO0110M BM, BO0110D BD, IFWM11M IM
         WHERE BM.COMP_CD = BD.COMP_CD AND BM.STOR_CD = BD.STOR_CD AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
           AND BM.COMP_CD = IM.COMP_CD AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
           AND IM.EDI_DOC_STAT_CD = 'G1' AND BM.PMIT_CLS_CD IN ('06', '76', '86')
           AND NVL(BM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= '20261130'
         GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO)
 GROUP BY PMIT_CNT
 ORDER BY 1;



/* =====================================================================
   [Detail] SR_ItemCarryIn_D 양식 순서   — 못 찾은 항목은 NULL
            상품: MA0040C / MA0030C / MA3118I,   GWP: WM0310C / WM0314C(상품속성) / WM0310I(추가정보)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),

-- ① 미인도반입면장 교환권 빌  ← 고객 쿼리 "3." + 도착 보세구역·장치장
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD)              ARRV_BOND,     -- 도착보세구역
           MAX(IM.ARRV_SHED_CD)                  ARRV_SHED,     -- 도착장치장
           COUNT(DISTINCT BM.BOND_TRAN_MNGE_NO)  PMIT_CNT       -- 2 이상이면 [확인 2]
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                         /* 확정통보 */
       /* 06:미인도반입면장, 76:국산미인도반입면장, 86:외국인국산미인도반입면장 */
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO               -- 카톤별 행 중복 제거
),

-- ② 판매취소 아닌 빌
VALID_BILL AS (
    SELECT A.COMP_CD, A.STOR_CD, A.SALE_DT, A.POS_NO, A.RCPT_NO, A.BILL_NO, A.BILL_PROC_CLS_CD,
           U.ARRV_BOND, U.ARRV_SHED, U.PMIT_CNT
      FROM SA0100M A, U_BILL U, PRM P
     WHERE A.COMP_CD = U.COMP_CD
       AND A.STOR_CD = U.STOR_CD
       AND A.BILL_NO = U.BILL_NO
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       -- 판매취소가 아닌것 (다른 날 취소 포함)
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
       -- AND A.BILL_PROC_CLS_CD <> '04'                    -- ← [확인 1] 에서 고객인도(04)가 나오면 제외할지 결정
),

-- ③ 판매수량 : 상품 + GWP
LINES AS (
    SELECT 'G' KIND, V.*, C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY     -- 상품
      FROM VALID_BILL V, SA0103D C
     WHERE C.COMP_CD = V.COMP_CD AND C.STOR_CD = V.STOR_CD AND C.SALE_DT = V.SALE_DT
       AND C.POS_NO = V.POS_NO AND C.RCPT_NO = V.RCPT_NO
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W' KIND, V.*, G.GOOS_CD, NULL, G.PMNT_QTY               -- GWP
      FROM VALID_BILL V, SA0109D G
     WHERE G.COMP_CD = V.COMP_CD AND G.STOR_CD = V.STOR_CD AND G.SALE_DT = V.SALE_DT
       AND G.POS_NO = V.POS_NO AND G.RCPT_NO = V.RCPT_NO
),

-- ④ 위치 + 환급코드
TAGGED AS (
    SELECT L.KIND, L.BILL_NO, L.GOOS_CD, L.QTY, L.BILL_PROC_CLS_CD, L.PMIT_CNT,
           NVL(L.ARRV_BOND, B.BOND_GRN_CD)                        WH_CODE,     -- 도착보세구역, 없으면 판매점 보세구역
           NVL(L.ARRV_SHED, NVL(L.ARRV_BOND, B.BOND_GRN_CD))      SHED_CD,     -- 도착장치장, 없으면 보세구역 자기 장치장
           CASE WHEN L.KIND = 'W'                     THEN 'D'                 -- GWP
                WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1'    THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'             THEN 'T'
                ELSE 'D' END                                       CSTM_GOODS_TYPE_CD,
           G.GOOS_CD MST_GOOS_CD, G.GOOS_TYPE_CD
      FROM LINES L
      LEFT JOIN BOND B     ON B.STOR_CD = L.STOR_CD
      LEFT JOIN MA0040C G  ON L.KIND = 'G' AND G.COMP_CD = '01' AND G.GOOS_CD = L.GOOS_CD
),
CODED AS (
    SELECT T.*,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN T.KIND = 'W' THEN T.GOOS_CD                                          -- GWP 는 상품코드 그대로
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN T.KIND = 'W' THEN 'GWP_CD'
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                ELSE 'NO_TYPE' END                                 MATCH_BY
      FROM TAGGED T
      LEFT JOIN MA9301C R ON R.COMP_CD = '01' AND R.USE_YN = 'Y'
                         AND R.GOOS_CD = T.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
     -- 본점 / 통물만 (T1·T2 자기 장치장은 "없음")
     WHERE T.WH_CODE = '01022006'
        OR T.SHED_CD IN ('04077090', '04077137')
),

-- ⑤ 집계 : 보세구역 × 장치장 × 교환권 × 환급구분 × 세관상품코드
AGG AS (
    SELECT C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY,
           MAX(C.BILL_PROC_CLS_CD) BILL_PROC_CLS_CD, MAX(C.PMIT_CNT) PMIT_CNT,
           SUM(C.QTY) QTY
      FROM CODED C
     GROUP BY C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY
    HAVING SUM(C.QTY) > 0
),

-- ⑥ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.WH_CODE, A.SHED_CD
                              ORDER BY A.BILL_NO, A.KIND, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '4'(미인도) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.WH_CODE || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '4' || LPAD(DENSE_RANK() OVER (PARTITION BY N.WH_CODE
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      LEFT JOIN BOND D ON D.BOND_GRN_CD = N.WH_CODE
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                        AS DECLARATION_NO,     --  1 신고번호
       X.WH_CODE                                               AS WH_CODE,            --  2 신고지점
       'DLG'                                                   AS DOC_TYPE,           --  3 문서구분
       X.DOC_SEQ                                               AS DOC_SEQ,            --  4 품목일련번호
       NULL                                                    AS RAMEND_TYPE,        --  5 란정정구분
       X.CSTM_GOODS_TYPE_CD                                    AS ITEM_TYPE,          --  6 물품구분 T/D/W
       CASE X.KIND WHEN 'W' THEN WP.HS_CD END                  AS HS_CODE,            --  7 HS코드 (GWP: WM0314C / 상품: 공백)
       X.NEW_CSTM_GOOS_CD                                      AS ITEM_CODE,          --  8 세관신고 상품코드
       CASE X.KIND WHEN 'W' THEN WP.CSTM_GOOS_NM                                       --  9 품명 (GWP: 세관상품명)
                   ELSE B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM END
                                                               AS ITEM_NAME,
       NULL                                                    AS ITEM_NORM,          -- 10 규격
       X.QTY                                                   AS ITEM_QTY,           -- 11 수량
       CASE X.KIND WHEN 'W' THEN 0 END                         AS ITEM_COST,          -- 12 단가(미화) GWP 0
       CASE X.KIND WHEN 'W' THEN 0 END                         AS ITEM_AMOUNT,        -- 13 금액
       CASE X.KIND WHEN 'W' THEN WP.GOOS_CAPA ELSE V.GOOS_CAPA END AS CAPACITY,       -- 14 용량
       CASE X.KIND WHEN 'W' THEN WM.BRAN_CD   ELSE M.BRAN_CD   END AS BRAND_CODE,     -- 15 브랜드코드
       CASE X.KIND WHEN 'W' THEN WB.BRAN_NM   ELSE B.BRAN_NM   END AS BRAND_NAME,     -- 16 브랜드명
       CASE X.KIND WHEN 'W' THEN WP.SIZE_UNIT_CD END           AS UNIT_CODE,          -- 17 용량단위 (GWP: 71 ML / 73 GR)
       CASE X.KIND WHEN 'W' THEN WI.MNGE_LVL_CD END            AS GWP_PRODUCT_GRADE,  -- 18 GWP물품등급 (관리등급, 확인)
       X.BILL_NO                                               AS REGISTER_NO,        -- 19 참조번호 = 교환권번호 (빌번호, 확인)
       CASE X.KIND WHEN 'W' THEN 0 END                         AS ITEM_COST_KRW,      -- 20 단가(원화)
       NULL                                                    AS QTY_UNIT_CODE,      -- 21 수량단위
       ----------------------------------------------- 참고 (적재 제외, 4개 STEP 공통 순서)
       X.STOR_NM                                               AS REF_STOR_NM,
       X.SHED_CD                                               AS REF_SHED_CD,
       NULL                                                    AS REF_SITE,
       X.GOOS_CD                                               AS REF_GOOS_CD,
       DECODE(X.KIND, 'G', '상품', 'GWP')                        AS REF_GOOS_GWP,
       X.MATCH_BY                                              AS REF_MATCH_BY,
       CASE X.KIND WHEN 'W' THEN WP.REF_NO ELSE M.REF_NO END   AS REF_REF_NO,
       X.BILL_PROC_CLS_CD                                      AS REF_BILL_STAT,
       X.PMIT_CNT                                              AS REF_PMIT_CNT,
       NULL                                                    AS REF_Q_CSTM,
       NULL                                                    AS REF_Q_SUBUL,
       NULL                                                    AS REF_Q_EXCH,
       NULL                                                    AS REF_Q_HREENT,
       NULL                                                    AS REF_Q_UDLV
  FROM DECL X
  LEFT JOIN MA0040C M  ON X.KIND = 'G' AND M.COMP_CD = '01' AND M.GOOS_CD = X.GOOS_CD    -- 상품마스터
  LEFT JOIN MA0030C B  ON B.COMP_CD = M.COMP_CD AND B.BRAN_CD = M.BRAN_CD               -- 브랜드
  LEFT JOIN MA3118I V  ON X.KIND = 'G' AND V.COMP_CD = '01' AND V.GOOS_CD = X.GOOS_CD    -- 상품용량
  LEFT JOIN WM0310C WM ON X.KIND = 'W' AND WM.COMP_CD = '01' AND WM.GOOS_CD = X.GOOS_CD  -- GWP 기본
  LEFT JOIN MA0030C WB ON WB.COMP_CD = WM.COMP_CD AND WB.BRAN_CD = WM.BRAN_CD           -- GWP 브랜드
  LEFT JOIN WM0314C WP ON X.KIND = 'W' AND WP.COMP_CD = '01' AND WP.GOOS_CD = X.GOOS_CD  -- GWP 상품속성
  LEFT JOIN WM0310I WI ON X.KIND = 'W' AND WI.COMP_CD = '01' AND WI.GOOS_CD = X.GOOS_CD  -- GWP 추가정보
 ORDER BY X.DECLARATION_NO, X.DOC_SEQ;



/* =====================================================================
   [Header] SR_ItemCarryIn_H 양식 순서   — 신고서마다 1행 (Detail 과 같은 WITH)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),

-- ① 미인도반입면장 교환권 빌  ← 고객 쿼리 "3." + 도착 보세구역·장치장
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD)              ARRV_BOND,     -- 도착보세구역
           MAX(IM.ARRV_SHED_CD)                  ARRV_SHED,     -- 도착장치장
           COUNT(DISTINCT BM.BOND_TRAN_MNGE_NO)  PMIT_CNT       -- 2 이상이면 [확인 2]
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                         /* 확정통보 */
       /* 06:미인도반입면장, 76:국산미인도반입면장, 86:외국인국산미인도반입면장 */
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO               -- 카톤별 행 중복 제거
),

-- ② 판매취소 아닌 빌
VALID_BILL AS (
    SELECT A.COMP_CD, A.STOR_CD, A.SALE_DT, A.POS_NO, A.RCPT_NO, A.BILL_NO, A.BILL_PROC_CLS_CD,
           U.ARRV_BOND, U.ARRV_SHED, U.PMIT_CNT
      FROM SA0100M A, U_BILL U, PRM P
     WHERE A.COMP_CD = U.COMP_CD
       AND A.STOR_CD = U.STOR_CD
       AND A.BILL_NO = U.BILL_NO
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       -- 판매취소가 아닌것 (다른 날 취소 포함)
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
       -- AND A.BILL_PROC_CLS_CD <> '04'                    -- ← [확인 1] 에서 고객인도(04)가 나오면 제외할지 결정
),

-- ③ 판매수량 : 상품 + GWP
LINES AS (
    SELECT 'G' KIND, V.*, C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY     -- 상품
      FROM VALID_BILL V, SA0103D C
     WHERE C.COMP_CD = V.COMP_CD AND C.STOR_CD = V.STOR_CD AND C.SALE_DT = V.SALE_DT
       AND C.POS_NO = V.POS_NO AND C.RCPT_NO = V.RCPT_NO
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W' KIND, V.*, G.GOOS_CD, NULL, G.PMNT_QTY               -- GWP
      FROM VALID_BILL V, SA0109D G
     WHERE G.COMP_CD = V.COMP_CD AND G.STOR_CD = V.STOR_CD AND G.SALE_DT = V.SALE_DT
       AND G.POS_NO = V.POS_NO AND G.RCPT_NO = V.RCPT_NO
),

-- ④ 위치 + 환급코드
TAGGED AS (
    SELECT L.KIND, L.BILL_NO, L.GOOS_CD, L.QTY, L.BILL_PROC_CLS_CD, L.PMIT_CNT,
           NVL(L.ARRV_BOND, B.BOND_GRN_CD)                        WH_CODE,     -- 도착보세구역, 없으면 판매점 보세구역
           NVL(L.ARRV_SHED, NVL(L.ARRV_BOND, B.BOND_GRN_CD))      SHED_CD,     -- 도착장치장, 없으면 보세구역 자기 장치장
           CASE WHEN L.KIND = 'W'                     THEN 'D'                 -- GWP
                WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1'    THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'             THEN 'T'
                ELSE 'D' END                                       CSTM_GOODS_TYPE_CD,
           G.GOOS_CD MST_GOOS_CD, G.GOOS_TYPE_CD
      FROM LINES L
      LEFT JOIN BOND B     ON B.STOR_CD = L.STOR_CD
      LEFT JOIN MA0040C G  ON L.KIND = 'G' AND G.COMP_CD = '01' AND G.GOOS_CD = L.GOOS_CD
),
CODED AS (
    SELECT T.*,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN T.KIND = 'W' THEN T.GOOS_CD                                          -- GWP 는 상품코드 그대로
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN T.KIND = 'W' THEN 'GWP_CD'
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                ELSE 'NO_TYPE' END                                 MATCH_BY
      FROM TAGGED T
      LEFT JOIN MA9301C R ON R.COMP_CD = '01' AND R.USE_YN = 'Y'
                         AND R.GOOS_CD = T.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
     -- 본점 / 통물만 (T1·T2 자기 장치장은 "없음")
     WHERE T.WH_CODE = '01022006'
        OR T.SHED_CD IN ('04077090', '04077137')
),

-- ⑤ 집계 : 보세구역 × 장치장 × 교환권 × 환급구분 × 세관상품코드
AGG AS (
    SELECT C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY,
           MAX(C.BILL_PROC_CLS_CD) BILL_PROC_CLS_CD, MAX(C.PMIT_CNT) PMIT_CNT,
           SUM(C.QTY) QTY
      FROM CODED C
     GROUP BY C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY
    HAVING SUM(C.QTY) > 0
),

-- ⑥ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.WH_CODE, A.SHED_CD
                              ORDER BY A.BILL_NO, A.KIND, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '4'(미인도) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.WH_CODE || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '4' || LPAD(DENSE_RANK() OVER (PARTITION BY N.WH_CODE
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      LEFT JOIN BOND D ON D.BOND_GRN_CD = N.WH_CODE
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                        AS DECLARATION_NO,        --  1 신고번호
       X.WH_CODE                                               AS WH_CODE,               --  2 신고지점
       'DLG'                                                   AS DOC_TYPE,              --  3 문서구분
       P.DECL_DT                                               AS DECLARATION_DATE,      --  4 신고일자
       NULL                                                    AS AMEND_TYPE,            --  5 정정구분
       CASE WHEN X.SHED_CD = X.WH_CODE THEN NULL
            ELSE X.SHED_CD END                                 AS CARRYIN_LOC,           --  6 반입장치장소 (통물이면 값)
       NULL                                                    AS REFERENCE_NO,          --  7 근거번호
       'Y'                                                     AS DECLARATION_TYPE,      --  8 Y 미인도물품재고반입
       'A1'                                                    AS STATUS,                --  9 A1 생성
       SYSDATE                                                 AS C_DATETIME,            -- 10 생성일시
       NULL                                                    AS INTERNATIONAL_MAIL_YN, -- 11 국제우편여부
       ----------------------------------------------- 참고 (적재 제외, 4개 STEP 공통 순서)
       X.STOR_NM                                               AS REF_STOR_NM,
       NULL                                                    AS REF_SITE,
       COUNT(*)                                                AS REF_ITEM_CNT,
       COUNT(DISTINCT X.BILL_NO)                               AS REF_BILL_CNT,
       SUM(X.QTY)                                              AS REF_QTY,
       SUM(CASE X.KIND WHEN 'G' THEN X.QTY ELSE 0 END)         AS REF_QTY_GOODS,
       SUM(CASE X.KIND WHEN 'W' THEN X.QTY ELSE 0 END)         AS REF_QTY_GWP,
       NULL                                                    AS REF_Q_CSTM,
       NULL                                                    AS REF_Q_SUBUL,
       NULL                                                    AS REF_Q_EXCH,
       NULL                                                    AS REF_Q_HREENT,
       NULL                                                    AS REF_Q_UDLV
  FROM DECL X
  CROSS JOIN PRM P
 GROUP BY X.DECLARATION_NO, X.WH_CODE, P.DECL_DT, X.SHED_CD, X.STOR_NM
 ORDER BY X.DECLARATION_NO;



/* =====================================================================
   [점검]
   ===================================================================== */
-- 점검 1) 본점·통물이 아니라서 빠진 것 (T1·T2 자기 장치장 등) — Detail 의 CODED 블록 WHERE 를 반대로 바꿔서 확인
--         고객 정리상 "T1·T2 없음" 이 맞는지 수량으로 확인

-- 점검 2) STEP 1·2 의 정상재고(Z)에서 빼야 할 수량 = 이 STEP 의 보세구역·장치장·환급구분·세관상품코드별 합계
--         Detail 결과를 아래처럼 묶으면 됨 (STEP 1·2 연결은 고객 확인 후)
--   SELECT WH_CODE, REF_SHED_CD, ITEM_TYPE, ITEM_CODE, SUM(ITEM_QTY) UDLV_QTY
--     FROM ( < Detail 쿼리 > )
--    GROUP BY WH_CODE, REF_SHED_CD, ITEM_TYPE, ITEM_CODE;

-- 점검 3) "미인도 − " 가 맞는 전제 확인 : 미인도반입 물건이 세관재고(WM0121L)에 반입으로 다시 잡혔는지
--         (반입으로 잡혔으면 Z 에서 빼고 Y 로 신고하는 게 맞음 / 안 잡혔으면 빼면 이중 차감)
SELECT CASE WHEN EXISTS (SELECT 1 FROM WM0121L L
                          WHERE L.COMP_CD = U.COMP_CD AND L.BILL_NO = U.BILL_NO AND NVL(L.CARI_QTY, 0) > 0)
            THEN '세관재고 반입 있음' ELSE '세관재고 반입 없음' END AS CARI_IN_CSTM,
       COUNT(*) BILL_CNT
  FROM (SELECT DISTINCT BD.COMP_CD, BD.BILL_NO
          FROM BO0110M BM, BO0110D BD, IFWM11M IM
         WHERE BM.COMP_CD = BD.COMP_CD AND BM.STOR_CD = BD.STOR_CD AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
           AND BM.COMP_CD = IM.COMP_CD AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
           AND IM.EDI_DOC_STAT_CD = 'G1' AND BM.PMIT_CLS_CD IN ('06', '76', '86')
           AND NVL(BM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= '20261130') U
 GROUP BY CASE WHEN EXISTS (SELECT 1 FROM WM0121L L
                             WHERE L.COMP_CD = U.COMP_CD AND L.BILL_NO = U.BILL_NO AND NVL(L.CARI_QTY, 0) > 0)
               THEN '세관재고 반입 있음' ELSE '세관재고 반입 없음' END;

