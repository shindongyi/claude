/* =====================================================================
   09. 신고 테이블(SR_ItemCarryIn_H / SR_ItemCarryIn_D)에 INSERT
   - 08 에서 만든 MIG_DECL_H / MIG_DECL_D 를 양식 컬럼 그대로 옮김
   - 대상 테이블 위치에 따라 둘 중 하나 사용
       [방법 1] 같은 Oracle DB 이거나 DB Link 가 있으면 → INSERT ... SELECT
       [방법 2] 다른 DB(SQL Server 등) 이면 → INSERT 문을 텍스트로 생성해서 대상 DB 에서 실행
   - 순서: Header → Detail (Detail 이 Header 를 참조)
   바인드: :RUN_ID
   ===================================================================== */

/* 0) 적재 전 확인: Header 마다 Detail 이 1~9999 건, 필수값 누락 없음 */
SELECT H.DECLARATION_NO, H.WH_CODE, COUNT(D.DOC_SEQ) ITEM_CNT
  FROM MIG_DECL_H H
  LEFT JOIN MIG_DECL_D D ON D.MIG_RUN_ID = H.MIG_RUN_ID AND D.DECLARATION_NO = H.DECLARATION_NO
                        AND D.WH_CODE = H.WH_CODE AND D.DOC_TYPE = H.DOC_TYPE
 WHERE H.MIG_RUN_ID = :RUN_ID
 GROUP BY H.DECLARATION_NO, H.WH_CODE
HAVING COUNT(D.DOC_SEQ) NOT BETWEEN 1 AND 9999;          -- 0건이어야 함

SELECT COUNT(*) MISSING_REQUIRED
  FROM MIG_DECL_D
 WHERE MIG_RUN_ID = :RUN_ID
   AND (ITEM_TYPE IS NULL OR HS_CODE IS NULL OR ITEM_CODE IS NULL OR ITEM_NAME IS NULL OR ITEM_NORM IS NULL
        OR ITEM_QTY IS NULL OR ITEM_COST IS NULL OR ITEM_AMOUNT IS NULL OR BRAND_CODE IS NULL
        OR BRAND_NAME IS NULL OR QTY_UNIT_CODE IS NULL);  -- 0건이어야 함

/* ================= [방법 1] INSERT ... SELECT (같은 DB / DB Link) ================= */
-- 대상이 DB Link 너머면 테이블명 뒤에 @링크명 (예: SR_ItemCarryIn_H@CSTM_LINK)

INSERT INTO SR_ItemCarryIn_H
      (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, reference_no,
       declaration_type, status, c_datetime, international_mail_yn)
SELECT DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, AMEND_TYPE, CARRYIN_LOC, REFERENCE_NO,
       DECLARATION_TYPE, STATUS, SYSDATE, INTERNATIONAL_MAIL_YN
  FROM MIG_DECL_H
 WHERE MIG_RUN_ID = :RUN_ID;

INSERT INTO SR_ItemCarryIn_D
      (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name,
       item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, unit_code,
       gwp_product_grade, register_no, item_cost_krw, qty_unit_code)
SELECT DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, NULL, ITEM_TYPE, HS_CODE, ITEM_CODE, ITEM_NAME,
       ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME, UNIT_CODE,
       GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE
  FROM MIG_DECL_D
 WHERE MIG_RUN_ID = :RUN_ID
 ORDER BY DECLARATION_NO, DOC_SEQ;

-- 적재 건수 확인 후 COMMIT
-- SELECT COUNT(*) FROM SR_ItemCarryIn_H WHERE declaration_no IN (SELECT DECLARATION_NO FROM MIG_DECL_H WHERE MIG_RUN_ID = :RUN_ID);
-- COMMIT;

/* ================= [방법 2] INSERT 문 생성 (다른 DB) =================
   - 결과 컬럼(SQL_TEXT)을 Toad 에서 텍스트로 저장 → 대상 DB 에서 실행
   - 문자열 안의 작은따옴표는 '' 로 이스케이프, 빈 값은 NULL
   - c_datetime 은 CURRENT_TIMESTAMP (SQL Server / Oracle 공통)                 */

