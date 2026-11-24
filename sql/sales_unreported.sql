/* =====================================================================
   판매미신고 — 판매(정정)신고서 SR_Sales_H / SR_Sales_D            기준일 2026-11-30
   ---------------------------------------------------------------------
   대상 : 본점(05) 판매분 중 판매취소 확정되지 않은 모든 교환권
            빌상태(BILL_PROC_CLS_CD, BO015)   00 매출 / 01 면장등록 / 02 면장확정
          × 상품위치(GOOS_LOC_CLS_CD, BO014) 01 점포(점창고) / 02 통물 / 11 점미래보세 / 12 통물미래보세
   우선순위 : 당일(신고일) 출국 1 → 이후 출국 2 → 출국일 지남·없음 3  (신고번호도 이 순서로 부여)
   단위 : 교환권(빌) 1건 = 판매신고서 1건 (Header 1행), 품목 = 상품(SA0103D) + GWP(SA0109D)
   신고번호 : 세관(3)+과(2)+보세구역(8)+년도(2)+구분코드 'C'(판매)+일련번호(8)   문서구분 DL8
   - 고객 쿼리 "1. 매출조회 기본" 기반 (판매취소 판정은 다른 날 취소 포함)
   - 못 찾은 항목은 NULL, 확인 필요한 값은 주석 "확인"
   - 고객정보(고객명·여권번호)는 암호화 컬럼 → 복호화 함수 필요 (자리 표시만 해 둠)
   - 빌상태·상품위치는 현재 상태 값 → 12/1 영업 시작 전 실행
   ===================================================================== */


/* [확인 1] 대상 빌 분포 — 빌상태 × 상품위치 × 출국 우선순위 (본점) */
SELECT A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
       CASE WHEN A.DPAT_DT = '20261201' THEN '1 당일출국'
            WHEN A.DPAT_DT > '20261201' THEN '2 이후출국'
            ELSE '3 출국일 지남/없음' END PRIORITY,
       COUNT(*) BILL_CNT, SUM(A.GOOS_QTY) QTY, SUM(A.NET_SELL_DOLR_AMT) USD
  FROM SA0100M A
 WHERE A.COMP_CD = '01'
   AND A.STOR_CD = '05'
   AND A.SALE_TYPE_CD = '1'
   AND A.SALE_DT <= '20261130'
   AND A.BILL_PROC_CLS_CD IN ('00', '01', '02')
   AND A.GOOS_LOC_CLS_CD  IN ('01', '02', '11', '12')
   AND NOT EXISTS (SELECT 1 FROM SA0100M E
                    WHERE E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD AND E.BILL_NO = A.BILL_NO
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD AND E.SALE_DT <= '20261130')
 GROUP BY A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
          CASE WHEN A.DPAT_DT = '20261201' THEN '1 당일출국'
               WHEN A.DPAT_DT > '20261201' THEN '2 이후출국'
               ELSE '3 출국일 지남/없음' END
 ORDER BY 3, 1, 2;

/* [확인 2] SA0109D(GWP 매출)의 GOOS_CD 가 GWP 자체 코드인지, 본품 코드인지
     - 신고 양식에 "GWP연계상품코드 = GWP 제공 시 본품의 상품코드" 항목이 있음
     - GOOS_CD 가 GWP 마스터(WM0310C)에 있으면 GWP 코드 / 상품마스터(MA0040C)에 있으면 본품 코드
     - SPTM_CD(판촉품코드) 도 같이 비교  ※ 결과에 따라 재고 STEP 3·4 의 GWP 코드도 확인 필요 */
SELECT CASE WHEN W.GOOS_CD IS NOT NULL THEN 'GWP마스터' WHEN M.GOOS_CD IS NOT NULL THEN '상품마스터' ELSE '없음' END GOOS_CD_IN,
       CASE WHEN W2.GOOS_CD IS NOT NULL THEN 'GWP마스터' ELSE '없음' END SPTM_CD_IN,
       COUNT(*) ROW_CNT
  FROM SA0109D G
  LEFT JOIN (SELECT DISTINCT GOOS_CD FROM WM0310C WHERE COMP_CD = '01') W  ON W.GOOS_CD  = G.GOOS_CD
  LEFT JOIN (SELECT DISTINCT GOOS_CD FROM WM0310C WHERE COMP_CD = '01') W2 ON W2.GOOS_CD = G.SPTM_CD
  LEFT JOIN MA0040C M ON M.COMP_CD = '01' AND M.GOOS_CD = G.GOOS_CD
 WHERE G.COMP_CD = '01' AND G.SALE_DT LIKE '202610%'
 GROUP BY CASE WHEN W.GOOS_CD IS NOT NULL THEN 'GWP마스터' WHEN M.GOOS_CD IS NOT NULL THEN '상품마스터' ELSE '없음' END,
          CASE WHEN W2.GOOS_CD IS NOT NULL THEN 'GWP마스터' ELSE '없음' END;



