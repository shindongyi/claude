/* =====================================================================
   12. 11월 기준 기초재고 — 단순 버전 (고객 쿼리 재고관련_정리.sql 기반)
   ---------------------------------------------------------------------
   - 12/1 실행, 기준일 2026-11-30 (11월말). 기준값은 MIG_V_PRM 한 곳에서만 바꿈
   - 고객 쿼리 모양(SA0100M A / SA0103D C / NOT EXISTS ...)을 그대로 살리고
     꼭 필요한 수정만 "-- [수정]" 으로 표시
   - 구성요소를 뷰 하나씩으로 나눠서, 최종 쿼리는 뷰를 더하고 빼기만 함
   - 장치장 매핑은 계산에서 뺐음. 계산재고는 수불과 같은 단위(점·코너·상품)로 냄
     → 신고서의 보세구역/반입장치장소는 고객 답(Q20) 받은 뒤 마지막 INSERT 에서만 붙임
   - 뷰 생성 권한이 없으면 각 뷰 SELECT 를 WITH 절로 옮겨도 똑같이 동작
   ===================================================================== */

-- 0. 기준값 (여기만 바꾸면 전체가 바뀜)
CREATE OR REPLACE VIEW MIG_V_PRM AS
SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON FROM DUAL;


/* ---------------------------------------------------------------------
   1. 판매취소 아닌 매출 (상품 + GWP)  ← 고객 쿼리 "1. 매출조회 기본"
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_SALE AS
SELECT 'G' KIND,                                         -- 상품
       A.COMP_CD, A.STOR_CD, A.SALE_DT, A.BILL_NO,
       A.BILL_PROC_CLS_CD,                               -- 빌상태 (BO015)
       A.GOOS_LOC_CLS_CD,                                -- 상품위치 (BO014)
       NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD, -- 재고가 빠지는 점
       NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD, -- 재고가 빠지는 코너
       C.GOOS_CD, C.GOOS_QTY QTY
  FROM SA0100M A /* 영업_매출기본 */, SA0103D C /* 영업_매출상세 */, MIG_V_PRM P
 WHERE A.COMP_CD = C.COMP_CD
   AND A.STOR_CD = C.STOR_CD
   AND A.SALE_DT = C.SALE_DT
   AND A.POS_NO  = C.POS_NO
   AND A.RCPT_NO = C.RCPT_NO
   AND A.COMP_CD = P.COMP_CD
   AND A.SALE_TYPE_CD = '1'                              -- [수정] 정상매출만 명시
   AND A.SALE_DT <= P.BASE_DT                            -- [수정] 11/30 까지
   AND NVL(C.SALE_CNCL_YN, 'N') = 'N'                    -- [수정] 라인 취소 제외
   -- [수정] 고객 쿼리의 SA2000I, MA0100I 조인은 재고 계산에 불필요해서 뺌 (INNER JOIN 이라 누락 위험)
   -- 판매취소가 아닌것
   AND NOT EXISTS (SELECT 1
                     FROM SA0100M E /* 영업 매출 기본 */
                    WHERE E.COMP_CD = A.COMP_CD
                      AND E.STOR_CD = A.STOR_CD
                      AND E.BILL_NO = A.BILL_NO
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                      AND E.SALE_DT <= P.BASE_DT)        -- [수정] E.SALE_DT = A.SALE_DT 대신 (다른 날 취소도 잡음)
UNION ALL
SELECT 'W' KIND,                                         -- GWP
       A.COMP_CD, A.STOR_CD, A.SALE_DT, A.BILL_NO,
       A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
       NVL(G.STOC_STOR_CD, A.STOC_STOR_CD), NVL(G.STOC_CORN_CD, A.STOC_CORN_CD),
       G.GOOS_CD, G.PMNT_QTY
  FROM SA0100M A, SA0109D G /* 영업_매출GWP */, MIG_V_PRM P
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
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT);


/* ---------------------------------------------------------------------
   2. 교환권 (+) : 매출/통물창고, 매출/통물미래보세, 면장등록/통물미래보세
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_EXCH AS
SELECT S.*
  FROM MIG_V_SALE S
 WHERE (S.BILL_PROC_CLS_CD, S.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'));


/* ---------------------------------------------------------------------
   3. H신고 재반입면장 교환권 중 판매취소 아닌 것 (−)  ← 고객 쿼리 "2."
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_H_BILL AS
/* WM038 면장기준 IFWM11M */
SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
  FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD
 WHERE BM.COMP_CD = BD.COMP_CD
   AND BM.STOR_CD = BD.STOR_CD
   AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
   AND BM.COMP_CD = IM.COMP_CD
   AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
   AND IM.EDI_DOC_STAT_CD = 'G1'                          /* 확정통보 */
   AND BM.COMP_CD = MD.COMP_CD
   AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
   AND MD.WRK_MDUL_CD = 'WM'
   AND MD.COMM_CTG_CD = 'WM038'
   /* 05:반입면장, 75:국산반입면장, 85:외국인국산반입면장, 10:한도초과반입면장, 80:국산 한도초과면장,
      90:외국인국산 한도초과면장, 20:세관유치재반입, 91:세관유치반입(국산비환급) */
   AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
   AND MD.COMM_PROP_CONT_1 = 'H'                          -- H신고
   AND NVL(BM.DEL_YN, 'N') = 'N'                          -- [수정] 삭제건 제외
   AND IM.EDI_RPT_DT <= (SELECT BASE_DT FROM MIG_V_PRM)  -- [수정] 11/30 까지
