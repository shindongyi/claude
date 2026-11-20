/* =====================================================================
   04. C04 H신고 재반입면장 교환권 중 판매취소 아닌 교환권의 판매수량 (−)  [통합물류]
   고객 쿼리(line 76~185) 수정본
   - [수정] line 147 SA.COMP_CD = S.BILL_NO 오타 → 빌 키 UNION 으로 대체 (자연 중복제거)
   - [수정] SELECT * UNION ALL (컬럼수 불일치) → 키 컬럼만
   - [수정] SA0103D/SA0109D 조인으로 상품별 판매수량 산출
   - [수정] BO0110D 카톤/순번 중복 → 빌 키 DISTINCT 후 상세 조인
   - [수정] IFWM11M/12M JOIN → EXISTS, 삭제여부·기준일 조건 추가
   - [확인] 고객 원본은 [B]에서 "H면장 존재(G1 무관)" 빌을 제외 → 본 수정본은 [A](G1 확정) 와 UNION.
            "H면장은 있으나 G1 미확정 + 5KP F1" 빌의 포함 여부 고객 확인
   바인드: :RUN_ID, :COMP_CD, :BASE_DT
   ===================================================================== */

INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, QTY, SRC_BILL_NO, SRC_KEY)
WITH H_BILL AS (
    /* [A] WM038 H신고 반입면장 + G1 확정통보 */
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO, 'A' SRC
      FROM BO0110M BM
      JOIN BO0110D BD
        ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD
       AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      JOIN MA0151D MD
        ON MD.COMP_CD = BM.COMP_CD AND MD.WRK_MDUL_CD = 'WM' AND MD.COMM_CTG_CD = 'WM038'
       AND MD.COMM_CTG_DTL_CD = BM.PMIT_CLS_CD
     WHERE BM.COMP_CD = :COMP_CD
       AND NVL(BM.DEL_YN, 'N') = 'N'                       -- [추가] 삭제 제외
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'
       AND EXISTS (SELECT 1 FROM IFWM11M IM
                    WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1'          -- 확정통보
                      AND NVL(IM.DEL_YN, 'N') = 'N'
                      AND IM.EDI_RPT_DT <= :BASE_DT)
    UNION
    /* [B] WM038 에는 없지만 대상: 5KP 반입신고 B(반품-인도후)/R(미인도물품재반입) + F1 결과통보 */
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO, 'B'
      FROM MK5010D MK
     WHERE MK.COMP_CD = :COMP_CD
       AND EXISTS (SELECT 1 FROM IFWM12M IM
                    WHERE IM.COMP_CD = MK.COMP_CD AND IM.EDI_RPT_NO = MK.EDI_RPT_NO
                      AND IM.EDI_DOC_CLS_CD = '5KP'
                      AND IM.CSTM_RPT_CLS_CD IN ('B','R')
                      AND IM.EDI_DOC_STAT_CD = 'F1'          -- 결과통보
                      AND NVL(IM.DEL_YN, 'N') = 'N'
                      AND IM.EDI_RPT_DT <= :BASE_DT)
),
H_BILL_U AS (   -- [A],[B] 양쪽에 있는 빌은 1건으로 (원본 line 147 버그로 이중차감되던 부분)
    SELECT COMP_CD, STOR_CD, BILL_NO, MIN(SRC) SRC FROM H_BILL GROUP BY COMP_CD, STOR_CD, BILL_NO
)
SELECT :RUN_ID, :BASE_DT, V.COMP_CD, V.STOC_STOR_CD, V.STOC_CORN_CD, 'G', 'N', 'C04', -1,
       V.GOOS_CD, V.GOOS_QTY, V.BILL_NO,
       H.SRC||'|'||V.STOR_CD||'|'||V.SALE_DT||'|'||V.POS_NO||'|'||V.RCPT_NO||'|'||V.SEQ
  FROM H_BILL_U H
  JOIN MIG_V_VALID_SALE_GOOS V            -- 판매취소 아닌 정상매출 상세 (상품)
    ON V.COMP_CD = H.COMP_CD AND V.STOR_CD = H.STOR_CD AND V.BILL_NO = H.BILL_NO
 WHERE V.SALE_DT <= :BASE_DT;
-- GWP 도 필요하면 동일 구조로 MIG_V_VALID_SALE_GWP 조인, ITEM_TYPE='W'
-- 통물 귀속분만 남기는 필터는 MIG_MAP_STOR(SITE_GRP='LOGI') 기준으로 집계 단계(sql/06)에서 적용

-- 고객 원본 버그 영향도 확인: [A],[B] 양쪽에 걸린 빌 수 = 원본에서 이중 차감되던 빌 수
WITH A AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD=BM.COMP_CD AND BD.STOR_CD=BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO=BM.BOND_TRAN_MNGE_NO
      JOIN MA0151D MD ON MD.COMP_CD=BM.COMP_CD AND MD.WRK_MDUL_CD='WM' AND MD.COMM_CTG_CD='WM038'
                     AND MD.COMM_CTG_DTL_CD=BM.PMIT_CLS_CD AND MD.COMM_PROP_CONT_1='H'
     WHERE BM.COMP_CD = :COMP_CD),
B AS (
    SELECT DISTINCT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK
     WHERE MK.COMP_CD = :COMP_CD
       AND EXISTS (SELECT 1 FROM IFWM12M IM WHERE IM.COMP_CD=MK.COMP_CD AND IM.EDI_RPT_NO=MK.EDI_RPT_NO
                      AND IM.EDI_DOC_CLS_CD='5KP' AND IM.CSTM_RPT_CLS_CD IN ('B','R') AND IM.EDI_DOC_STAT_CD='F1'))
SELECT COUNT(*) AS BOTH_A_B_BILL_CNT FROM A JOIN B USING (COMP_CD, STOR_CD, BILL_NO);

-- BO0110D 카톤 중복 확인: 1보다 크면 원본 방식은 수량 배수
SELECT MAX(CNT) MAX_ROWS_PER_BILL, SUM(CASE WHEN CNT > 1 THEN 1 END) MULTI_ROW_BILLS
  FROM (SELECT COMP_CD, STOR_CD, BOND_TRAN_MNGE_NO, BILL_NO, COUNT(*) CNT
          FROM BO0110D WHERE COMP_CD = :COMP_CD
         GROUP BY COMP_CD, STOR_CD, BOND_TRAN_MNGE_NO, BILL_NO);