/* =====================================================================
   [Detail] SR_Sales_D 양식 순서
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 본점만 (신고구분 E 인도장 인도판매 / 인도방법 E 출국장인도장 — 확인)
    SELECT '05' STOR_CD, '본점' STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX,
           'E' DECL_TYPE, 'E' DELIV_METHOD FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장 (재고 STEP 2·3 과 같은 값, 961/965 배정은 가정)
    SELECT '961' CORN_CD, '04077090' SHED_CD FROM DUAL UNION ALL
    SELECT '965',         '04077137'         FROM DUAL
),

-- ① 대상 빌 : 본점 · 판매취소 아님 × 빌상태 00·01·02 × 상품위치 01·02·11·12
BILL AS (
    SELECT A.*, B.STOR_NM, B.BOND_GRN_CD, B.CSTM_CD, B.DEPT_CD, B.SEQ_PREFIX, B.DECL_TYPE, B.DELIV_METHOD
      FROM SA0100M A /* 영업_매출기본 */
      JOIN BOND B ON B.STOR_CD = A.STOR_CD
      CROSS JOIN PRM P
     WHERE A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND A.BILL_PROC_CLS_CD IN ('00', '01', '02')             -- 매출 / 면장등록 / 면장확정
       AND A.GOOS_LOC_CLS_CD  IN ('01', '02', '11', '12')       -- 점포(점창고) / 통물 / 점미래보세 / 통물미래보세
       -- 판매취소가 아닌것 (다른 날 취소 포함)
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- 우선순위 : 당일(신고일) 출국 1 / 이후 출국 2 / 출국일 지남·없음 3
BILL_PRI AS (
    SELECT B.*,
           CASE WHEN B.DPAT_DT = P.DECL_DT THEN 1
                WHEN B.DPAT_DT > P.DECL_DT THEN 2
                ELSE 3 END PRIORITY
      FROM BILL B CROSS JOIN PRM P
),
-- 신고번호 : 우선순위 → 출국일 → 매출일 순으로 일련번호
BILL_NO_SEQ AS (
    SELECT B.*,
           B.CSTM_CD || B.DEPT_CD || B.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'C'
             || B.SEQ_PREFIX || LPAD(ROW_NUMBER() OVER (PARTITION BY B.BOND_GRN_CD
                                                         ORDER BY B.PRIORITY, B.DPAT_DT, B.SALE_DT, B.BILL_NO), 7, '0') DECLARATION_NO
      FROM BILL_PRI B CROSS JOIN PRM P
),

-- ② 품목 : 상품 + GWP
LINES AS (
    SELECT 'G' KIND, B.DECLARATION_NO, B.BOND_GRN_CD, B.STOR_NM, B.BILL_NO, B.SALE_DT, B.PRIORITY,
           C.SEQ, C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY,
           C.NET_SELL_DOLR_AMT, C.NET_SELL_WON_AMT, C.SALE_DOLR_UCST, C.SALE_WON_UCST, C.DC_EVT_CD_1
      FROM BILL_NO_SEQ B, SA0103D C
     WHERE C.COMP_CD = B.COMP_CD AND C.STOR_CD = B.STOR_CD AND C.SALE_DT = B.SALE_DT
       AND C.POS_NO = B.POS_NO AND C.RCPT_NO = B.RCPT_NO
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W', B.DECLARATION_NO, B.BOND_GRN_CD, B.STOR_NM, B.BILL_NO, B.SALE_DT, B.PRIORITY,
           G.SEQ, G.GOOS_CD, NULL, G.PMNT_QTY,
           0, 0, 0, 0, NULL
      FROM BILL_NO_SEQ B, SA0109D G
     WHERE G.COMP_CD = B.COMP_CD AND G.STOR_CD = B.STOR_CD AND G.SALE_DT = B.SALE_DT
       AND G.POS_NO = B.POS_NO AND G.RCPT_NO = B.RCPT_NO
)