UNION                                                     -- [수정] UNION ALL + ZZZ 서브쿼리(147행 오타) 대신 UNION 으로 중복 제거
/* WM038에 없지만 대상 */
SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
  FROM MK5010D MK, IFWM12M IM
 WHERE MK.COMP_CD = IM.COMP_CD
   AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
   AND IM.EDI_DOC_CLS_CD = '5KP'
   AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')                   /* B:반품(인도후), R:미인도물품재반입 */
   AND IM.EDI_DOC_STAT_CD = 'F1'                          /* 결과통보 */
   AND IM.EDI_RPT_DT <= (SELECT BASE_DT FROM MIG_V_PRM); -- [수정]

CREATE OR REPLACE VIEW MIG_V_H_REENT AS
SELECT S.*                                                -- [수정] 빌 목록이 아니라 상품/GWP 수량으로
  FROM MIG_V_SALE S
 WHERE (S.COMP_CD, S.STOR_CD, S.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM MIG_V_H_BILL);


/* ---------------------------------------------------------------------
   4. 미인도반입면장 교환권 중 판매취소 아닌 것  ← 고객 쿼리 "3."
      정상재고에서는 (−), 신고는 Y(미인도물품재고반입) + 교환권번호
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_U_BILL AS
SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO        -- [수정] DISTINCT (카톤별 중복 방지)
  FROM BO0110M BM, BO0110D BD, IFWM11M IM
 WHERE BM.COMP_CD = BD.COMP_CD
   AND BM.STOR_CD = BD.STOR_CD
   AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
   AND BM.COMP_CD = IM.COMP_CD
   AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
   AND IM.EDI_DOC_STAT_CD = 'G1'                          /* 확정통보 */
   /* 06:미인도반입면장, 76:국산미인도반입면장, 86:외국인국산미인도반입면장 */
   AND BM.PMIT_CLS_CD IN ('06', '76', '86')
   AND NVL(BM.DEL_YN, 'N') = 'N'                          -- [수정]
   AND IM.EDI_RPT_DT <= (SELECT BASE_DT FROM MIG_V_PRM); -- [수정]

CREATE OR REPLACE VIEW MIG_V_UDLV AS
SELECT S.*
  FROM MIG_V_SALE S
 WHERE (S.COMP_CD, S.STOR_CD, S.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM MIG_V_U_BILL);


/* ---------------------------------------------------------------------
   5. 수불재고 11월말 (월수불)  — 상품 WM0053L / GWP WM0353L
      ※ 월수불 QTY = 월말재고 인지 1회 확인 (sql/06 [판별]), 12/1 아침 11월 월마감 완료 확인
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_SUBUL AS
SELECT 'G' KIND, S.COMP_CD, S.STOR_CD, S.CORN_CD, S.GOOS_CD, S.REFU_CLS_CD, S.STOC_CLS_CD, S.QTY
  FROM WM0053L S, MIG_V_PRM P
 WHERE S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON
UNION ALL
SELECT 'W', S.COMP_CD, S.STOR_CD, S.CORN_CD, S.GOOS_CD, NULL, S.STOC_CLS_CD, S.QTY
  FROM WM0353L S, MIG_V_PRM P
 WHERE S.COMP_CD = P.COMP_CD AND S.YMON = P.YMON;


/* ---------------------------------------------------------------------
   6. HS세관재고 11/30  — 상품별은 WM0121L 누계 (WM0121S 에는 상품코드 없음)
   --------------------------------------------------------------------- */
CREATE OR REPLACE VIEW MIG_V_CSTM AS
SELECT L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD,
       SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) QTY
  FROM WM0121L L, MIG_V_PRM P
 WHERE L.COMP_CD = P.COMP_CD
   AND L.EDI_REPA_DT <= P.BASE_DT
 GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD;



/* =====================================================================
   결과 조회
   ===================================================================== */

-- [A] 계산재고 = 수불 + 교환권 − H재반입 − 미인도   (점·코너·상품 단위, 수불과 같은 단위)
SELECT STOR_CD, CORN_CD, KIND, GOOS_CD,
       SUM(SUBUL)  SUBUL,
       SUM(EXCH)   EXCH,
       SUM(HREENT) HREENT,
       SUM(UDLV)   UDLV,
       SUM(SUBUL + EXCH - HREENT - UDLV) CALC_QTY
  FROM (SELECT STOR_CD, CORN_CD, KIND, GOOS_CD, QTY SUBUL, 0 EXCH, 0 HREENT, 0 UDLV FROM MIG_V_SUBUL
        UNION ALL
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, QTY, 0, 0 FROM MIG_V_EXCH
        UNION ALL
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, QTY, 0 FROM MIG_V_H_REENT
        UNION ALL
        SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, 0, QTY FROM MIG_V_UDLV)
 GROUP BY STOR_CD, CORN_CD, KIND, GOOS_CD
