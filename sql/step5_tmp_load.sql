/* =====================================================================
   STEP 5. TEMP 적재 → 검증 → 본테이블(SR_ItemCarryIn_H / _D) 적재
   ---------------------------------------------------------------------
   TEMP 2개 : TMP_ITEMCARRYIN_H / TMP_ITEMCARRYIN_D
     앞  : MIG_STEP (1 상품세관 / 2 상품통물 / 3 GWP / 4 미인도), BASE_DT, LOAD_DTTM
     중간: 신고 양식 컬럼 (순서 동일)   ※ 길이는 넉넉하게 → 양식 길이 초과는 검증 쿼리로 잡음
     뒤  : REF_ 참고 컬럼 (STEP 1~4 가 같은 순서로 출력하도록 맞춰 둠)
   ===================================================================== */

/* ---------------------------------------------------------------------
   1. TEMP DDL
   --------------------------------------------------------------------- */
CREATE TABLE TMP_ITEMCARRYIN_H (
    MIG_STEP              NUMBER(1)     NOT NULL,   -- 1 상품세관 / 2 상품통물 / 3 GWP / 4 미인도
    BASE_DT               VARCHAR2(8)   NOT NULL,   -- 기준일 20261130
    LOAD_DTTM             DATE          NOT NULL,
    -- 신고 양식 (SR_ItemCarryIn_H)
    DECLARATION_NO        VARCHAR2(40),             -- 양식 27
    WH_CODE               VARCHAR2(20),             -- 양식 8
    DOC_TYPE              VARCHAR2(3),
    DECLARATION_DATE      VARCHAR2(8),
    AMEND_TYPE            VARCHAR2(3),
    CARRYIN_LOC           VARCHAR2(30),             -- 양식 8
    REFERENCE_NO          VARCHAR2(24),
    DECLARATION_TYPE      VARCHAR2(1),
    STATUS                VARCHAR2(2),
    C_DATETIME            DATE,
    INTERNATIONAL_MAIL_YN VARCHAR2(1),
    -- 참고
    REF_STOR_NM           VARCHAR2(50),
    REF_SITE              VARCHAR2(10),
    REF_ITEM_CNT          NUMBER,
    REF_BILL_CNT          NUMBER,
    REF_QTY               NUMBER,
    REF_QTY_GOODS         NUMBER,
    REF_QTY_GWP           NUMBER,
    REF_Q_CSTM            NUMBER,
    REF_Q_SUBUL           NUMBER,
    REF_Q_EXCH            NUMBER,
    REF_Q_HREENT          NUMBER,
    REF_Q_UDLV            NUMBER
);