-- Header
SELECT 'INSERT INTO SR_ItemCarryIn_H (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, '
    || 'reference_no, declaration_type, status, c_datetime, international_mail_yn) VALUES ('
    || '''' || DECLARATION_NO || ''', '
    || '''' || WH_CODE || ''', '
    || '''' || DOC_TYPE || ''', '
    || '''' || DECLARATION_DATE || ''', '
    || NVL2(AMEND_TYPE,   '''' || AMEND_TYPE   || '''', 'NULL') || ', '
    || NVL2(CARRYIN_LOC,  '''' || CARRYIN_LOC  || '''', 'NULL') || ', '
    || NVL2(REFERENCE_NO, '''' || REFERENCE_NO || '''', 'NULL') || ', '
    || '''' || DECLARATION_TYPE || ''', '
    || '''' || STATUS || ''', '
    || 'CURRENT_TIMESTAMP, '
    || NVL2(INTERNATIONAL_MAIL_YN, '''' || INTERNATIONAL_MAIL_YN || '''', 'NULL')
    || ');' AS SQL_TEXT
  FROM MIG_DECL_H
 WHERE MIG_RUN_ID = :RUN_ID
 ORDER BY DECLARATION_NO;

-- Detail
SELECT 'INSERT INTO SR_ItemCarryIn_D (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, '
    || 'item_code, item_name, item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, '
    || 'unit_code, gwp_product_grade, register_no, item_cost_krw, qty_unit_code) VALUES ('
    || '''' || DECLARATION_NO || ''', '
    || '''' || WH_CODE || ''', '
    || '''' || DOC_TYPE || ''', '
    || TO_CHAR(DOC_SEQ) || ', '
    || 'NULL, '
    || '''' || ITEM_TYPE || ''', '
    || '''' || HS_CODE || ''', '
    || '''' || REPLACE(ITEM_CODE, '''', '''''') || ''', '
    || '''' || REPLACE(ITEM_NAME, '''', '''''') || ''', '
    || '''' || REPLACE(ITEM_NORM, '''', '''''') || ''', '
    || TO_CHAR(ITEM_QTY) || ', '
    || TO_CHAR(ITEM_COST, 'FM99999999999990.00') || ', '
    || TO_CHAR(ITEM_AMOUNT, 'FM99999999999990.00') || ', '
    || NVL(TO_CHAR(CAPACITY, 'FM99990.00'), 'NULL') || ', '
    || '''' || REPLACE(BRAND_CODE, '''', '''''') || ''', '
    || '''' || REPLACE(BRAND_NAME, '''', '''''') || ''', '
    || NVL2(UNIT_CODE,         '''' || UNIT_CODE || '''', 'NULL') || ', '
    || NVL2(GWP_PRODUCT_GRADE, '''' || GWP_PRODUCT_GRADE || '''', 'NULL') || ', '
    || NVL2(REGISTER_NO,       '''' || REGISTER_NO || '''', 'NULL') || ', '
    || NVL(TO_CHAR(ITEM_COST_KRW), 'NULL') || ', '
    || '''' || QTY_UNIT_CODE || ''''
    || ');' AS SQL_TEXT
  FROM MIG_DECL_D
 WHERE MIG_RUN_ID = :RUN_ID
 ORDER BY DECLARATION_NO, DOC_SEQ;
-- 품목이 수만 건이면 파일이 커짐 → 대상 DB 의 대량적재(BULK INSERT / bcp 등)용 CSV 로 내리는 방법도 검토

/* 되돌리기 (리허설 정리용, 대상 DB 에서) — 이번 회차 신고번호만 삭제
DELETE FROM SR_ItemCarryIn_D WHERE declaration_no IN (...);
DELETE FROM SR_ItemCarryIn_H WHERE declaration_no IN (...);
*/
