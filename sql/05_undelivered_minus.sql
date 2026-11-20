/* =====================================================================
   05. C05 미인도반입면장 교환권 중 판매취소 아닌 교환권의 판매수량 (−)  [본점, 통합물류 / T1·T2 없음]
   고객 쿼리(line 187~221) 수정본 — 수정 사항은 04 와 동일
   STOC_TYPE='U'(미인도)로 적재. 정상재고 차감 여부/미인도재고 별도 적재 여부는 고객 확인(Q2) 후 06에서 처리
   바인드: :RUN_ID, :COMP_CD, :BASE_DT
   ===================================================================== */

INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, QTY, SRC_BILL_NO, SRC_KEY)
WITH U_BILL AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO          -- 카톤 중복 제거
      FROM BO0110M BM
      JOIN BO0110D BD
        ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD
       AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
     WHERE BM.COMP_CD = :COMP_CD
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.PMIT_CLS_CD IN ('06','76','86')   -- 미인도반입 / 국산미인도반입 / 외국인국산미인도반입
       AND EXISTS (SELECT 1 FROM IFWM11M IM
                    WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1'
                      AND NVL(IM.DEL_YN, 'N') = 'N'
                      AND IM.EDI_RPT_DT <= :BASE_DT)
)
SELECT :RUN_ID, :BASE_DT, V.COMP_CD, V.STOC_STOR_CD, V.STOC_CORN_CD, 'G', 'U', 'C05', -1,
       V.GOOS_CD, V.GOOS_QTY, V.BILL_NO,
       V.STOR_CD||'|'||V.SALE_DT||'|'||V.POS_NO||'|'||V.RCPT_NO||'|'||V.SEQ
  FROM U_BILL U
  JOIN MIG_V_VALID_SALE_GOOS V            -- 판매취소 아닌 정상매출 상세 (상품)
    ON V.COMP_CD = U.COMP_CD AND V.STOR_CD = U.STOR_CD AND V.BILL_NO = U.BILL_NO
 WHERE V.SALE_DT <= :BASE_DT;
-- GWP: 동일 구조로 MIG_V_VALID_SALE_GWP 조인, ITEM_TYPE='W' (고객 정의: "상품 및 GWP 미인도 기초")