CREATE TABLE TMP_ITEMCARRYIN_D (
    MIG_STEP              NUMBER(1)     NOT NULL,
    BASE_DT               VARCHAR2(8)   NOT NULL,
    LOAD_DTTM             DATE          NOT NULL,
    -- 신고 양식 (SR_ItemCarryIn_D)
    DECLARATION_NO        VARCHAR2(40),             -- 양식 27
    WH_CODE               VARCHAR2(20),             -- 양식 8
    DOC_TYPE              VARCHAR2(3),
    DOC_SEQ               NUMBER,                   -- 1 ~ 9999
    RAMEND_TYPE           VARCHAR2(2),
    ITEM_TYPE             VARCHAR2(1),              -- T / W / H / D
    HS_CODE               VARCHAR2(20),             -- 양식 10
    ITEM_CODE             VARCHAR2(40),             -- 양식 24
    ITEM_NAME             VARCHAR2(500),            -- 양식 200
    ITEM_NORM             VARCHAR2(100),            -- 양식 50
    ITEM_QTY              NUMBER,                   -- 양식 numeric(10,0)
    ITEM_COST             NUMBER,                   -- 양식 numeric(16,2)
    ITEM_AMOUNT           NUMBER,                   -- 양식 numeric(16,2)
    CAPACITY              VARCHAR2(50),             -- 양식 numeric(7,2) — 원천 형식이 문자일 수 있어 문자로 받고 적재 때 변환
    BRAND_CODE            VARCHAR2(30),             -- 양식 10
    BRAND_NAME            VARCHAR2(300),            -- 양식 200
    UNIT_CODE             VARCHAR2(10),             -- 양식 char(2)
    GWP_PRODUCT_GRADE     VARCHAR2(10),             -- 양식 char(1)
    REGISTER_NO           VARCHAR2(30),             -- 양식 24
    ITEM_COST_KRW         NUMBER,                   -- 양식 numeric(18,0)
    QTY_UNIT_CODE         VARCHAR2(10),
    -- 참고
    REF_STOR_NM           VARCHAR2(50),
    REF_SHED_CD           VARCHAR2(30),
    REF_SITE              VARCHAR2(10),
    REF_GOOS_CD           VARCHAR2(30),
    REF_GOOS_GWP          VARCHAR2(10),
    REF_MATCH_BY          VARCHAR2(20),
    REF_REF_NO            VARCHAR2(100),
    REF_BILL_STAT         VARCHAR2(10),
    REF_PMIT_CNT          NUMBER,
    REF_Q_CSTM            NUMBER,
    REF_Q_SUBUL           NUMBER,
    REF_Q_EXCH            NUMBER,
    REF_Q_HREENT          NUMBER,
    REF_Q_UDLV            NUMBER
);
-- 채번용 컬럼 (PL/SQL 적재 → 채번 2단계 방식)
ALTER TABLE TMP_ITEMCARRYIN_H ADD (DECL_KEY VARCHAR2(100), NO_PREFIX VARCHAR2(20));
ALTER TABLE TMP_ITEMCARRYIN_D ADD (DECL_KEY VARCHAR2(100));
CREATE INDEX TMP_ITEMCARRYIN_D_IX2 ON TMP_ITEMCARRYIN_D (DECL_KEY);
CREATE INDEX TMP_ITEMCARRYIN_D_IX1 ON TMP_ITEMCARRYIN_D (DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ);
CREATE INDEX TMP_ITEMCARRYIN_H_IX1 ON TMP_ITEMCARRYIN_H (DECLARATION_NO, WH_CODE, DOC_TYPE);


/* ---------------------------------------------------------------------
   2. STEP 1~4 적재 (래핑) — STEP 마다 Header 1번, Detail 1번
      ( ) 안에 해당 STEP 파일의 [Detail] / [Header] 쿼리를 WITH 부터 그대로 붙여넣기 (끝의 ; 만 빼기)

   INSERT INTO TMP_ITEMCARRYIN_D
   SELECT 1, '20261130', SYSDATE, Q.*          -- ← 숫자를 STEP 번호로 (1·2·3·4)
     FROM ( <STEP n 의 [Detail] 쿼리> ) Q;

   INSERT INTO TMP_ITEMCARRYIN_H
   SELECT 1, '20261130', SYSDATE, Q.*
     FROM ( <STEP n 의 [Header] 쿼리> ) Q;

   - 다시 넣을 때: DELETE FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP = n;  (H 도 같이)
   - "ORA-00913 값의 수가 너무 많습니다 / 적습니다" → 그 STEP 쿼리의 SELECT 컬럼 수가 TEMP 와 다름 (수정했으면 알려주기)
   - WITH 를 괄호 안에 넣는 게 안 되는 DB 버전이면:
       INSERT INTO TMP_ITEMCARRYIN_D
       WITH ... (그대로)
       SELECT 1, '20261130', SYSDATE, X.DECLARATION_NO ...   ← 마지막 SELECT 맨 앞에 세 값만 추가
   --------------------------------------------------------------------- */



/* ---------------------------------------------------------------------
   2-1. [채번] — STEP 1·2·3·4 PL/SQL 적재를 COMMIT 한 다음 실행
        FN_MA_AUTO_NO 가 내부에서 COMMIT 하므로 적재와 분리함
        - 신고번호가 비어 있는 Header 만 채번 → 중간에 실패해도 다시 돌리면 남은 것만 이어서 채번
        - Header 1건마다 : 채번 1번 → Header·Detail(같은 DECL_KEY) 에 같은 번호 → COMMIT
   --------------------------------------------------------------------- */