SELECT L.DECLARATION_NO                                            AS DECLARATION_NO,       --  1 신고번호
       L.BOND_GRN_CD                                               AS WH_CODE,              --  2 신고점
       'DL8'                                                       AS DOC_TYPE,             --  3 문서구분 판매신고
       ROW_NUMBER() OVER (PARTITION BY L.DECLARATION_NO
                          ORDER BY L.KIND, L.SEQ)                  AS DOC_SEQ,              --  4 품목일련번호
       NULL                                                        AS RAMEND_TYPE,          --  5 란정정구분
       CASE WHEN L.KIND = 'W'                  THEN 'D'                                    --  6 물품구분 (재고 STEP 과 같은 규칙)
            WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1' THEN 'W'
            WHEN M.GOOS_TYPE_CD = '1'          THEN 'T'
            WHEN M.GOOS_CD IS NULL             THEN '?'
            ELSE 'D' END                                           AS ITEM_TYPE,
       CASE L.KIND WHEN 'W' THEN WP.HS_CD END                      AS HS_CODE,              --  7 HS코드 (상품: 공백)
       NVL(R.CSTM_GOOS_CD, L.GOOS_CD)                              AS ITEM_CODE,            --  8 상품코드 (세관신고 상품코드)
       CASE L.KIND WHEN 'W' THEN WP.CSTM_GOOS_NM
                   ELSE BR.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM END AS ITEM_NAME,  --  9 품명
       NULL                                                        AS ITEM_NORM,            -- 10 규격
       L.QTY                                                       AS ITEM_QTY,             -- 11 수량
       CASE WHEN L.KIND = 'W' OR NVL(L.QTY, 0) = 0 THEN 0
            ELSE ROUND(L.NET_SELL_DOLR_AMT / L.QTY, 2) END         AS ITEM_COST,            -- 12 실단가(미화) = 순매출 / 수량
       CASE L.KIND WHEN 'W' THEN 0 ELSE ROUND(L.NET_SELL_DOLR_AMT, 2) END AS ITEM_AMOUNT,   -- 13 금액(미화)
       CASE WHEN L.KIND = 'G' AND M.GOOS_TYPE_CD = '1' THEN 'B' END AS MAKE_TYPE,           -- 14 제조구분 B 외국산 / C 대기업 / D 중소중견 (국산 C·D 구분 확인)
       CASE WHEN L.DC_EVT_CD_1 IS NOT NULL THEN '2' ELSE '1' END   AS EVENT_TYPE_CODE,      -- 15 일반/행사 (행사코드 있으면 행사, 확인)
       CASE WHEN L.KIND = 'W' OR NVL(L.QTY, 0) = 0 THEN 0
            ELSE ROUND(L.NET_SELL_WON_AMT / L.QTY) END             AS ITEM_COST_KRW,        -- 16 실단가(원화)
       CASE L.KIND WHEN 'W' THEN 0 ELSE L.SALE_DOLR_UCST END       AS NORM_UNIT_PRICE_USD,  -- 17 정상단가(미화)
       CASE L.KIND WHEN 'W' THEN 0 ELSE L.SALE_WON_UCST END        AS NORM_UNIT_PRICE_KRW,  -- 18 정상단가(원화)
       CASE L.KIND WHEN 'W' THEN WP.GOOS_CAPA ELSE V.GOOS_CAPA END AS CAPACITY,             -- 19 용량
       CASE L.KIND WHEN 'W' THEN WM.BRAN_CD ELSE M.BRAN_CD END     AS BRAND_CODE,           -- 20 브랜드코드
       CASE L.KIND WHEN 'W' THEN WB.BRAN_NM ELSE BR.BRAN_NM END    AS BRAND_NAME,           -- 21 브랜드명
       CASE L.KIND WHEN 'W' THEN WP.SIZE_UNIT_CD END               AS UNIT_CODE,            -- 22 용량단위
       CASE L.KIND WHEN 'W' THEN WI.MNGE_LVL_CD END                AS GWP_PRODUCT_GRADE,    -- 23 GWP물품등급
       NULL                                                        AS GWP_LINK_ITEM_CODE,   -- 24 GWP연계상품코드 (본품, [확인 2] 결과 보고)
       NULL                                                        AS QTY_UNIT_CODE,        -- 25 수량단위
       ----------------------------------------------- 참고 (적재 제외)
       L.PRIORITY                                                  AS REF_PRIORITY,
       L.BILL_NO                                                   AS REF_BILL_NO,
       DECODE(L.KIND, 'G', '상품', 'GWP')                           AS REF_GOOS_GWP,
       L.GOOS_CD                                                   AS REF_GOOS_CD
  FROM LINES L
  LEFT JOIN MA0040C M  ON L.KIND = 'G' AND M.COMP_CD = '01' AND M.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA0030C BR ON BR.COMP_CD = M.COMP_CD AND BR.BRAN_CD = M.BRAN_CD
  LEFT JOIN MA3118I V  ON L.KIND = 'G' AND V.COMP_CD = '01' AND V.GOOS_CD = L.GOOS_CD
  LEFT JOIN WM0310C WM ON L.KIND = 'W' AND WM.COMP_CD = '01' AND WM.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA0030C WB ON WB.COMP_CD = WM.COMP_CD AND WB.BRAN_CD = WM.BRAN_CD
  LEFT JOIN WM0314C WP ON L.KIND = 'W' AND WP.COMP_CD = '01' AND WP.GOOS_CD = L.GOOS_CD
  LEFT JOIN WM0310I WI ON L.KIND = 'W' AND WI.COMP_CD = '01' AND WI.GOOS_CD = L.GOOS_CD
  LEFT JOIN MA9301C R  ON R.COMP_CD = '01' AND R.USE_YN = 'Y' AND R.GOOS_CD = L.GOOS_CD
                      AND R.CSTM_GOODS_TYPE_CD = CASE WHEN L.KIND = 'W'                  THEN 'D'
                                                      WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1' THEN 'W'
                                                      WHEN M.GOOS_TYPE_CD = '1'          THEN 'T'
                                                      ELSE 'D' END
 ORDER BY 1, 4;



