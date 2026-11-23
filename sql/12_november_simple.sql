/* =====================================================================
   12. 11월 기준 기초재고 — 단순 버전 (고객 쿼리 재고관련_정리.sql 기반)
   ---------------------------------------------------------------------
   - 테이블·뷰를 하나도 만들지 않음. SELECT 쿼리 4개만 (WITH 절 사용)
       [A] 계산재고 (수불 + 교환권 − H재반입 − 미인도)  — 점·코너·상품
       [B] HS세관재고 11/30                              — 보세구역·장치장·상품
       [C] 미인도 (Y 신고 대상)                          — 교환권번호별
       [D] WM0121S 대사
   - 기준일: 2026-11-30 (12/1 실행). 각 쿼리 맨 위 PRM 줄만 바꾸면 됨
   - 고객 쿼리 모양을 살리고 고친 곳만 "-- [수정]"
   ===================================================================== */


/* =====================================================================
   [A] 계산재고 = 수불 + 교환권 − H신고 재반입 − 미인도   (점·코너·상품)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON FROM DUAL),

-- 1. 판매취소 아닌 매출 (상품 + GWP)  ← 고객 쿼리 "1. 매출조회 기본"
SALE AS (
    SELECT 'G' KIND, A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD,       -- 재고가 빠지는 점
           NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,       -- 재고가 빠지는 코너
           C.GOOS_CD, C.GOOS_QTY QTY
      FROM SA0100M A /* 영업_매출기본 */, SA0103D C /* 영업_매출상세 */, PRM P
     WHERE A.COMP_CD = C.COMP_CD
       AND A.STOR_CD = C.STOR_CD
       AND A.SALE_DT = C.SALE_DT
       AND A.POS_NO  = C.POS_NO
       AND A.RCPT_NO = C.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'                    -- [수정] 정상매출만
       AND A.SALE_DT <= P.BASE_DT                  -- [수정] 11/30 까지
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'          -- [수정] 라인 취소 제외
       -- 판매취소가 아닌것
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)   -- [수정] 같은 날 조건 제거 (다른 날 취소도 제외)
    UNION ALL
    SELECT 'W', A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(G.STOC_STOR_CD, A.STOC_STOR_CD), NVL(G.STOC_CORN_CD, A.STOC_CORN_CD),
           G.GOOS_CD, G.PMNT_QTY
      FROM SA0100M A, SA0109D G /* 영업_매출GWP */, PRM P
     WHERE A.COMP_CD = G.COMP_CD
       AND A.STOR_CD = G.STOR_CD
       AND A.SALE_DT = G.SALE_DT
       AND A.POS_NO  = G.POS_NO
       AND A.RCPT_NO = G.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
),

-- 2. H신고 재반입면장 교환권 빌  ← 고객 쿼리 "2."
H_BILL AS (
    /* WM038 면장기준 IFWM11M */
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'               /* 확정통보 */
       AND BM.COMP_CD = MD.COMP_CD
       AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
       AND MD.WRK_MDUL_CD = 'WM'
       AND MD.COMM_CTG_CD = 'WM038'
       /* 05:반입면장, 75:국산반입면장, 85:외국인국산반입면장, 10:한도초과반입면장, 80:국산 한도초과면장,
          90:외국인국산 한도초과면장, 20:세관유치재반입, 91:세관유치반입(국산비환급) */
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'               -- H신고
       AND NVL(BM.DEL_YN, 'N') = 'N'               -- [수정] 삭제건 제외
       AND IM.EDI_RPT_DT <= P.BASE_DT              -- [수정] 11/30 까지
    UNION                                          -- [수정] UNION ALL + ZZZ 서브쿼리(147행 오타) 대신 UNION 으로 중복 제거
    /* WM038에 없지만 대상 */
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK, IFWM12M IM, PRM P
     WHERE MK.COMP_CD = IM.COMP_CD
       AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_CLS_CD = '5KP'
       AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')        /* B:반품(인도후), R:미인도물품재반입 */
       AND IM.EDI_DOC_STAT_CD = 'F1'               /* 결과통보 */
       AND IM.EDI_RPT_DT <= P.BASE_DT              -- [수정]
),

-- 3. 미인도반입면장 교환권 빌  ← 고객 쿼리 "3."
U_BILL AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO   -- [수정] DISTINCT (카톤별 중복 방지)
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'               /* 확정통보 */
       /* 06:미인도반입면장, 76:국산미인도반입면장, 86:외국인국산미인도반입면장 */
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'               -- [수정]
       AND IM.EDI_RPT_DT <= P.BASE_DT              -- [수정]
)

