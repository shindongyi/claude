/* =====================================================================
   03. C03 교환권(+) : 팔렸지만 아직 통물에 실물이 있는 상품/GWP
       (빌상태, 상품위치) ∈ (00,02) 매출/통물창고, (00,12) 매출/통물미래보세, (01,12) 면장등록/통물미래보세
   - 상태 컬럼은 스냅샷 → 동결 직후 실행
   - 바인드: :RUN_ID, :COMP_CD, :BASE_DT
   ===================================================================== */

INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, QTY, SRC_BILL_NO, SRC_KEY)
SELECT :RUN_ID, :BASE_DT, V.COMP_CD, V.STOC_STOR_CD, V.STOC_CORN_CD, 'G', 'N', 'C03', +1,
       V.GOOS_CD, V.GOOS_QTY /* - V.RTN_QTY : 부분반품 확인 후 */, V.BILL_NO,
       V.STOR_CD||'|'||V.SALE_DT||'|'||V.POS_NO||'|'||V.RCPT_NO||'|'||V.SEQ
  FROM MIG_V_VALID_SALE_GOOS V
 WHERE V.COMP_CD = :COMP_CD
   AND V.SALE_DT <= :BASE_DT
   AND (V.BILL_PROC_CLS_CD, V.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'));

-- GWP 교환권 (통물 / 본점 계산재고용 — 본점 위치코드 조합은 고객 확인)
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, QTY, SRC_BILL_NO, SRC_KEY)
SELECT :RUN_ID, :BASE_DT, V.COMP_CD, V.STOC_STOR_CD, V.STOC_CORN_CD, 'W', 'N', 'C03', +1,
       V.GOOS_CD, V.GOOS_QTY, V.BILL_NO,
       V.STOR_CD||'|'||V.SALE_DT||'|'||V.POS_NO||'|'||V.RCPT_NO||'|'||V.SEQ
  FROM MIG_V_VALID_SALE_GWP V
 WHERE V.COMP_CD = :COMP_CD
   AND V.SALE_DT <= :BASE_DT
   AND (V.BILL_PROC_CLS_CD, V.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'));

-- 점검: 재고 귀속 점/코너 분포 (통물 외 점이 나오면 매핑 확인)
SELECT STOR_CD, CORN_CD, ITEM_TYPE, COUNT(DISTINCT SRC_BILL_NO) BILL_CNT, SUM(QTY) QTY
  FROM MIG_STOC_COMP WHERE MIG_RUN_ID = :RUN_ID AND COMP_TYPE = 'C03'
 GROUP BY STOR_CD, CORN_CD, ITEM_TYPE ORDER BY 1,2,3;