DECLARE
    V_REGR_ID   VARCHAR2(10) := 'MIG';            -- 채번 등록자 (확인)
    V_NO        VARCHAR2(27);
    V_CNT       NUMBER := 0;
    V_D_CNT     NUMBER := 0;
    V_CUR_KEY   VARCHAR2(100);
BEGIN
    DBMS_OUTPUT.ENABLE(NULL);

    FOR H IN (SELECT ROWID AS RID, DECL_KEY, NO_PREFIX
                FROM TMP_ITEMCARRYIN_H
               WHERE DECLARATION_NO IS NULL
               ORDER BY MIG_STEP, DECL_KEY)
    LOOP
        V_CUR_KEY := H.DECL_KEY;

        IF H.NO_PREFIX IS NULL OR LENGTH(H.NO_PREFIX) < 16 THEN
            RAISE_APPLICATION_ERROR(-20002, '채번 접두 이상 : ' || H.DECL_KEY);
        END IF;

        V_NO := FN_MA_AUTO_NO('01', 'BO15', H.NO_PREFIX, V_REGR_ID);   -- 함수 안에서 COMMIT

        UPDATE TMP_ITEMCARRYIN_H SET DECLARATION_NO = V_NO WHERE ROWID    = H.RID;
        UPDATE TMP_ITEMCARRYIN_D SET DECLARATION_NO = V_NO WHERE DECL_KEY = H.DECL_KEY;
        V_D_CNT := V_D_CNT + SQL%ROWCOUNT;

        COMMIT;
        V_CNT := V_CNT + 1;
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('채번 SUCCESS  Header = ' || V_CNT || ' / Detail = ' || V_D_CNT);

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;                                  -- 진행 중이던 1건만 되돌림 (앞서 채번된 건은 유지)
        DBMS_OUTPUT.PUT_LINE('FAIL 위치 : ' || V_CUR_KEY);
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        DBMS_OUTPUT.PUT_LINE('→ 원인 해결 후 다시 실행하면 비어 있는 것만 이어서 채번');
        RAISE;
END;
/

-- 채번 확인 : 0 이어야 함
SELECT 'H_NO_NULL' CHK, COUNT(*) CNT FROM TMP_ITEMCARRYIN_H WHERE DECLARATION_NO IS NULL
UNION ALL
SELECT 'D_NO_NULL', COUNT(*) FROM TMP_ITEMCARRYIN_D WHERE DECLARATION_NO IS NULL;

/* ---------------------------------------------------------------------
   3. 검증  (모두 0건 / 일치가 정상)
   --------------------------------------------------------------------- */

-- V1. STEP 별 요약 (사인오프용) — Header 의 REF_QTY 합 = Detail 의 ITEM_QTY 합
SELECT D.MIG_STEP, D.WH_CODE, NVL(H.CARRYIN_LOC, '(자기장치장)') CARRYIN_LOC, H.DECLARATION_TYPE,
       COUNT(DISTINCT D.DECLARATION_NO) DECL_CNT, COUNT(*) ITEM_CNT, SUM(D.ITEM_QTY) QTY,
       SUM(D.REF_Q_CSTM) Q_CSTM, SUM(D.REF_Q_SUBUL) Q_SUBUL, SUM(D.REF_Q_EXCH) Q_EXCH,
       SUM(D.REF_Q_HREENT) Q_HREENT, SUM(D.REF_Q_UDLV) Q_UDLV
  FROM TMP_ITEMCARRYIN_D D
  LEFT JOIN TMP_ITEMCARRYIN_H H
    ON H.DECLARATION_NO = D.DECLARATION_NO AND H.WH_CODE = D.WH_CODE AND H.DOC_TYPE = D.DOC_TYPE
 GROUP BY D.MIG_STEP, D.WH_CODE, NVL(H.CARRYIN_LOC, '(자기장치장)'), H.DECLARATION_TYPE
 ORDER BY 1, 2, 3;

-- V2. 키 중복 (Header 신고번호 / Detail 신고번호+품목순번)
SELECT 'H_DUP' CHK, DECLARATION_NO, WH_CODE, DOC_TYPE, NULL DOC_SEQ, COUNT(*) CNT
  FROM TMP_ITEMCARRYIN_H GROUP BY DECLARATION_NO, WH_CODE, DOC_TYPE HAVING COUNT(*) > 1