SELECT STOR_CD, CORN_CD, KIND, GOOS_CD,
       SUM(SUBUL)  SUBUL,                          -- 11월말 수불
       SUM(EXCH)   EXCH,                           -- 교환권 (+)
       SUM(HREENT) HREENT,                         -- H신고 재반입 (−)
       SUM(UDLV)   UDLV,                           -- 미인도 (−)
       SUM(SUBUL + EXCH - HREENT - UDLV) CALC_QTY  -- 계산재고
  FROM (
        -- 수불 11월말: 상품 WM0053L / GWP WM0353L
        SELECT S.STOR_CD, S.CORN_CD, 'G' KIND, S.GOOS_CD, S.QTY SUBUL, 0 EXCH, 0 HREENT, 0 UDLV
          FROM WM0053L S, PRM P WHERE S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON
        UNION ALL
        SELECT S.STOR_CD, S.CORN_CD, 'W', S.GOOS_CD, S.QTY, 0, 0, 0
          FROM WM0353L S, PRM P WHERE S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON
        UNION ALL
        -- 교환권 (+): 매출/통물창고, 매출/통물미래보세, 면장등록/통물미래보세
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, QTY, 0, 0
          FROM SALE
         WHERE (BILL_PROC_CLS_CD, GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
        UNION ALL
        -- H신고 재반입 (−)
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, QTY, 0
          FROM SALE
         WHERE (COMP_CD, STOR_CD, BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
        UNION ALL
        -- 미인도 (−)
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, 0, QTY
          FROM SALE
         WHERE (COMP_CD, STOR_CD, BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM U_BILL)
       )
 GROUP BY STOR_CD, CORN_CD, KIND, GOOS_CD
HAVING SUM(SUBUL + EXCH - HREENT - UDLV) <> 0
 ORDER BY STOR_CD, CORN_CD, KIND, GOOS_CD;
-- 점·코너별 요약이 보고 싶으면 맨 끝 GROUP BY 에서 GOOS_CD 를 빼고 SELECT 에 COUNT(DISTINCT GOOS_CD) 추가



/* =====================================================================
   [B] HS세관재고 11/30 — 보세구역·장치장·상품 (WM0121S 에는 상품코드가 없어서 WM0121L 누계)
   ===================================================================== */
SELECT L.BOND_GRN_CD, L.SHED_CD, L.CSTM_ITEM_CLS_CD, L.GOOS_CD, L.HS_CD,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L
 WHERE L.COMP_CD = '01'
   AND L.EDI_REPA_DT <= '20261130'
 GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.CSTM_ITEM_CLS_CD, L.GOOS_CD, L.HS_CD
HAVING SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) <> 0
 ORDER BY 1, 2, 3, 4;



/* =====================================================================
   [C] 미인도 (Y 신고 대상) — 교환권번호별 상품/GWP 수량
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT FROM DUAL),
U_BILL AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'
       AND BM.PMIT_CLS_CD IN ('06', '76', '86')
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND IM.EDI_RPT_DT <= P.BASE_DT
)
SELECT 'G' KIND, NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD, NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,
       A.BILL_NO, C.GOOS_CD, SUM(C.GOOS_QTY) QTY
  FROM SA0100M A, SA0103D C, U_BILL U, PRM P
 WHERE A.COMP_CD = C.COMP_CD AND A.STOR_CD = C.STOR_CD AND A.SALE_DT = C.SALE_DT
   AND A.POS_NO = C.POS_NO AND A.RCPT_NO = C.RCPT_NO
   AND A.COMP_CD = U.COMP_CD AND A.STOR_CD = U.STOR_CD AND A.BILL_NO = U.BILL_NO
   AND A.SALE_TYPE_CD = '1' AND A.SALE_DT <= P.BASE_DT
   AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
   AND NOT EXISTS (SELECT 1 FROM SA0100M E
                    WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
 GROUP BY NVL(C.STOC_STOR_CD, A.STOC_STOR_CD), NVL(C.STOC_CORN_CD, A.STOC_CORN_CD), A.BILL_NO, C.GOOS_CD
UNION ALL
SELECT 'W', NVL(G.STOC_STOR_CD, A.STOC_STOR_CD), NVL(G.STOC_CORN_CD, A.STOC_CORN_CD),
       A.BILL_NO, G.GOOS_CD, SUM(G.PMNT_QTY)
  FROM SA0100M A, SA0109D G, U_BILL U, PRM P
 WHERE A.COMP_CD = G.COMP_CD AND A.STOR_CD = G.STOR_CD AND A.SALE_DT = G.SALE_DT
   AND A.POS_NO = G.POS_NO AND A.RCPT_NO = G.RCPT_NO
   AND A.COMP_CD = U.COMP_CD AND A.STOR_CD = U.STOR_CD AND A.BILL_NO = U.BILL_NO
   AND A.SALE_TYPE_CD = '1' AND A.SALE_DT <= P.BASE_DT
   AND NOT EXISTS (SELECT 1 FROM SA0100M E
                    WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
 GROUP BY NVL(G.STOC_STOR_CD, A.STOC_STOR_CD), NVL(G.STOC_CORN_CD, A.STOC_CORN_CD), A.BILL_NO, G.GOOS_CD
 ORDER BY 2, 4, 1, 5;
-- 검증: [C] 의 QTY 합계 = [A] 의 UDLV 합계 (같은 빌·같은 조건이므로 같아야 함)



/* =====================================================================
   [D] 세관재고 대사: [B] 보세구역·장치장 합계 vs 고객이 보는 WM0121S (11/30 집계) — DIFF 0 이어야 함
   ===================================================================== */
SELECT NVL(L.BOND_GRN_CD, S.BOND_GRN_CD) BOND_GRN_CD, NVL(L.SHED_CD, S.SHED_CD) SHED_CD,
       L.QTY L_QTY, S.QTY S_QTY, NVL(L.QTY, 0) - NVL(S.QTY, 0) DIFF
  FROM (SELECT BOND_GRN_CD, SHED_CD, SUM(NVL(CARI_QTY, 0) - NVL(TAKE_OUT_QTY, 0)) QTY
          FROM WM0121L
         WHERE COMP_CD = '01' AND EDI_REPA_DT <= '20261130'
         GROUP BY BOND_GRN_CD, SHED_CD) L
  FULL OUTER JOIN
       (SELECT BOND_GRN_CD, SHED_CD, SUM(ACUM_CARI_QTY - ACUM_TAKE_OUT_QTY) QTY
          FROM WM0121S
         WHERE COMP_CD = '01' AND EDI_REPA_DT = '20261130'
         GROUP BY BOND_GRN_CD, SHED_CD) S
    ON S.BOND_GRN_CD = L.BOND_GRN_CD AND S.SHED_CD = L.SHED_CD
 ORDER BY 1, 2;
