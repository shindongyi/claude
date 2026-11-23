/* =====================================================================
   STEP 3. GWP 기초                                                기준일 2026-11-30
   ---------------------------------------------------------------------
   본점 / 통물      : 계산재고 = GWP 수불 기말재고 (11월 월수불 WM0353L)
                                + 교환권 (매출/통물창고 00·02, 매출/통물미래보세 00·12, 면장등록/통물미래보세 01·12)
                                − H신고 재반입면장 교환권 중 판매취소 아닌 것의 판매수량
                                − 미인도반입면장 교환권 중 판매취소 아닌 것의 판매수량 (Y 신고는 STEP 4)
   T1-DF4 / T2-DF4  : 수불재고 (WM0353L 그대로)

   - 위치 : 수불·교환권·H재반입은 (재고)점·코너 → 통물 코너(TONG)면 통물 장치장, 아니면 그 점 자기 장치장
            미인도는 반입면장 EDI 도착보세구역·도착장치장 (STEP 4 와 동일)
   - 통물 = 계산재고는 어느 점(05/15/17) 밑의 통물 코너든 적용, T1·T2 자기 장치장만 수불재고 그대로
   - GWP : 환급구분 D, 세관신고 상품코드 = MA9301C(D) 없으면 상품코드, 단가 0
           품명·HS·용량·단위 = WM0314C(상품속성), 브랜드 = WM0310C + MA0030C, 등급 = WM0310I.MNGE_LVL_CD
   - 신고번호 케이스 자리 '3'
   - 빌상태·상품위치는 현재 상태 값 → 12/1 영업 시작 전에 실행
   ===================================================================== */


/* [확인] GWP 월수불이 점·코너별로 어떻게 있는지 (11월 마감 전이면 '202610') */
SELECT S.STOR_CD, S.CORN_CD, COUNT(DISTINCT S.GOOS_CD) GOOS_CNT, SUM(S.QTY) QTY
  FROM WM0353L S
 WHERE S.COMP_CD = '01' AND S.YMON = '202610' AND S.STOR_CD IN ('05', '15', '17')
 GROUP BY S.STOR_CD, S.CORN_CD
 ORDER BY 1, 2;