/* =====================================================================
   [Header] SR_Sales_H 양식 순서   — 교환권(빌)마다 1행
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 본점만 (신고구분 E 인도장 인도판매 / 인도방법 E 출국장인도장 — 확인)
    SELECT '05' STOR_CD, '본점' STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX,
           'E' DECL_TYPE, 'E' DELIV_METHOD FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장 (재고 STEP 2·3 과 같은 값, 961/965 배정은 가정)
    SELECT '961' CORN_CD, '04077090' SHED_CD FROM DUAL UNION ALL
    SELECT '965',         '04077137'         FROM DUAL
),

-- ① 대상 빌 : 본점 · 판매취소 아님 × 빌상태 00·01·02 × 상품위치 01·02·11·12
BILL AS (
    SELECT A.*, B.STOR_NM, B.BOND_GRN_CD, B.CSTM_CD, B.DEPT_CD, B.SEQ_PREFIX, B.DECL_TYPE, B.DELIV_METHOD
      FROM SA0100M A /* 영업_매출기본 */
      JOIN BOND B ON B.STOR_CD = A.STOR_CD
      CROSS JOIN PRM P
     WHERE A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND A.BILL_PROC_CLS_CD IN ('00', '01', '02')             -- 매출 / 면장등록 / 면장확정
       AND A.GOOS_LOC_CLS_CD  IN ('01', '02', '11', '12')       -- 점포(점창고) / 통물 / 점미래보세 / 통물미래보세
       -- 판매취소가 아닌것 (다른 날 취소 포함)
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- 우선순위 : 당일(신고일) 출국 1 / 이후 출국 2 / 출국일 지남·없음 3
BILL_PRI AS (
    SELECT B.*,
           CASE WHEN B.DPAT_DT = P.DECL_DT THEN 1
                WHEN B.DPAT_DT > P.DECL_DT THEN 2
                ELSE 3 END PRIORITY
      FROM BILL B CROSS JOIN PRM P
),
-- 신고번호 : 우선순위 → 출국일 → 매출일 순으로 일련번호
BILL_NO_SEQ AS (
    SELECT B.*,
           B.CSTM_CD || B.DEPT_CD || B.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'C'
             || B.SEQ_PREFIX || LPAD(ROW_NUMBER() OVER (PARTITION BY B.BOND_GRN_CD
                                                         ORDER BY B.PRIORITY, B.DPAT_DT, B.SALE_DT, B.BILL_NO), 7, '0') DECLARATION_NO
      FROM BILL_PRI B CROSS JOIN PRM P
),

-- ② 품목 : 상품 + GWP
LINES AS (
    SELECT 'G' KIND, B.DECLARATION_NO, B.BOND_GRN_CD, B.STOR_NM, B.BILL_NO, B.SALE_DT, B.PRIORITY,
           C.SEQ, C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY,
           C.NET_SELL_DOLR_AMT, C.NET_SELL_WON_AMT, C.SALE_DOLR_UCST, C.SALE_WON_UCST, C.DC_EVT_CD_1
      FROM BILL_NO_SEQ B, SA0103D C
     WHERE C.COMP_CD = B.COMP_CD AND C.STOR_CD = B.STOR_CD AND C.SALE_DT = B.SALE_DT
       AND C.POS_NO = B.POS_NO AND C.RCPT_NO = B.RCPT_NO
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W', B.DECLARATION_NO, B.BOND_GRN_CD, B.STOR_NM, B.BILL_NO, B.SALE_DT, B.PRIORITY,
           G.SEQ, G.GOOS_CD, NULL, G.PMNT_QTY,
           0, 0, 0, 0, NULL
      FROM BILL_NO_SEQ B, SA0109D G
     WHERE G.COMP_CD = B.COMP_CD AND G.STOR_CD = B.STOR_CD AND G.SALE_DT = B.SALE_DT
       AND G.POS_NO = B.POS_NO AND G.RCPT_NO = B.RCPT_NO
)