HAVING SUM(SUBUL + EXCH - HREENT - UDLV) <> 0
 ORDER BY STOR_CD, CORN_CD, KIND, GOOS_CD;

-- [A-1] 위 결과를 점·코너별로 요약 (어느 점·코너가 통합물류인지 고객과 같이 보기 좋음)
SELECT STOR_CD, CORN_CD, KIND,
       SUM(SUBUL) SUBUL, SUM(EXCH) EXCH, SUM(HREENT) HREENT, SUM(UDLV) UDLV,
       SUM(SUBUL + EXCH - HREENT - UDLV) CALC_QTY,
       COUNT(DISTINCT GOOS_CD) GOOS_CNT
  FROM (SELECT STOR_CD, CORN_CD, KIND, GOOS_CD, QTY SUBUL, 0 EXCH, 0 HREENT, 0 UDLV FROM MIG_V_SUBUL
        UNION ALL SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, QTY, 0, 0 FROM MIG_V_EXCH
        UNION ALL SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, QTY, 0 FROM MIG_V_H_REENT
        UNION ALL SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, GOOS_CD, 0, 0, 0, QTY FROM MIG_V_UDLV)
 GROUP BY STOR_CD, CORN_CD, KIND
 ORDER BY STOR_CD, CORN_CD, KIND;

-- [B] HS세관재고 11/30 (보세구역·장치장별 요약)
SELECT BOND_GRN_CD, SHED_CD, CSTM_ITEM_CLS_CD,
       COUNT(DISTINCT GOOS_CD) GOOS_CNT, SUM(QTY) QTY
  FROM MIG_V_CSTM
 GROUP BY BOND_GRN_CD, SHED_CD, CSTM_ITEM_CLS_CD
 ORDER BY 1, 2, 3;

-- [B-1] 대사: WM0121L 누계 vs 고객이 보는 WM0121S (11/30 집계) — 차이 0 이어야 함
SELECT NVL(L.BOND_GRN_CD, S.BOND_GRN_CD) BOND_GRN_CD, NVL(L.SHED_CD, S.SHED_CD) SHED_CD,
       L.QTY L_QTY, S.QTY S_QTY, NVL(L.QTY, 0) - NVL(S.QTY, 0) DIFF
  FROM (SELECT BOND_GRN_CD, SHED_CD, SUM(QTY) QTY FROM MIG_V_CSTM GROUP BY BOND_GRN_CD, SHED_CD) L
  FULL OUTER JOIN
       (SELECT A.BOND_GRN_CD, A.SHED_CD, SUM(A.ACUM_CARI_QTY - A.ACUM_TAKE_OUT_QTY) QTY
          FROM WM0121S A, MIG_V_PRM P
         WHERE A.COMP_CD = P.COMP_CD AND A.EDI_REPA_DT = P.BASE_DT
         GROUP BY A.BOND_GRN_CD, A.SHED_CD) S
    ON S.BOND_GRN_CD = L.BOND_GRN_CD AND S.SHED_CD = L.SHED_CD
 ORDER BY 1, 2;

-- [C] 미인도 (Y 신고 대상) — 교환권번호별
SELECT STOC_STOR_CD, STOC_CORN_CD, KIND, BILL_NO, GOOS_CD, SUM(QTY) QTY
  FROM MIG_V_UDLV
 GROUP BY STOC_STOR_CD, STOC_CORN_CD, KIND, BILL_NO, GOOS_CD
 ORDER BY STOC_STOR_CD, BILL_NO, KIND, GOOS_CD;

-- [D] 고객 쿼리 대비 영향 (설명용): 고객 원본 방식이면 이중 차감됐을 빌 수 (147행 오타)
SELECT COUNT(*) BOTH_PART_BILLS
  FROM (SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
          FROM BO0110M BM, BO0110D BD, MA0151D MD
         WHERE BM.COMP_CD = BD.COMP_CD AND BM.STOR_CD = BD.STOR_CD AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
           AND BM.COMP_CD = MD.COMP_CD AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
           AND MD.WRK_MDUL_CD = 'WM' AND MD.COMM_CTG_CD = 'WM038' AND MD.COMM_PROP_CONT_1 = 'H'
        INTERSECT
        SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
          FROM MK5010D MK, IFWM12M IM
         WHERE MK.COMP_CD = IM.COMP_CD AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
           AND IM.EDI_DOC_CLS_CD = '5KP' AND IM.CSTM_RPT_CLS_CD IN ('B','R') AND IM.EDI_DOC_STAT_CD = 'F1');
