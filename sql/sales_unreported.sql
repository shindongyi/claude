/* ==========================================================================
   판매미신고 마이그 — 판매(정정)신고서 SR_Sales_H / SR_Sales_D
   --------------------------------------------------------------------------
   대상   : 본점(05) 판매분, 판매취소 아닌 교환권
            빌상태   01 면장등록 / 02 면장확정
            상품위치 01 점포 / 02 통물 / 11 점미래보세 / 12 통물미래보세
   우선   : 당일(신고일) 출국 1 → 이후 출국 2 → 출국일 지남·없음 3

   신고번호 : 채번 함수 FN_MA_AUTO_NO 로 발급 (신고서 = 교환권 1건마다 1번만 호출)
              FN_MA_AUTO_NO( 회사코드
                           , 'MA76'                                  -- MA053 채번구분 : 판매신고
                           , 세관(MA041 속성1) || 과(MA041 속성2) || 보세구역 || 년도(YY) || 'C'
                           , 등록자ID )

   순서   : 1) TEMP DDL
            2) Header 적재  ← 여기서 채번 (교환권마다 1번)
            3) Detail 적재  ← Header 의 신고번호를 그대로 가져옴 (Header-Detail 쌍)
            4) 검증
            5) 본테이블 적재
   ========================================================================== */


/* ==========================================================================
   1) TEMP DDL
   ========================================================================== */
CREATE TABLE TMP_SALES_H
(
      DECLARATION_NO           VARCHAR2(27)
    , WH_CODE                  VARCHAR2(8)
    , DOC_TYPE                 VARCHAR2(3)
    , DECLARATION_DATE         VARCHAR2(8)
    , AMEND_TYPE               VARCHAR2(3)
    , DECLARATION_TYPE         VARCHAR2(1)
    , STATUS                   VARCHAR2(2)
    , C_DATETIME               DATE
    , SALE_DATE                VARCHAR2(14)
    , ITEM_AMEND_TYPE          VARCHAR2(1)
    , DELIVERY_METHOD          VARCHAR2(1)
    , DOMESTIC_TYPE            VARCHAR2(1)
    , BUYER_NAME               VARCHAR2(200)
    , NATIONALITY              VARCHAR2(10)
    , EXCHANGE_NO              VARCHAR2(30)
    , PERSONAL_TYPE            VARCHAR2(1)
    , PERSONAL_VALUE           VARCHAR2(200)
    , BIRTH_DATE               VARCHAR2(8)
    , DEPARTURE_ARRIVE_TYPE    VARCHAR2(1)
    , DEPARTURE_ARRIVE_DATE    VARCHAR2(8)
    , FLIGHT_NO                VARCHAR2(30)
    , EXCHANGE_RATE            NUMBER
    , ELECTRONIC_COMMERCE_YN   VARCHAR2(1)
    , CARRYOUT_LOC             VARCHAR2(8)
    -- 참고 (Detail 연결키 + 검토용)
    , REF_COMP_CD              VARCHAR2(2)
    , REF_STOR_CD              VARCHAR2(10)
    , REF_SALE_DT              VARCHAR2(8)
    , REF_POS_NO               VARCHAR2(10)
    , REF_RCPT_NO              NUMBER
    , REF_PRIORITY             NUMBER(1)
    , REF_BILL_STAT            VARCHAR2(2)
    , REF_GOOS_LOC             VARCHAR2(2)
    , REF_NATI_CD              VARCHAR2(10)
    , REF_NET_USD              NUMBER
);