UNION ALL
SELECT 'D_DUP', DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, COUNT(*)
  FROM TMP_ITEMCARRYIN_D GROUP BY DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ HAVING COUNT(*) > 1;

-- V3. 짝 안 맞음 (Detail 없는 Header / Header 없는 Detail) + 신고서당 품목 1~9999
SELECT 'H_NO_D' CHK, H.DECLARATION_NO, H.MIG_STEP FROM TMP_ITEMCARRYIN_H H
 WHERE NOT EXISTS (SELECT 1 FROM TMP_ITEMCARRYIN_D D WHERE D.DECLARATION_NO = H.DECLARATION_NO
                      AND D.WH_CODE = H.WH_CODE AND D.DOC_TYPE = H.DOC_TYPE)
UNION ALL
SELECT DISTINCT 'D_NO_H', D.DECLARATION_NO, D.MIG_STEP FROM TMP_ITEMCARRYIN_D D
 WHERE NOT EXISTS (SELECT 1 FROM TMP_ITEMCARRYIN_H H WHERE H.DECLARATION_NO = D.DECLARATION_NO
                      AND H.WH_CODE = D.WH_CODE AND H.DOC_TYPE = D.DOC_TYPE)
UNION ALL
SELECT 'SEQ_OVER', DECLARATION_NO, MAX(MIG_STEP) FROM TMP_ITEMCARRYIN_D
 GROUP BY DECLARATION_NO HAVING COUNT(*) > 9999 OR MAX(DOC_SEQ) > 9999 OR MIN(DOC_SEQ) < 1;

-- V4. 필수값 누락 (NOT NULL 컬럼) — 항목별 건수
SELECT MIG_STEP,
       SUM(CASE WHEN ITEM_TYPE     IS NULL THEN 1 ELSE 0 END) NO_ITEM_TYPE,
       SUM(CASE WHEN HS_CODE       IS NULL THEN 1 ELSE 0 END) NO_HS_CODE,
       SUM(CASE WHEN ITEM_CODE     IS NULL THEN 1 ELSE 0 END) NO_ITEM_CODE,
       SUM(CASE WHEN ITEM_NAME     IS NULL OR TRIM(ITEM_NAME) IS NULL THEN 1 ELSE 0 END) NO_ITEM_NAME,
       SUM(CASE WHEN ITEM_NORM     IS NULL THEN 1 ELSE 0 END) NO_ITEM_NORM,
       SUM(CASE WHEN ITEM_COST     IS NULL THEN 1 ELSE 0 END) NO_ITEM_COST,
       SUM(CASE WHEN ITEM_AMOUNT   IS NULL THEN 1 ELSE 0 END) NO_ITEM_AMOUNT,
       SUM(CASE WHEN BRAND_CODE    IS NULL THEN 1 ELSE 0 END) NO_BRAND_CODE,
       SUM(CASE WHEN BRAND_NAME    IS NULL THEN 1 ELSE 0 END) NO_BRAND_NAME,
       SUM(CASE WHEN QTY_UNIT_CODE IS NULL THEN 1 ELSE 0 END) NO_QTY_UNIT,
       COUNT(*) TOTAL
  FROM TMP_ITEMCARRYIN_D
 GROUP BY MIG_STEP ORDER BY 1;