SELECT B.DECLARATION_NO                                            AS DECLARATION_NO,         --  1 신고번호
       B.BOND_GRN_CD                                               AS WH_CODE,                --  2 보세판매장부호
       'DL8'                                                       AS DOC_TYPE,               --  3 문서구분 판매신고
       P.DECL_DT                                                   AS DECLARATION_DATE,       --  4 신고일자
       NULL                                                        AS AMEND_TYPE,             --  5 정정구분
       B.DECL_TYPE                                                 AS DECLARATION_TYPE,       --  6 신고구분 (점별, 확인)
       'A1'                                                        AS STATUS,                 --  7 상태
       SYSDATE                                                     AS C_DATETIME,             --  8 생성일시
       B.SALE_DT || NVL(RPAD(B.SYSM_TM, 6, '0'), '000000')         AS SALE_DATE,              --  9 판매일시 YYYYMMDDHH24MISS
       NULL                                                        AS ITEM_AMEND_TYPE,        -- 10 품목정정신고구분
       B.DELIV_METHOD                                              AS DELIVERY_METHOD,        -- 11 인도방법 (점별, 확인)
       CASE WHEN B.NATI_CD = 'KOR' THEN '1' ELSE '2' END           AS DOMESTIC_TYPE,          -- 12 내국인/외국인
       B.CUST_NM                                                   AS BUYER_NAME,             -- 13 구매자영문성명 ※ 암호화 → 복호화 함수 필요
       N.COMM_PROP_CONT_1                                          AS NATIONALITY,            -- 14 국적코드 2자리 (MA024 속성 중 2자리 코드 확인)
       B.BILL_NO                                                   AS EXCHANGE_NO,            -- 15 교환권번호
       CASE WHEN B.PSPT_NO IS NOT NULL THEN '1' END                AS PERSONAL_TYPE,          -- 16 개인정보식별구분 1 여권번호
       B.PSPT_NO                                                   AS PERSONAL_VALUE,         -- 17 개인정보식별값 ※ 암호화 → 복호화 함수 필요
       B.BIRT_DT                                                   AS BIRTH_DATE,             -- 18 생년월일
       'D'                                                         AS DEPARTURE_ARRIVE_TYPE,  -- 19 입/출국 D 출국
       B.DPAT_DT                                                   AS DEPARTURE_ARRIVE_DATE,  -- 20 출국예정일자
       B.OPEN_NM                                                   AS FLIGHT_NO,              -- 21 편명
       CASE WHEN NVL(B.TOT_SALE_DOLR_AMT, 0) = 0 THEN 0
            ELSE ROUND(B.TOT_SALE_WON_AMT / B.TOT_SALE_DOLR_AMT, 2) END AS EXCHANGE_RATE,     -- 22 환율 (원화/달러로 계산, 환율 테이블 있으면 교체)
       CASE WHEN B.SALE_CRS_CLS_CD = 'OFF' THEN 'N' ELSE 'Y' END   AS ELECTRONIC_COMMERCE_YN, -- 23 전자상거래 여부
       CASE WHEN B.GOOS_LOC_CLS_CD IN ('02', '12') THEN T.SHED_CD END AS CARRYOUT_LOC,        -- 24 반출장치장소 (통물이면 통물 장치장)
       ----------------------------------------------- 참고 (적재 제외)
       B.PRIORITY                                                  AS REF_PRIORITY,           -- 1 당일출국 / 2 이후 / 3 지남·없음
       B.BILL_PROC_CLS_CD                                          AS REF_BILL_STAT,
       B.GOOS_LOC_CLS_CD                                           AS REF_GOOS_LOC,
       B.NATI_CD                                                   AS REF_NATI_CD,
       B.NET_SELL_DOLR_AMT                                         AS REF_NET_USD
  FROM BILL_NO_SEQ B
  CROSS JOIN PRM P
  LEFT JOIN TONG T     ON T.CORN_CD = B.STOC_CORN_CD
  LEFT JOIN MA0151D N  ON N.COMP_CD = '01' AND N.WRK_MDUL_CD = 'MA' AND N.COMM_CTG_CD = 'MA024'
                      AND N.COMM_CTG_DTL_CD = B.NATI_CD
 ORDER BY 1;