CREATE TABLE TMP_SALES_D
(
      DECLARATION_NO           VARCHAR2(27)
    , WH_CODE                  VARCHAR2(8)
    , DOC_TYPE                 VARCHAR2(3)
    , DOC_SEQ                  NUMBER
    , RAMEND_TYPE              VARCHAR2(2)
    , ITEM_TYPE                VARCHAR2(1)
    , HS_CODE                  VARCHAR2(20)
    , ITEM_CODE                VARCHAR2(30)
    , ITEM_NAME                VARCHAR2(500)
    , ITEM_NORM                VARCHAR2(100)
    , ITEM_QTY                 NUMBER
    , ITEM_COST                NUMBER
    , ITEM_AMOUNT              NUMBER
    , MAKE_TYPE                VARCHAR2(1)
    , EVENT_TYPE_CODE          VARCHAR2(1)
    , ITEM_COST_KRW            NUMBER
    , NORM_UNIT_PRICE_USD      NUMBER
    , NORM_UNIT_PRICE_KRW      NUMBER
    , CAPACITY                 VARCHAR2(50)
    , BRAND_CODE               VARCHAR2(30)
    , BRAND_NAME               VARCHAR2(300)
    , UNIT_CODE                VARCHAR2(10)
    , GWP_PRODUCT_GRADE        VARCHAR2(10)
    , GWP_LINK_ITEM_CODE       VARCHAR2(30)
    , QTY_UNIT_CODE            VARCHAR2(10)
    -- 참고
    , REF_EXCHANGE_NO          VARCHAR2(30)
    , REF_GOOS_GWP             VARCHAR2(10)
    , REF_GOOS_CD              VARCHAR2(30)
);


/* ==========================================================================
   2) Header 적재 — 교환권 1건 = 신고서 1건, 여기서 채번
      ※ 채번 함수는 행마다 1번씩 불림 → 이 INSERT 는 한 번만 실행 (다시 돌리면 번호가 또 나감)
   ========================================================================== */