/* =====================================================================
   [Detail] SR_ItemCarryIn_D 양식 순서   — 못 찾은 항목은 NULL
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, 'MAIN' SITE, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         'T1',        '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         'T2',        '04021041',             '040',          '21',         '?'            FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장 (STEP 2 와 같은 값으로)
    SELECT '961' CORN_CD, '????????' SHED_CD FROM DUAL UNION ALL     -- 예) 04077090 제2 통합물류센터 ?
    SELECT '965',         '????????'         FROM DUAL               -- 예) 04077137 은산 통합물류창고 ?
),

-- 판매취소 아닌 GWP 매출 라인  ← 고객 쿼리 "1. 매출조회 기본" (GWP 는 SA0109D)
SALE AS (
    SELECT A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(G.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD,
           NVL(G.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,
           G.GOOS_CD, G.PMNT_QTY QTY
      FROM SA0100M A, SA0109D G, PRM P
     WHERE A.COMP_CD = G.COMP_CD
       AND A.STOR_CD = G.STOR_CD
       AND A.SALE_DT = G.SALE_DT
       AND A.POS_NO  = G.POS_NO
       AND A.RCPT_NO = G.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                       -- 판매취소가 아닌것 (다른 날 취소 포함)
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- H신고 재반입면장 교환권 빌  ← 고객 쿼리 "2." (STEP 2 와 동일)
H_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'
       AND BM.COMP_CD = MD.COMP_CD
       AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
       AND MD.WRK_MDUL_CD = 'WM'
       AND MD.COMM_CTG_CD = 'WM038'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND IM.EDI_RPT_DT <= P.BASE_DT
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK, IFWM12M IM, PRM P
     WHERE MK.COMP_CD = IM.COMP_CD
       AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_CLS_CD = '5KP'
       AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')
       AND IM.EDI_DOC_STAT_CD = 'F1'
       AND IM.EDI_RPT_DT <= P.BASE_DT
),

-- 미인도반입면장 교환권 빌 + 도착 보세구역·장치장  ← 고객 쿼리 "3." (STEP 4 와 동일)
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD) ARRV_BOND, MAX(IM.ARRV_SHED_CD) ARRV_SHED
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
),

-- ① 구성요소 → 보세구역·장치장·구분(SITE) 붙이기
COMP AS (
    -- GWP 수불 기말재고 (05·15·17 전 코너)
    SELECT 'SUBUL' SRC, B.BOND_GRN_CD WH_CODE,
           NVL(T.SHED_CD, B.BOND_GRN_CD) SHED_CD,
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END SITE,
           S.GOOS_CD, S.QTY
      FROM WM0353L S
      JOIN PRM P       ON S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON
      JOIN BOND B      ON B.STOR_CD = S.STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = S.CORN_CD
    UNION ALL
    -- 교환권 (+)
    SELECT 'EXCH', B.BOND_GRN_CD, NVL(T.SHED_CD, B.BOND_GRN_CD),
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END,
           X.GOOS_CD, X.QTY
      FROM SALE X
      JOIN BOND B      ON B.STOR_CD = X.STOC_STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = X.STOC_CORN_CD
     WHERE (X.BILL_PROC_CLS_CD, X.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
    UNION ALL
    -- H신고 재반입 (−)
    SELECT 'HREENT', B.BOND_GRN_CD, NVL(T.SHED_CD, B.BOND_GRN_CD),
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END,
           X.GOOS_CD, -X.QTY
      FROM SALE X
      JOIN BOND B      ON B.STOR_CD = X.STOC_STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = X.STOC_CORN_CD
     WHERE (X.COMP_CD, X.STOR_CD, X.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
    UNION ALL
    -- 미인도 (−) : 도착 보세구역·장치장
    SELECT 'UDLV', NVL(U.ARRV_BOND, B.BOND_GRN_CD), NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD)),
           CASE WHEN NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD)) IN ('04077090', '04077137') THEN 'LOGI'
                WHEN NVL(U.ARRV_BOND, B.BOND_GRN_CD) = '01022006' THEN 'MAIN'
                ELSE 'T1T2' END,
           X.GOOS_CD, -X.QTY
      FROM SALE X
      JOIN U_BILL U    ON U.COMP_CD = X.COMP_CD AND U.STOR_CD = X.STOR_CD AND U.BILL_NO = X.BILL_NO
      LEFT JOIN BOND B ON B.STOR_CD = X.STOR_CD
),

-- ② 규칙 적용 : 본점·통물 = 수불 + 교환권 − H재반입 − 미인도 / T1·T2 = 수불만
RULED AS (
    SELECT C.*
      FROM COMP C
     WHERE C.SITE IN ('MAIN', 'LOGI')
        OR (C.SITE IN ('T1', 'T2') AND C.SRC = 'SUBUL')
),

-- ③ 집계 : 보세구역 × 장치장 × 상품 (환급구분 D, 세관상품코드)
AGG AS (
    SELECT R.WH_CODE, R.SHED_CD, R.GOOS_CD,
           'D'                                                      CSTM_GOODS_TYPE_CD,
           NVL(MAX(M9.CSTM_GOOS_CD), R.GOOS_CD)                     NEW_CSTM_GOOS_CD,
           MAX(R.SITE)                                              SITE,
           SUM(R.QTY)                                               QTY,
           SUM(CASE WHEN R.SRC = 'SUBUL'  THEN R.QTY ELSE 0 END)    Q_SUBUL,
           SUM(CASE WHEN R.SRC = 'EXCH'   THEN R.QTY ELSE 0 END)    Q_EXCH,
           SUM(CASE WHEN R.SRC = 'HREENT' THEN R.QTY ELSE 0 END)    Q_HREENT,
           SUM(CASE WHEN R.SRC = 'UDLV'   THEN R.QTY ELSE 0 END)    Q_UDLV
      FROM RULED R
      LEFT JOIN MA9301C M9 ON M9.COMP_CD = '01' AND M9.USE_YN = 'Y'
                          AND M9.GOOS_CD = R.GOOS_CD AND M9.CSTM_GOODS_TYPE_CD = 'D'
     GROUP BY R.WH_CODE, R.SHED_CD, R.GOOS_CD
    HAVING SUM(R.QTY) > 0                                            -- 0 이하는 신고 제외
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.WH_CODE, A.SHED_CD ORDER BY A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '3'(GWP) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.WH_CODE || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '3' || LPAD(DENSE_RANK() OVER (PARTITION BY N.WH_CODE
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      LEFT JOIN BOND D ON D.BOND_GRN_CD = N.WH_CODE
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,     --  1 신고번호
       X.WH_CODE                                          AS WH_CODE,            --  2 신고지점
       'DLG'                                              AS DOC_TYPE,           --  3 문서구분
       X.DOC_SEQ                                          AS DOC_SEQ,            --  4 품목일련번호
       NULL                                               AS RAMEND_TYPE,        --  5 란정정구분
       X.CSTM_GOODS_TYPE_CD                               AS ITEM_TYPE,          --  6 물품구분 D
       WP.HS_CD                                           AS HS_CODE,            --  7 HS코드 (WM0314C)
       X.NEW_CSTM_GOOS_CD                                 AS ITEM_CODE,          --  8 세관신고 상품코드
       WP.CSTM_GOOS_NM                                    AS ITEM_NAME,          --  9 품명 (세관상품명 = 브랜드 + REF_NO + 상품명)
       NULL                                               AS ITEM_NORM,          -- 10 규격
       X.QTY                                              AS ITEM_QTY,           -- 11 수량
       0                                                  AS ITEM_COST,          -- 12 단가(미화) GWP 0
       0                                                  AS ITEM_AMOUNT,        -- 13 금액
       WP.GOOS_CAPA                                       AS CAPACITY,           -- 14 용량
       WM.BRAN_CD                                         AS BRAND_CODE,         -- 15 브랜드코드
       WB.BRAN_NM                                         AS BRAND_NAME,         -- 16 브랜드명
       WP.SIZE_UNIT_CD                                    AS UNIT_CODE,          -- 17 용량단위 (71 ML / 73 GR)
       WI.MNGE_LVL_CD                                     AS GWP_PRODUCT_GRADE,  -- 18 GWP물품등급 (관리등급, 확인)
       NULL                                               AS REGISTER_NO,        -- 19 참조번호 (Z 는 공백)
       0                                                  AS ITEM_COST_KRW,      -- 20 단가(원화)
       NULL                                               AS QTY_UNIT_CODE,      -- 21 수량단위
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       X.SHED_CD                                          AS REF_SHED_CD,
       X.SITE                                             AS REF_SITE,           -- MAIN / LOGI(통물) / T1 / T2
       X.GOOS_CD                                          AS REF_GOOS_CD,
       WP.REF_NO                                          AS REF_REF_NO,
       X.Q_SUBUL                                          AS REF_Q_SUBUL,        -- 수불 기말
       X.Q_EXCH                                           AS REF_Q_EXCH,         -- 교환권 (+)
       X.Q_HREENT                                         AS REF_Q_HREENT,       -- H재반입 (−)
       X.Q_UDLV                                           AS REF_Q_UDLV          -- 미인도 (−)
  FROM DECL X
  LEFT JOIN WM0310C WM ON WM.COMP_CD = '01' AND WM.GOOS_CD = X.GOOS_CD      -- GWP 기본
  LEFT JOIN MA0030C WB ON WB.COMP_CD = WM.COMP_CD AND WB.BRAN_CD = WM.BRAN_CD  -- 브랜드
  LEFT JOIN WM0314C WP ON WP.COMP_CD = '01' AND WP.GOOS_CD = X.GOOS_CD      -- GWP 상품속성
  LEFT JOIN WM0310I WI ON WI.COMP_CD = '01' AND WI.GOOS_CD = X.GOOS_CD      -- GWP 추가정보
 ORDER BY X.DECLARATION_NO, X.DOC_SEQ;



/* =====================================================================
   [Header] SR_ItemCarryIn_H 양식 순서   — 신고서마다 1행 (Detail 과 같은 WITH)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, 'MAIN' SITE, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         'T1',        '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         'T2',        '04021041',             '040',          '21',         '?'            FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장 (STEP 2 와 같은 값으로)
    SELECT '961' CORN_CD, '????????' SHED_CD FROM DUAL UNION ALL     -- 예) 04077090 제2 통합물류센터 ?
    SELECT '965',         '????????'         FROM DUAL               -- 예) 04077137 은산 통합물류창고 ?
),

-- 판매취소 아닌 GWP 매출 라인  ← 고객 쿼리 "1. 매출조회 기본" (GWP 는 SA0109D)
SALE AS (
    SELECT A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(G.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD,
           NVL(G.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,
           G.GOOS_CD, G.PMNT_QTY QTY
      FROM SA0100M A, SA0109D G, PRM P
     WHERE A.COMP_CD = G.COMP_CD
       AND A.STOR_CD = G.STOR_CD
       AND A.SALE_DT = G.SALE_DT
       AND A.POS_NO  = G.POS_NO
       AND A.RCPT_NO = G.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                       -- 판매취소가 아닌것 (다른 날 취소 포함)
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- H신고 재반입면장 교환권 빌  ← 고객 쿼리 "2." (STEP 2 와 동일)
H_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'
       AND BM.COMP_CD = MD.COMP_CD
       AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
       AND MD.WRK_MDUL_CD = 'WM'
       AND MD.COMM_CTG_CD = 'WM038'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND IM.EDI_RPT_DT <= P.BASE_DT
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK, IFWM12M IM, PRM P
     WHERE MK.COMP_CD = IM.COMP_CD
       AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_CLS_CD = '5KP'
       AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')
       AND IM.EDI_DOC_STAT_CD = 'F1'
       AND IM.EDI_RPT_DT <= P.BASE_DT
),

-- 미인도반입면장 교환권 빌 + 도착 보세구역·장치장  ← 고객 쿼리 "3." (STEP 4 와 동일)
U_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO,
           MAX(IM.ARRV_BOND_RGN_CD) ARRV_BOND, MAX(IM.ARRV_SHED_CD) ARRV_SHED
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.COMP_CD = P.COMP_CD
       AND IM.EDI_RPT_DT <= P.BASE_DT
     GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
),

-- ① 구성요소 → 보세구역·장치장·구분(SITE) 붙이기
COMP AS (
    -- GWP 수불 기말재고 (05·15·17 전 코너)
    SELECT 'SUBUL' SRC, B.BOND_GRN_CD WH_CODE,
           NVL(T.SHED_CD, B.BOND_GRN_CD) SHED_CD,
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END SITE,
           S.GOOS_CD, S.QTY
      FROM WM0353L S
      JOIN PRM P       ON S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON
      JOIN BOND B      ON B.STOR_CD = S.STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = S.CORN_CD
    UNION ALL
    -- 교환권 (+)
    SELECT 'EXCH', B.BOND_GRN_CD, NVL(T.SHED_CD, B.BOND_GRN_CD),
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END,
           X.GOOS_CD, X.QTY
      FROM SALE X
      JOIN BOND B      ON B.STOR_CD = X.STOC_STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = X.STOC_CORN_CD
     WHERE (X.BILL_PROC_CLS_CD, X.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
    UNION ALL
    -- H신고 재반입 (−)
    SELECT 'HREENT', B.BOND_GRN_CD, NVL(T.SHED_CD, B.BOND_GRN_CD),
           CASE WHEN T.CORN_CD IS NOT NULL THEN 'LOGI' ELSE B.SITE END,
           X.GOOS_CD, -X.QTY
      FROM SALE X
      JOIN BOND B      ON B.STOR_CD = X.STOC_STOR_CD
      LEFT JOIN TONG T ON T.CORN_CD = X.STOC_CORN_CD
     WHERE (X.COMP_CD, X.STOR_CD, X.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
    UNION ALL
    -- 미인도 (−) : 도착 보세구역·장치장
    SELECT 'UDLV', NVL(U.ARRV_BOND, B.BOND_GRN_CD), NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD)),
           CASE WHEN NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD)) IN ('04077090', '04077137') THEN 'LOGI'
                WHEN NVL(U.ARRV_BOND, B.BOND_GRN_CD) = '01022006' THEN 'MAIN'
                ELSE 'T1T2' END,
           X.GOOS_CD, -X.QTY
      FROM SALE X
      JOIN U_BILL U    ON U.COMP_CD = X.COMP_CD AND U.STOR_CD = X.STOR_CD AND U.BILL_NO = X.BILL_NO
      LEFT JOIN BOND B ON B.STOR_CD = X.STOR_CD
),

-- ② 규칙 적용 : 본점·통물 = 수불 + 교환권 − H재반입 − 미인도 / T1·T2 = 수불만
RULED AS (
    SELECT C.*
      FROM COMP C
     WHERE C.SITE IN ('MAIN', 'LOGI')
        OR (C.SITE IN ('T1', 'T2') AND C.SRC = 'SUBUL')
),

-- ③ 집계 : 보세구역 × 장치장 × 상품 (환급구분 D, 세관상품코드)
AGG AS (
    SELECT R.WH_CODE, R.SHED_CD, R.GOOS_CD,
           'D'                                                      CSTM_GOODS_TYPE_CD,
           NVL(MAX(M9.CSTM_GOOS_CD), R.GOOS_CD)                     NEW_CSTM_GOOS_CD,
           MAX(R.SITE)                                              SITE,
           SUM(R.QTY)                                               QTY,
           SUM(CASE WHEN R.SRC = 'SUBUL'  THEN R.QTY ELSE 0 END)    Q_SUBUL,
           SUM(CASE WHEN R.SRC = 'EXCH'   THEN R.QTY ELSE 0 END)    Q_EXCH,
           SUM(CASE WHEN R.SRC = 'HREENT' THEN R.QTY ELSE 0 END)    Q_HREENT,
           SUM(CASE WHEN R.SRC = 'UDLV'   THEN R.QTY ELSE 0 END)    Q_UDLV
      FROM RULED R
      LEFT JOIN MA9301C M9 ON M9.COMP_CD = '01' AND M9.USE_YN = 'Y'
                          AND M9.GOOS_CD = R.GOOS_CD AND M9.CSTM_GOODS_TYPE_CD = 'D'
     GROUP BY R.WH_CODE, R.SHED_CD, R.GOOS_CD
    HAVING SUM(R.QTY) > 0                                            -- 0 이하는 신고 제외
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.WH_CODE, A.SHED_CD ORDER BY A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '3'(GWP) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.WH_CODE || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '3' || LPAD(DENSE_RANK() OVER (PARTITION BY N.WH_CODE
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      LEFT JOIN BOND D ON D.BOND_GRN_CD = N.WH_CODE
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,        --  1 신고번호
       X.WH_CODE                                          AS WH_CODE,               --  2 신고지점
       'DLG'                                              AS DOC_TYPE,              --  3 문서구분
       P.DECL_DT                                          AS DECLARATION_DATE,      --  4 신고일자
       NULL                                               AS AMEND_TYPE,            --  5 정정구분
       CASE WHEN X.SHED_CD = X.WH_CODE THEN NULL
            ELSE X.SHED_CD END                            AS CARRYIN_LOC,           --  6 반입장치장소 (통물이면 값)
       NULL                                               AS REFERENCE_NO,          --  7 근거번호
       'Z'                                                AS DECLARATION_TYPE,      --  8 Z 기초재고반입
       'A1'                                               AS STATUS,                --  9 A1 생성
       SYSDATE                                            AS C_DATETIME,            -- 10 생성일시
       NULL                                               AS INTERNATIONAL_MAIL_YN, -- 11 국제우편여부
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       MAX(X.SITE)                                        AS REF_SITE,
       COUNT(*)                                           AS REF_ITEM_CNT,
       SUM(X.QTY)                                         AS REF_QTY,
       SUM(X.Q_SUBUL)                                     AS REF_Q_SUBUL,
       SUM(X.Q_EXCH)                                      AS REF_Q_EXCH,
       SUM(X.Q_HREENT)                                    AS REF_Q_HREENT,
       SUM(X.Q_UDLV)                                      AS REF_Q_UDLV
  FROM DECL X
  CROSS JOIN PRM P
 GROUP BY X.DECLARATION_NO, X.WH_CODE, P.DECL_DT, X.SHED_CD, X.STOR_NM
 ORDER BY X.DECLARATION_NO;
