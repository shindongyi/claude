/* =====================================================================
   02. 공통: 기준일 현재 "판매취소되지 않은" 정상매출 상세 (상품 / GWP)
   - 고객 쿼리 대비 수정: 취소 판정에서 SALE_DT 동일 조건 제거 (후일 취소 포함)
   - 바인드: :COMP_CD, :BASE_DT (YYYYMMDD)
   - 뷰로 만들어 C03~C05 에서 재사용
   ===================================================================== */

CREATE OR REPLACE VIEW MIG_V_VALID_SALE_GOOS AS
SELECT SA.COMP_CD, SA.STOR_CD, SA.SALE_DT, SA.POS_NO, SA.RCPT_NO, SA.BILL_NO,
       SA.BILL_PROC_CLS_CD,                         -- BO015 빌상태 (현재 스냅샷)
       SA.GOOS_LOC_CLS_CD,                          -- BO014 상품위치 (현재 스냅샷)
       D.SEQ,
       D.GOOS_CD,
       D.GOOS_QTY,
       NVL(D.RTN_QTY, 0)                AS RTN_QTY, -- 부분반품 처리방식 고객 확인 후 QTY 산식 확정
       D.SALE_CNCL_YN,
       NVL(D.STOC_STOR_CD, SA.STOC_STOR_CD) AS STOC_STOR_CD,   -- 재고 귀속 점
       NVL(D.STOC_CORN_CD, SA.STOC_CORN_CD) AS STOC_CORN_CD    -- 재고 귀속 코너
  FROM SA0100M SA
  JOIN SA0103D D
    ON D.COMP_CD = SA.COMP_CD AND D.STOR_CD = SA.STOR_CD AND D.SALE_DT = SA.SALE_DT
   AND D.POS_NO  = SA.POS_NO  AND D.RCPT_NO = SA.RCPT_NO
 WHERE SA.SALE_TYPE_CD = '1'                        -- 정상매출 (SA101 확인)
   AND NVL(SA.BILL_PROC_CLS_CD, '00') <> '08'       -- 빌상태 판매취소 제외 (이중 안전장치)
   AND NVL(D.SALE_CNCL_YN, 'N') = 'N'               -- 라인 취소 제외 (의미 확인 필요)
   AND NOT EXISTS (SELECT 1
                     FROM SA0100M E
                    WHERE E.COMP_CD = SA.COMP_CD
                      AND E.STOR_CD = SA.STOR_CD
                      AND E.BILL_NO = SA.BILL_NO
                      AND E.SALE_TYPE_CD <> SA.SALE_TYPE_CD);
-- ※ 뷰에는 기준일 조건을 넣지 않음. 사용하는 쪽에서 SALE_DT <= :BASE_DT.
--   본 이행은 동결 직후 수행하므로 "기준일 이후 취소"는 존재하지 않는 것이 정상.
--   리허설 시점과 동결 시점이 다르면 E.SALE_DT <= :BASE_DT 조건을 추가한 버전을 사용.

/* GWP: SA0109D 컬럼 확인 후 아래 컬럼명 수정 (GWP_CD / GWP_QTY 는 가정) */
CREATE OR REPLACE VIEW MIG_V_VALID_SALE_GWP AS
SELECT SA.COMP_CD, SA.STOR_CD, SA.SALE_DT, SA.POS_NO, SA.RCPT_NO, SA.BILL_NO,
       SA.BILL_PROC_CLS_CD, SA.GOOS_LOC_CLS_CD,
       G.SEQ,
       G.GWP_CD        AS GOOS_CD,     -- TODO: 실제 컬럼명
       G.GWP_QTY       AS GOOS_QTY,    -- TODO: 실제 컬럼명
       SA.STOC_STOR_CD, SA.STOC_CORN_CD
  FROM SA0100M SA
  JOIN SA0109D G
    ON G.COMP_CD = SA.COMP_CD AND G.STOR_CD = SA.STOR_CD AND G.SALE_DT = SA.SALE_DT
   AND G.POS_NO  = SA.POS_NO  AND G.RCPT_NO = SA.RCPT_NO
 WHERE SA.SALE_TYPE_CD = '1'
   AND NVL(SA.BILL_PROC_CLS_CD, '00') <> '08'
   AND NOT EXISTS (SELECT 1 FROM SA0100M E
                    WHERE E.COMP_CD = SA.COMP_CD AND E.STOR_CD = SA.STOR_CD
                      AND E.BILL_NO = SA.BILL_NO AND E.SALE_TYPE_CD <> SA.SALE_TYPE_CD);

/* 취소 판정 방식 차이 점검: SALE_TYPE 짝 방식 vs BILL_PROC_CLS_CD='08' 방식 */
SELECT 'PAIR_ONLY' GBN, COUNT(*) CNT
  FROM SA0100M SA
 WHERE SA.SALE_TYPE_CD = '1' AND NVL(SA.BILL_PROC_CLS_CD,'00') <> '08'
   AND EXISTS (SELECT 1 FROM SA0100M E WHERE E.COMP_CD=SA.COMP_CD AND E.STOR_CD=SA.STOR_CD
                                         AND E.BILL_NO=SA.BILL_NO AND E.SALE_TYPE_CD<>SA.SALE_TYPE_CD)
UNION ALL
SELECT 'STAT08_ONLY', COUNT(*)
  FROM SA0100M SA
 WHERE SA.SALE_TYPE_CD = '1' AND SA.BILL_PROC_CLS_CD = '08'
   AND NOT EXISTS (SELECT 1 FROM SA0100M E WHERE E.COMP_CD=SA.COMP_CD AND E.STOR_CD=SA.STOR_CD
                                             AND E.BILL_NO=SA.BILL_NO AND E.SALE_TYPE_CD<>SA.SALE_TYPE_CD);
-- 둘 다 0건이 이상적. 아니면 원인 확인 후 고객과 기준 확정.