INSERT INTO TMP_SALES_H
WITH
PRM AS (
    SELECT '01'       AS COMP_CD
         , '20261130' AS BASE_DT
         , '20261201' AS DECL_DT
      FROM DUAL
),
BOND AS (                                                 -- 본점 (신고구분 E 인도장 인도판매 / 인도방법 E 출국장인도장, 확인)
    SELECT '05'       AS STOR_CD
         , '01022006' AS BOND_GRN_CD
         , 'E'        AS DECL_TYPE
         , 'E'        AS DELIV_METHOD
      FROM DUAL
),
TONG AS (                                                 -- 통물 코너 → 통물 장치장 (961/965 배정은 가정)
    SELECT '961' AS CORN_CD, '04077090' AS SHED_CD FROM DUAL UNION ALL
    SELECT '965' AS CORN_CD, '04077137' AS SHED_CD FROM DUAL
),
EXCH AS (                                                 -- 환율 : MA0140I 매매기준환율, 매출기준일자별
    SELECT X.SALE_STD_DT
         , MAX(X.TRD_STD_EXCH_RTE) KEEP (DENSE_RANK LAST ORDER BY X.EXCH_RTE_NOTI_DT) AS TRD_STD_EXCH_RTE
      FROM MA0140I X
     WHERE X.COMP_CD = '01'
       AND X.CUR_CD  = 'USD'
       AND X.SALE_STD_DT IS NOT NULL
     GROUP BY X.SALE_STD_DT
),
BILL AS (                                                 -- 대상 교환권
    SELECT A.*
         , B.BOND_GRN_CD
         , B.DECL_TYPE
         , B.DELIV_METHOD
         , CASE WHEN A.DPAT_DT = P.DECL_DT THEN 1
                WHEN A.DPAT_DT > P.DECL_DT THEN 2
                ELSE 3 END                 AS PRIORITY
      FROM SA0100M A
      JOIN BOND B
        ON B.STOR_CD = A.STOR_CD
     CROSS JOIN PRM P
     WHERE A.COMP_CD          = P.COMP_CD
       AND A.SALE_TYPE_CD     = '1'
       AND A.SALE_DT         <= P.BASE_DT
       AND A.BILL_PROC_CLS_CD IN ('01', '02')                  -- 면장등록 / 면장확정
       AND A.GOOS_LOC_CLS_CD  IN ('01', '02', '11', '12')      -- 점포 / 통물 / 점미래보세 / 통물미래보세
       AND NOT EXISTS (SELECT 1                                -- 판매취소가 아닌것 (다른 날 취소 포함)
                         FROM SA0100M E
                        WHERE E.COMP_CD       = A.COMP_CD
                          AND E.STOR_CD       = A.STOR_CD
                          AND E.BILL_NO       = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT      <= P.BASE_DT)
),
SRC AS (                                                  -- 채번 전 Header 값 (우선순위 순으로 정렬)
    SELECT B.BOND_GRN_CD                                                  AS WH_CODE
         , P.DECL_DT                                                      AS DECLARATION_DATE
         , B.DECL_TYPE                                                    AS DECLARATION_TYPE
         , B.SALE_DT || NVL(RPAD(B.SYSM_TM, 6, '0'), '000000')            AS SALE_DATE
         , B.DELIV_METHOD                                                 AS DELIVERY_METHOD
         , CASE WHEN B.NATI_CD = 'KOR' THEN '1' ELSE '2' END              AS DOMESTIC_TYPE
         , B.CUST_NM                                                      AS BUYER_NAME            -- ※ 암호화 → 복호화 함수
         , NA.COMM_PROP_CONT_1                                            AS NATIONALITY           -- MA024 2자리 코드 속성 확인
         , B.BILL_NO                                                      AS EXCHANGE_NO
         , CASE WHEN B.PSPT_NO IS NOT NULL THEN '1' END                   AS PERSONAL_TYPE         -- 1 여권번호
         , B.PSPT_NO                                                      AS PERSONAL_VALUE        -- ※ 암호화 → 복호화 함수
         , B.BIRT_DT                                                      AS BIRTH_DATE
         , B.DPAT_DT                                                      AS DEPARTURE_ARRIVE_DATE
         , B.OPEN_NM                                                      AS FLIGHT_NO
         , ROUND(NVL(X.TRD_STD_EXCH_RTE, 0), 2)                           AS EXCHANGE_RATE
         , CASE WHEN B.SALE_CRS_CLS_CD = 'OFF' THEN 'N' ELSE 'Y' END      AS ELECTRONIC_COMMERCE_YN
         , CASE WHEN B.GOOS_LOC_CLS_CD IN ('02', '12') THEN T.SHED_CD END AS CARRYOUT_LOC
         -- 채번 접두 : 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'C'(판매)
         , N.COMM_PROP_CONT_1 || N.COMM_PROP_CONT_2 || B.BOND_GRN_CD
           || TO_CHAR(SYSDATE, 'YY') || 'C'                               AS NO_PREFIX
         -- 참고
         , B.COMP_CD
         , B.STOR_CD
         , B.SALE_DT
         , B.POS_NO
         , B.RCPT_NO
         , B.PRIORITY
         , B.BILL_PROC_CLS_CD
         , B.GOOS_LOC_CLS_CD
         , B.NATI_CD
         , B.NET_SELL_DOLR_AMT
      FROM BILL B
     CROSS JOIN PRM P
      LEFT JOIN MA0151D N                                 -- 보세구역 → 세관·과 코드
        ON N.COMP_CD         = '01'
       AND N.WRK_MDUL_CD     = 'MA'
       AND N.COMM_CTG_CD     = 'MA041'
       AND N.COMM_CTG_DTL_CD = B.BOND_GRN_CD
      LEFT JOIN MA0151D NA                                -- 국가코드
        ON NA.COMP_CD         = '01'
       AND NA.WRK_MDUL_CD     = 'MA'
       AND NA.COMM_CTG_CD     = 'MA024'
       AND NA.COMM_CTG_DTL_CD = B.NATI_CD
      LEFT JOIN TONG T
        ON T.CORN_CD = B.STOC_CORN_CD
      LEFT JOIN EXCH X
        ON X.SALE_STD_DT = B.SALE_DT
     ORDER BY B.PRIORITY, B.DPAT_DT, B.SALE_DT, B.BILL_NO
)
SELECT FN_MA_AUTO_NO(S.COMP_CD, 'MA76', S.NO_PREFIX, 'MIG')  AS DECLARATION_NO          --  1 신고번호 (채번)
     , S.WH_CODE                                             AS WH_CODE                 --  2 보세판매장부호
     , 'DL8'                                                 AS DOC_TYPE                --  3 문서구분 판매신고
     , S.DECLARATION_DATE                                    AS DECLARATION_DATE        --  4 신고일자
     , NULL                                                  AS AMEND_TYPE              --  5 정정구분
     , S.DECLARATION_TYPE                                    AS DECLARATION_TYPE        --  6 신고구분
     , 'A1'                                                  AS STATUS                  --  7 상태
     , SYSDATE                                               AS C_DATETIME              --  8 생성일시
     , S.SALE_DATE                                           AS SALE_DATE               --  9 판매일시
     , NULL                                                  AS ITEM_AMEND_TYPE         -- 10 품목정정신고구분
     , S.DELIVERY_METHOD                                     AS DELIVERY_METHOD         -- 11 인도방법
     , S.DOMESTIC_TYPE                                       AS DOMESTIC_TYPE           -- 12 내국인/외국인
     , S.BUYER_NAME                                          AS BUYER_NAME              -- 13 구매자영문성명
     , S.NATIONALITY                                         AS NATIONALITY             -- 14 국적코드
     , S.EXCHANGE_NO                                         AS EXCHANGE_NO             -- 15 교환권번호
     , S.PERSONAL_TYPE                                       AS PERSONAL_TYPE           -- 16 개인정보식별구분
     , S.PERSONAL_VALUE                                      AS PERSONAL_VALUE          -- 17 개인정보식별값
     , S.BIRTH_DATE                                          AS BIRTH_DATE              -- 18 생년월일
     , 'D'                                                   AS DEPARTURE_ARRIVE_TYPE   -- 19 입/출국 D 출국
     , S.DEPARTURE_ARRIVE_DATE                               AS DEPARTURE_ARRIVE_DATE   -- 20 출국예정일자
     , S.FLIGHT_NO                                           AS FLIGHT_NO               -- 21 편명
     , S.EXCHANGE_RATE                                       AS EXCHANGE_RATE           -- 22 환율
     , S.ELECTRONIC_COMMERCE_YN                              AS ELECTRONIC_COMMERCE_YN  -- 23 전자상거래 여부
     , S.CARRYOUT_LOC                                        AS CARRYOUT_LOC            -- 24 반출장치장소
     -- 참고
     , S.COMP_CD
     , S.STOR_CD
     , S.SALE_DT
     , S.POS_NO
     , S.RCPT_NO
     , S.PRIORITY
     , S.BILL_PROC_CLS_CD
     , S.GOOS_LOC_CLS_CD
     , S.NATI_CD
     , S.NET_SELL_DOLR_AMT
  FROM SRC S;