-- V5. 양식 길이·형식 위반 / 미확정 값('?', '미매핑') 남아 있음
SELECT MIG_STEP, CHK, COUNT(*) CNT
  FROM (SELECT MIG_STEP,
               CASE WHEN DECLARATION_NO LIKE '%?%'           THEN '신고번호에 ? (세관·과·접두문자 미확정)'
                    WHEN LENGTH(DECLARATION_NO) NOT IN (24, 27) THEN '신고번호 길이'
                    WHEN LENGTH(WH_CODE) <> 8                  THEN '신고지점 길이'
                    WHEN LENGTH(ITEM_CODE) > 24               THEN '상품코드 24 초과'
                    WHEN LENGTH(HS_CODE) > 10                 THEN 'HS코드 10 초과'
                    WHEN LENGTHB(ITEM_NAME) > 200             THEN '품명 200 초과'
                    WHEN LENGTHB(BRAND_NAME) > 200            THEN '브랜드명 200 초과'
                    WHEN LENGTH(BRAND_CODE) > 10              THEN '브랜드코드 10 초과'
                    WHEN LENGTH(UNIT_CODE) > 2                THEN '용량단위 2 초과'
                    WHEN LENGTH(GWP_PRODUCT_GRADE) > 1        THEN 'GWP등급 1 초과'
                    WHEN LENGTH(REGISTER_NO) > 24             THEN '참조번호 24 초과'
                    WHEN CAPACITY IS NOT NULL
                     AND NOT REGEXP_LIKE(CAPACITY, '^[0-9]{1,5}(\.[0-9]{1,2})?$') THEN '용량 숫자형식(7,2) 아님'
                    WHEN ITEM_TYPE NOT IN ('T', 'W', 'H', 'D')  THEN '물품구분 값'
                    WHEN ITEM_QTY IS NULL OR ITEM_QTY <= 0 OR ITEM_QTY <> TRUNC(ITEM_QTY) THEN '수량 0이하/소수'
                    WHEN ITEM_AMOUNT <> ROUND(ITEM_QTY * ITEM_COST, 2) THEN '금액 ≠ 수량×단가'
               END CHK
          FROM TMP_ITEMCARRYIN_D)
 WHERE CHK IS NOT NULL
 GROUP BY MIG_STEP, CHK
UNION ALL
SELECT MIG_STEP,
       CASE WHEN CARRYIN_LOC LIKE '%?%' OR CARRYIN_LOC LIKE '미매핑%' THEN '반입장치장소 미확정'
            WHEN LENGTH(CARRYIN_LOC) <> 8 THEN '반입장치장소 길이'
            WHEN DECLARATION_TYPE NOT IN ('Z', 'Y') THEN '신고구분 값' END,
       COUNT(*)
  FROM TMP_ITEMCARRYIN_H
 WHERE CARRYIN_LOC LIKE '%?%' OR CARRYIN_LOC LIKE '미매핑%' OR LENGTH(CARRYIN_LOC) <> 8
    OR DECLARATION_TYPE NOT IN ('Z', 'Y')
 GROUP BY MIG_STEP,
          CASE WHEN CARRYIN_LOC LIKE '%?%' OR CARRYIN_LOC LIKE '미매핑%' THEN '반입장치장소 미확정'
               WHEN LENGTH(CARRYIN_LOC) <> 8 THEN '반입장치장소 길이'
               WHEN DECLARATION_TYPE NOT IN ('Z', 'Y') THEN '신고구분 값' END
 ORDER BY 1, 2;

-- V6. 신고구분과 참조번호: Y(미인도) 는 교환권번호 필수, Z 는 공백
SELECT H.DECLARATION_TYPE,
       SUM(CASE WHEN D.REGISTER_NO IS NULL THEN 1 ELSE 0 END)     NO_REGISTER_NO,
       SUM(CASE WHEN D.REGISTER_NO IS NOT NULL THEN 1 ELSE 0 END) HAS_REGISTER_NO
  FROM TMP_ITEMCARRYIN_D D
  JOIN TMP_ITEMCARRYIN_H H ON H.DECLARATION_NO = D.DECLARATION_NO AND H.WH_CODE = D.WH_CODE AND H.DOC_TYPE = D.DOC_TYPE
 GROUP BY H.DECLARATION_TYPE;                    -- Y: NO_REGISTER_NO = 0 / Z: HAS_REGISTER_NO = 0

-- V7. 이중 계상: 같은 보세구역·장치장·상품코드가 정상(Z)에 여러 STEP 으로 들어감 → 0건이어야 함
SELECT D.WH_CODE, NVL(H.CARRYIN_LOC, '(자기장치장)') CARRYIN_LOC, D.ITEM_CODE,
       LISTAGG(DISTINCT D.MIG_STEP, ',') WITHIN GROUP (ORDER BY D.MIG_STEP) STEPS, SUM(D.ITEM_QTY) QTY
  FROM TMP_ITEMCARRYIN_D D
  JOIN TMP_ITEMCARRYIN_H H ON H.DECLARATION_NO = D.DECLARATION_NO AND H.WH_CODE = D.WH_CODE AND H.DOC_TYPE = D.DOC_TYPE
 WHERE H.DECLARATION_TYPE = 'Z'
 GROUP BY D.WH_CODE, NVL(H.CARRYIN_LOC, '(자기장치장)'), D.ITEM_CODE