-- 건수 확인 후 COMMIT (채번은 이미 나간 상태)


/* ==========================================================================
   3) Detail 적재 — TMP_SALES_H 의 교환권으로 품목을 붙여서 같은 신고번호 사용
   ========================================================================== */
INSERT INTO TMP_SALES_D
WITH
LINES AS (
    SELECT 'G'                  AS KIND                   -- 상품
         , H.DECLARATION_NO
         , H.WH_CODE
         , H.EXCHANGE_NO
         , C.SEQ
         , C.GOOS_CD
         , C.AGIG_CD
         , C.GOOS_QTY           AS QTY
         , C.NET_SELL_DOLR_AMT
         , C.NET_SELL_WON_AMT
         , C.SALE_DOLR_UCST
         , C.SALE_WON_UCST
         , C.DC_EVT_CD_1
      FROM TMP_SALES_H H
      JOIN SA0103D C
        ON C.COMP_CD = H.REF_COMP_CD
       AND C.STOR_CD = H.REF_STOR_CD
       AND C.SALE_DT = H.REF_SALE_DT
       AND C.POS_NO  = H.REF_POS_NO
       AND C.RCPT_NO = H.REF_RCPT_NO
     WHERE NVL(C.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W'                  AS KIND                   -- GWP
         , H.DECLARATION_NO
         , H.WH_CODE
         , H.EXCHANGE_NO
         , G.SEQ
         , G.GOOS_CD
         , NULL
         , G.PMNT_QTY
         , 0
         , 0
         , 0
         , 0
         , NULL
      FROM TMP_SALES_H H
      JOIN SA0109D G
        ON G.COMP_CD = H.REF_COMP_CD
       AND G.STOR_CD = H.REF_STOR_CD
       AND G.SALE_DT = H.REF_SALE_DT
       AND G.POS_NO  = H.REF_POS_NO
       AND G.RCPT_NO = H.REF_RCPT_NO
),
TYPED AS (                                                -- 물품구분 (재고 STEP 과 같은 규칙)
    SELECT L.*
         , CASE WHEN L.KIND = 'W'                  THEN 'D'
                WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1' THEN 'W'
                WHEN M.GOOS_TYPE_CD = '1'          THEN 'T'
                ELSE 'D' END                                     AS ITEM_TYPE
      FROM LINES L
      LEFT JOIN MA0040C M
        ON L.KIND      = 'G'
       AND M.COMP_CD   = '01'
       AND M.GOOS_CD   = L.GOOS_CD
)
SELECT L.DECLARATION_NO                                                          AS DECLARATION_NO        --  1 신고번호 (Header 와 동일)
     , L.WH_CODE                                                                 AS WH_CODE               --  2 신고점
     , 'DL8'                                                                     AS DOC_TYPE              --  3 문서구분
     , ROW_NUMBER() OVER (PARTITION BY L.DECLARATION_NO ORDER BY L.KIND, L.SEQ)  AS DOC_SEQ               --  4 품목일련번호
     , NULL                                                                      AS RAMEND_TYPE           --  5 란정정구분
     , L.ITEM_TYPE                                                               AS ITEM_TYPE             --  6 물품구분
     , CASE L.KIND WHEN 'W' THEN WP.HS_CD ELSE M.HS_CD END                       AS HS_CODE               --  7 HS코드
     , NVL(R.CSTM_GOOS_CD, L.GOOS_CD)                                            AS ITEM_CODE             --  8 상품코드 (세관신고 상품코드)
     , CASE L.KIND WHEN 'W' THEN WP.CSTM_GOOS_NM
                   ELSE BR.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM END    AS ITEM_NAME             --  9 품명
     , CASE L.KIND WHEN 'W' THEN WP.STDZ_CONT ELSE M.STDZ_CONT END               AS ITEM_NORM             -- 10 규격
     , L.QTY                                                                     AS ITEM_QTY              -- 11 수량
     , CASE WHEN L.KIND = 'W' OR NVL(L.QTY, 0) = 0 THEN 0
            ELSE ROUND(L.NET_SELL_DOLR_AMT / L.QTY, 2) END                       AS ITEM_COST             -- 12 실단가(미화)
     , CASE L.KIND WHEN 'W' THEN 0 ELSE ROUND(L.NET_SELL_DOLR_AMT, 2) END        AS ITEM_AMOUNT           -- 13 금액(미화)
     , CASE WHEN L.KIND = 'G' AND M.GOOS_TYPE_CD = '1' THEN 'B' END              AS MAKE_TYPE             -- 14 제조구분 B 외국산 / C 대기업 / D 중소중견 (국산 확인)
     , CASE WHEN L.DC_EVT_CD_1 IS NOT NULL THEN '2' ELSE '1' END                 AS EVENT_TYPE_CODE       -- 15 일반/행사
     , CASE WHEN L.KIND = 'W' OR NVL(L.QTY, 0) = 0 THEN 0
            ELSE ROUND(L.NET_SELL_WON_AMT / L.QTY) END                           AS ITEM_COST_KRW         -- 16 실단가(원화)
     , CASE L.KIND WHEN 'W' THEN 0 ELSE L.SALE_DOLR_UCST END                     AS NORM_UNIT_PRICE_USD   -- 17 정상단가(미화)
     , CASE L.KIND WHEN 'W' THEN 0 ELSE L.SALE_WON_UCST END                      AS NORM_UNIT_PRICE_KRW   -- 18 정상단가(원화)
     , CASE L.KIND WHEN 'W' THEN WP.GOOS_CAPA ELSE V.GOOS_CAPA END               AS CAPACITY              -- 19 용량
     , CASE L.KIND WHEN 'W' THEN WM.BRAN_CD ELSE M.BRAN_CD END                   AS BRAND_CODE            -- 20 브랜드코드
     , CASE L.KIND WHEN 'W' THEN WB.BRAN_NM ELSE BR.BRAN_NM END                  AS BRAND_NAME            -- 21 브랜드명
     , CASE L.KIND WHEN 'W' THEN WP.SIZE_UNIT_CD ELSE M.UNIT END                 AS UNIT_CODE             -- 22 용량단위
     , CASE L.KIND WHEN 'W' THEN WI.MNGE_LVL_CD END                              AS GWP_PRODUCT_GRADE     -- 23 GWP물품등급
     , NULL                                                                      AS GWP_LINK_ITEM_CODE    -- 24 GWP연계상품코드
     , 'EA'                                                                      AS QTY_UNIT_CODE         -- 25 수량단위
     -- 참고
     , L.EXCHANGE_NO
     , DECODE(L.KIND, 'G', '상품', 'GWP')
     , L.GOOS_CD
  FROM TYPED L
  LEFT JOIN MA0040C M
    ON L.KIND    = 'G'
   AND M.COMP_CD = '01'
   AND M.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA0030C BR
    ON BR.COMP_CD = M.COMP_CD
   AND BR.BRAN_CD = M.BRAN_CD
  LEFT JOIN MA3118I V
    ON L.KIND    = 'G'
   AND V.COMP_CD = '01'
   AND V.GOOS_CD = L.GOOS_CD
  LEFT JOIN WM0310C WM
    ON L.KIND     = 'W'
   AND WM.COMP_CD = '01'
   AND WM.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA0030C WB
    ON WB.COMP_CD = WM.COMP_CD
   AND WB.BRAN_CD = WM.BRAN_CD
  LEFT JOIN WM0314C WP
    ON L.KIND     = 'W'
   AND WP.COMP_CD = '01'
   AND WP.GOOS_CD = L.GOOS_CD
  LEFT JOIN WM0310I WI
    ON L.KIND     = 'W'
   AND WI.COMP_CD = '01'
   AND WI.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA9301C R
    ON R.COMP_CD            = '01'
   AND R.USE_YN             = 'Y'
   AND R.GOOS_CD            = L.GOOS_CD
   AND R.CSTM_GOODS_TYPE_CD = L.ITEM_TYPE;


/* ==========================================================================
   4) 검증 — 모두 0건이면 정상
   ========================================================================== */
-- 4-1. Header 만 있고 Detail 없는 신고서 / Detail 만 있는 신고서
SELECT 'H_NO_D'         AS CHK
     , H.DECLARATION_NO
     , H.EXCHANGE_NO
  FROM TMP_SALES_H H
 WHERE NOT EXISTS (SELECT 1 FROM TMP_SALES_D D WHERE D.DECLARATION_NO = H.DECLARATION_NO AND D.WH_CODE = H.WH_CODE)
UNION ALL
SELECT DISTINCT 'D_NO_H'
     , D.DECLARATION_NO
     , D.REF_EXCHANGE_NO
  FROM TMP_SALES_D D
 WHERE NOT EXISTS (SELECT 1 FROM TMP_SALES_H H WHERE H.DECLARATION_NO = D.DECLARATION_NO AND H.WH_CODE = D.WH_CODE);

-- 4-2. 신고번호 비었거나 중복 / 교환권 중복
SELECT 'NO_NULL'        AS CHK, COUNT(*) AS CNT FROM TMP_SALES_H WHERE DECLARATION_NO IS NULL
UNION ALL
SELECT 'NO_DUP'         , COUNT(*) FROM (SELECT DECLARATION_NO FROM TMP_SALES_H GROUP BY DECLARATION_NO HAVING COUNT(*) > 1)
UNION ALL
SELECT 'BILL_DUP'       , COUNT(*) FROM (SELECT EXCHANGE_NO FROM TMP_SALES_H GROUP BY EXCHANGE_NO HAVING COUNT(*) > 1)
UNION ALL
SELECT 'D_KEY_DUP'      , COUNT(*) FROM (SELECT DECLARATION_NO, DOC_SEQ FROM TMP_SALES_D GROUP BY DECLARATION_NO, DOC_SEQ HAVING COUNT(*) > 1);

-- 4-3. 필수값 누락 (Detail)
SELECT SUM(CASE WHEN ITEM_TYPE   IS NULL THEN 1 ELSE 0 END) AS NO_ITEM_TYPE
     , SUM(CASE WHEN HS_CODE     IS NULL THEN 1 ELSE 0 END) AS NO_HS_CODE
     , SUM(CASE WHEN ITEM_CODE   IS NULL THEN 1 ELSE 0 END) AS NO_ITEM_CODE
     , SUM(CASE WHEN ITEM_NAME   IS NULL THEN 1 ELSE 0 END) AS NO_ITEM_NAME
     , SUM(CASE WHEN ITEM_NORM   IS NULL THEN 1 ELSE 0 END) AS NO_ITEM_NORM
     , SUM(CASE WHEN MAKE_TYPE   IS NULL THEN 1 ELSE 0 END) AS NO_MAKE_TYPE
     , SUM(CASE WHEN BRAND_CODE  IS NULL THEN 1 ELSE 0 END) AS NO_BRAND_CODE
     , SUM(CASE WHEN BRAND_NAME  IS NULL THEN 1 ELSE 0 END) AS NO_BRAND_NAME
     , COUNT(*)                                             AS TOTAL
  FROM TMP_SALES_D;

-- 4-4. 우선순위별 건수 (당일 출국 먼저 확인)
SELECT H.REF_PRIORITY
     , COUNT(DISTINCT H.DECLARATION_NO) AS DECL_CNT
     , COUNT(D.DOC_SEQ)                 AS ITEM_CNT
     , SUM(D.ITEM_QTY)                  AS QTY
     , SUM(D.ITEM_AMOUNT)               AS USD
  FROM TMP_SALES_H H
  LEFT JOIN TMP_SALES_D D
    ON D.DECLARATION_NO = H.DECLARATION_NO
   AND D.WH_CODE        = H.WH_CODE
 GROUP BY H.REF_PRIORITY
 ORDER BY 1;


/* ==========================================================================
   5) 본테이블 적재 — Header 먼저, Detail 나중 (우선순위 순)
   ========================================================================== */
INSERT INTO SR_Sales_H
(
      declaration_no, wh_code, doc_type, declaration_date, amend_type, declaration_type, status, c_datetime
    , sale_date, item_amend_type, delivery_method, domestic_type, buyer_name, nationality, exchange_no
    , personal_type, personal_value, birth_date, departure_arrive_type, departure_arrive_date, flight_no
    , exchange_rate, electronic_commerce_yn, carryout_loc
)
SELECT DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, AMEND_TYPE, DECLARATION_TYPE, STATUS, SYSDATE
     , SALE_DATE, ITEM_AMEND_TYPE, DELIVERY_METHOD, DOMESTIC_TYPE, BUYER_NAME, NATIONALITY, EXCHANGE_NO
     , PERSONAL_TYPE, PERSONAL_VALUE, BIRTH_DATE, DEPARTURE_ARRIVE_TYPE, DEPARTURE_ARRIVE_DATE, FLIGHT_NO
     , EXCHANGE_RATE, ELECTRONIC_COMMERCE_YN, CARRYOUT_LOC
  FROM TMP_SALES_H
 ORDER BY REF_PRIORITY, DECLARATION_NO;

INSERT INTO SR_Sales_D
(
      declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name
    , item_norm, item_qty, item_cost, item_amount, make_type, event_type_code, item_cost_krw
    , norm_unit_price_usd, norm_unit_price_krw, capacity, brand_code, brand_name, unit_code
    , gwp_product_grade, gwp_link_item_code, qty_unit_code
)
SELECT D.DECLARATION_NO, D.WH_CODE, D.DOC_TYPE, D.DOC_SEQ, D.RAMEND_TYPE, D.ITEM_TYPE, D.HS_CODE, D.ITEM_CODE, D.ITEM_NAME
     , D.ITEM_NORM, D.ITEM_QTY, D.ITEM_COST, D.ITEM_AMOUNT, D.MAKE_TYPE, D.EVENT_TYPE_CODE, D.ITEM_COST_KRW
     , D.NORM_UNIT_PRICE_USD, D.NORM_UNIT_PRICE_KRW, TO_NUMBER(D.CAPACITY), D.BRAND_CODE, D.BRAND_NAME, D.UNIT_CODE
     , D.GWP_PRODUCT_GRADE, D.GWP_LINK_ITEM_CODE, D.QTY_UNIT_CODE
  FROM TMP_SALES_D D
  JOIN TMP_SALES_H H
    ON H.DECLARATION_NO = D.DECLARATION_NO
   AND H.WH_CODE        = D.WH_CODE
 ORDER BY H.REF_PRIORITY, D.DECLARATION_NO, D.DOC_SEQ;

-- 건수 확인 후 COMMIT