HAVING COUNT(DISTINCT D.MIG_STEP) > 1;
-- ※ LISTAGG(DISTINCT ...) 가 안 되는 버전(19c 미만)이면 MIN(MIG_STEP), MAX(MIG_STEP) 로 바꿔서

-- V8. 미인도 대사 (통물만): STEP 2·3 에서 뺀 미인도(REF_Q_UDLV 음수) = STEP 4 의 Y 수량 중 통물 장치장분
--     ※ 본점 자기 장치장 미인도는 STEP 1 에서 안 빼므로 대사 대상 아님 (B 쪽에만 나오면 정상)
SELECT NVL(A.WH_CODE, B.WH_CODE) WH_CODE, NVL(A.SHED_CD, B.SHED_CD) SHED_CD,
       A.MINUS_QTY, B.Y_QTY, NVL(A.MINUS_QTY, 0) - NVL(B.Y_QTY, 0) DIFF
  FROM (SELECT WH_CODE, REF_SHED_CD SHED_CD, -SUM(REF_Q_UDLV) MINUS_QTY
          FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP IN (2, 3) GROUP BY WH_CODE, REF_SHED_CD) A
  FULL OUTER JOIN
       (SELECT WH_CODE, REF_SHED_CD SHED_CD, SUM(ITEM_QTY) Y_QTY
          FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP = 4 GROUP BY WH_CODE, REF_SHED_CD) B
    ON B.WH_CODE = A.WH_CODE AND B.SHED_CD = A.SHED_CD
 ORDER BY 1, 2;
-- ※ 차이가 나는 대표 원인: STEP 2·3 에서 "0 이하라 신고 제외"된 상품의 미인도분 (그 상품은 Z 에 안 나와서 REF_Q_UDLV 도 빠짐)

-- V9. 구코드 / 환급코드 미매칭 / 매핑 방식 요약
SELECT MIG_STEP, REF_GOOS_GWP, ITEM_TYPE, REF_MATCH_BY, COUNT(*) CNT, SUM(ITEM_QTY) QTY
  FROM TMP_ITEMCARRYIN_D
 GROUP BY MIG_STEP, REF_GOOS_GWP, ITEM_TYPE, REF_MATCH_BY
 ORDER BY 1, 2, 3, 4;                            -- NO_MASTER(구코드) / NO_TYPE / W_RULE 확인


/* ---------------------------------------------------------------------
   4. 본테이블 적재 (검증 통과 후) — Header 먼저, Detail 나중
   --------------------------------------------------------------------- */
INSERT INTO SR_ItemCarryIn_H
      (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, reference_no,
       declaration_type, status, c_datetime, international_mail_yn)
SELECT DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, AMEND_TYPE, CARRYIN_LOC, REFERENCE_NO,
       DECLARATION_TYPE, STATUS, SYSDATE, INTERNATIONAL_MAIL_YN
  FROM TMP_ITEMCARRYIN_H
 ORDER BY MIG_STEP, DECLARATION_NO;

INSERT INTO SR_ItemCarryIn_D
      (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name,
       item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, unit_code,
       gwp_product_grade, register_no, item_cost_krw, qty_unit_code)
SELECT DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, RAMEND_TYPE, ITEM_TYPE, HS_CODE, ITEM_CODE, ITEM_NAME,
       ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, TO_NUMBER(CAPACITY), BRAND_CODE, BRAND_NAME, UNIT_CODE,
       GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE
  FROM TMP_ITEMCARRYIN_D
 ORDER BY MIG_STEP, DECLARATION_NO, DOC_SEQ;

-- 건수 확인: TMP 건수 = 적재 건수 → COMMIT
-- 대상 테이블이 다른 DB 면 위 INSERT 대신 sql/09_insert_target.sql 의 "INSERT 문 생성" 방식으로 (FROM 만 TMP 로)
