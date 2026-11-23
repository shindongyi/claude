/* =====================================================================
   STEP 2. 상품 기초 — 통합물류 : 계산재고                         기준일 2026-11-30
   ---------------------------------------------------------------------
   계산재고 = 수불 기말재고 (11월 월수불 WM0053L, 통물 코너)
            + 교환권 판매수량   : 매출/통물창고(00,02) · 매출/통물미래보세(00,12) · 면장등록/통물미래보세(01,12)
            − H신고 재반입면장 교환권 중 판매취소 아닌 것의 판매수량
   ※ 미인도(06/76/86)는 고객 정리 3번 "미인도 기초"로 따로 → 여기서는 안 뺌 (STEP 4 에서 같이 정리)

   - 통물 재고는 점(05/15/17) 밑의 통물 코너로 관리됨 (조회상 961, 965 등이 모든 점에 있음)
     → 신고서: 신고지점 = 그 점의 보세구역, 반입장치장소 = 통물 장치장 (04077090 / 04077137)
   - 환급코드(T/D/W): 상품 마이그 규칙과 동일
       에이징코드 6번째 자리 = 1 → W,  아니면 상품구분(GOOS_TYPE_CD) = 1 → T,  그 외 D
       수불·매출 모두 행에 AGIG_CD 가 있어서 같은 규칙 적용
     세관신고 상품코드 = MA9301C (상품코드 + 같은 환급구분), 없으면 W 규칙 (수입 5 / 국산 6) || SUBSTR(상품코드, 2)
   - 교환권 판정에 쓰는 빌상태·상품위치(SA0100M)는 "지금 상태" 값이라 과거로 못 돌림
     → 12/1 영업 시작 전에 돌려야 11/30 마감 상태와 같음
   - 테이블 생성 없음. [확인] → [Detail] → [Header] → [점검]
   ===================================================================== */


/* ---------------------------------------------------------------------
   [확인 1] 통물 코너 찾기 — 월수불에 점·코너별로 무엇이 있는지 (코너명 포함)
     ※ 11월 마감 전이면 YMON 을 '202610' 으로
     → 여기서 통물 코너를 골라 아래 TONG 블록에 넣고, 각 코너가 어느 장치장(04077090 / 04077137)인지 확인
   --------------------------------------------------------------------- */
SELECT S.STOR_CD, S.CORN_CD,
       (SELECT MAX(N.CORN_NM) FROM MA0100C N WHERE N.COMP_CD = S.COMP_CD AND N.CORN_CD = S.CORN_CD) CORN_NM,  -- 코너명 (컬럼명 확인)
       COUNT(DISTINCT S.GOOS_CD) GOOS_CNT, SUM(S.QTY) QTY
  FROM WM0053L S
 WHERE S.COMP_CD = '01'
   AND S.YMON = '202610'
   AND S.STOR_CD IN ('05', '15', '17')
 GROUP BY S.COMP_CD, S.STOR_CD, S.CORN_CD
 ORDER BY 1, 2;

/* ---------------------------------------------------------------------
   [확인 2] 지금 남아 있는 교환권이 어느 재고점·재고코너에 있는지 (상태 조합별)
   --------------------------------------------------------------------- */
SELECT NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD, NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,
       A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
       COUNT(DISTINCT A.BILL_NO) BILL_CNT, SUM(C.GOOS_QTY) QTY
  FROM SA0100M A, SA0103D C
 WHERE A.COMP_CD = C.COMP_CD AND A.STOR_CD = C.STOR_CD AND A.SALE_DT = C.SALE_DT
   AND A.POS_NO = C.POS_NO AND A.RCPT_NO = C.RCPT_NO
   AND A.COMP_CD = '01'
   AND A.SALE_TYPE_CD = '1'
   AND A.SALE_DT <= '20261130'
   AND (A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
 GROUP BY NVL(C.STOC_STOR_CD, A.STOC_STOR_CD), NVL(C.STOC_CORN_CD, A.STOC_CORN_CD), A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD
 ORDER BY 1, 2, 3, 4;

/* ---------------------------------------------------------------------
   [확인 3] 수불의 환급구분(REFU_CLS_CD, GO407) 과 에이징 규칙(T/D/W)이 맞는지
   --------------------------------------------------------------------- */
SELECT S.REFU_CLS_CD,
       CASE WHEN SUBSTR(S.AGIG_CD, 6, 1) = '1' THEN 'W'
            WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
            ELSE 'D' END                                   AS RULE_TYPE,
       COUNT(*) ROW_CNT, SUM(S.QTY) QTY
  FROM WM0053L S
  LEFT JOIN MA0040C G ON G.COMP_CD = S.COMP_CD AND G.GOOS_CD = S.GOOS_CD
 WHERE S.COMP_CD = '01' AND S.YMON = '202610' AND S.STOR_CD IN ('05', '15', '17')
 GROUP BY S.REFU_CLS_CD,
          CASE WHEN SUBSTR(S.AGIG_CD, 6, 1) = '1' THEN 'W' WHEN G.GOOS_TYPE_CD = '1' THEN 'T' ELSE 'D' END
 ORDER BY 1, 2;



/* =====================================================================
   [Detail] SR_ItemCarryIn_D 양식 순서   — 못 찾은 항목은 NULL
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장  ※ [확인 1] 보고 채움 (장치장 모르면 '????????')
    SELECT '961' CORN_CD, '????????' SHED_CD FROM DUAL UNION ALL     -- 예) 04077090 제2 통합물류센터 ?
    SELECT '965',         '????????'         FROM DUAL               -- 예) 04077137 은산 통합물류창고 ?
),

-- 판매취소 아닌 상품 매출 라인  ← 고객 쿼리 "1. 매출조회 기본" (수정분 동일)
SALE AS (
    SELECT A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD,        -- 재고가 빠지는 점
           NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,        -- 재고가 빠지는 코너
           C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY
      FROM SA0100M A, SA0103D C, PRM P
     WHERE A.COMP_CD = C.COMP_CD
       AND A.STOR_CD = C.STOR_CD
       AND A.SALE_DT = C.SALE_DT
       AND A.POS_NO  = C.POS_NO
       AND A.RCPT_NO = C.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                       -- 판매취소가 아닌것 (다른 날 취소 포함)
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- H신고 재반입면장 교환권 빌  ← 고객 쿼리 "2." (147행 오타 대신 UNION 으로 중복 제거)
H_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO                         /* WM038 면장기준 IFWM11M */
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                                  /* 확정통보 */
       AND BM.COMP_CD = MD.COMP_CD
       AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
       AND MD.WRK_MDUL_CD = 'WM'
       AND MD.COMM_CTG_CD = 'WM038'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'                                  -- H신고
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND IM.EDI_RPT_DT <= P.BASE_DT
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO                         /* WM038에 없지만 대상 */
      FROM MK5010D MK, IFWM12M IM, PRM P
     WHERE MK.COMP_CD = IM.COMP_CD
       AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_CLS_CD = '5KP'
       AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')                           /* B:반품(인도후), R:미인도물품재반입 */
       AND IM.EDI_DOC_STAT_CD = 'F1'                                  /* 결과통보 */
       AND IM.EDI_RPT_DT <= P.BASE_DT
),

-- ① 구성요소 (점·코너·상품·에이징 단위, 부호 포함)
COMP AS (
    -- 수불 기말재고 (통물 코너만)
    SELECT 'SUBUL' SRC, S.STOR_CD, S.CORN_CD, S.GOOS_CD, S.AGIG_CD, S.QTY
      FROM WM0053L S, PRM P
     WHERE S.COMP_CD = P.COMP_CD
       AND S.YMON = P.YMON
       AND S.STOR_CD IN (SELECT STOR_CD FROM BOND)
       AND S.CORN_CD IN (SELECT CORN_CD FROM TONG)
    UNION ALL
    -- 교환권 (+) : 매출/통물창고, 매출/통물미래보세, 면장등록/통물미래보세
    SELECT 'EXCH', X.STOC_STOR_CD, X.STOC_CORN_CD, X.GOOS_CD, X.AGIG_CD, X.QTY
      FROM SALE X
     WHERE (X.BILL_PROC_CLS_CD, X.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
       AND X.STOC_STOR_CD IN (SELECT STOR_CD FROM BOND)
    UNION ALL
    -- H신고 재반입 교환권 (−)
    SELECT 'HREENT', X.STOC_STOR_CD, X.STOC_CORN_CD, X.GOOS_CD, X.AGIG_CD, -X.QTY
      FROM SALE X
     WHERE (X.COMP_CD, X.STOR_CD, X.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
       AND X.STOC_STOR_CD IN (SELECT STOR_CD FROM BOND)
),

-- ② 환급코드 먼저 반영 (행 단위) + 보세구역·장치장 붙이기
TAGGED AS (
    SELECT B.BOND_GRN_CD,
           NVL(T.SHED_CD, '미매핑:' || X.CORN_CD)                  SHED_CD,     -- 통물 코너가 아니면 드러나게
           X.SRC, X.GOOS_CD, X.QTY,
           CASE WHEN SUBSTR(X.AGIG_CD, 6, 1) = '1' THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                ELSE 'D' END                                       CSTM_GOODS_TYPE_CD,
           G.GOOS_CD                                               MST_GOOS_CD,
           G.GOOS_TYPE_CD
      FROM COMP X
      JOIN BOND B          ON B.STOR_CD = X.STOR_CD
      LEFT JOIN TONG T     ON T.CORN_CD = X.CORN_CD
      LEFT JOIN MA0040C G  ON G.COMP_CD = '01' AND G.GOOS_CD = X.GOOS_CD
),
CODED AS (
    SELECT T.*,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                ELSE 'NO_TYPE' END                                 MATCH_BY
      FROM TAGGED T
      LEFT JOIN MA9301C R ON R.COMP_CD = '01' AND R.USE_YN = 'Y'
                         AND R.GOOS_CD = T.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드  (구성요소별 수량도 같이)
AGG AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY,
           SUM(C.QTY)                                              QTY,
           SUM(CASE WHEN C.SRC = 'SUBUL'  THEN C.QTY ELSE 0 END)   Q_SUBUL,
           SUM(CASE WHEN C.SRC = 'EXCH'   THEN C.QTY ELSE 0 END)   Q_EXCH,
           SUM(CASE WHEN C.SRC = 'HREENT' THEN C.QTY ELSE 0 END)   Q_HREENT
      FROM CODED C
     GROUP BY C.BOND_GRN_CD, C.SHED_CD, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY
    HAVING SUM(C.QTY) > 0                                           -- 0 이하는 신고 제외 → [점검 1]
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.BOND_GRN_CD, A.SHED_CD
                              ORDER BY A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '2'(통물 상품) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '2' || LPAD(DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      JOIN BOND D ON D.BOND_GRN_CD = N.BOND_GRN_CD
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,     --  1 신고번호
       X.BOND_GRN_CD                                      AS WH_CODE,            --  2 신고지점
       'DLG'                                              AS DOC_TYPE,           --  3 문서구분
       X.DOC_SEQ                                          AS DOC_SEQ,            --  4 품목일련번호
       NULL                                               AS RAMEND_TYPE,        --  5 란정정구분
       X.CSTM_GOODS_TYPE_CD                               AS ITEM_TYPE,          --  6 물품구분 T/D/W
       NULL                                               AS HS_CODE,            --  7 HS코드 (수불엔 없음 → 상품마스터 등에서)
       X.NEW_CSTM_GOOS_CD                                 AS ITEM_CODE,          --  8 세관신고 상품코드
       B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM   AS ITEM_NAME,          --  9 품명
       NULL                                               AS ITEM_NORM,          -- 10 규격
       X.QTY                                              AS ITEM_QTY,           -- 11 수량 (계산재고)
       NULL                                               AS ITEM_COST,          -- 12 단가(미화)
       NULL                                               AS ITEM_AMOUNT,        -- 13 금액
       V.GOOS_CAPA                                        AS CAPACITY,           -- 14 용량 (MA3118I)
       M.BRAN_CD                                          AS BRAND_CODE,         -- 15 브랜드코드
       B.BRAN_NM                                          AS BRAND_NAME,         -- 16 브랜드명
       NULL                                               AS UNIT_CODE,          -- 17 용량단위
       NULL                                               AS GWP_PRODUCT_GRADE,  -- 18 GWP물품등급
       NULL                                               AS REGISTER_NO,        -- 19 참조번호
       NULL                                               AS ITEM_COST_KRW,      -- 20 단가(원화)
       NULL                                               AS QTY_UNIT_CODE,      -- 21 수량단위
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       X.SHED_CD                                          AS REF_SHED_CD,
       X.GOOS_CD                                          AS REF_GOOS_CD,
       X.Q_SUBUL                                          AS REF_Q_SUBUL,        -- 수불 기말
       X.Q_EXCH                                           AS REF_Q_EXCH,         -- 교환권 (+)
       X.Q_HREENT                                         AS REF_Q_HREENT,       -- H재반입 (−, 음수로 표시)
       X.MATCH_BY                                         AS REF_MATCH_BY
  FROM DECL X
  LEFT JOIN MA0040C M ON M.COMP_CD = '01' AND M.GOOS_CD = X.GOOS_CD
  LEFT JOIN MA0030C B ON B.COMP_CD = M.COMP_CD AND B.BRAN_CD = M.BRAN_CD
  LEFT JOIN MA3118I V ON V.COMP_CD = '01' AND V.GOOS_CD = X.GOOS_CD
 ORDER BY X.DECLARATION_NO, X.DOC_SEQ;



/* =====================================================================
   [Header] SR_ItemCarryIn_H 양식 순서   — 신고서마다 1행 (Detail 과 같은 WITH)
   ===================================================================== */
WITH
PRM AS (SELECT '01' COMP_CD, '20261130' BASE_DT, '202611' YMON, '20261201' DECL_DT FROM DUAL),
BOND AS (                                    -- 점 ↔ 보세구역 + 신고번호 재료 (STEP 1 과 동일)
    SELECT '05' STOR_CD, '본점'   STOR_NM, '01022006' BOND_GRN_CD, '010' CSTM_CD, '22' DEPT_CD, '?' SEQ_PREFIX FROM DUAL UNION ALL
    SELECT '15',         'T1-DF4',         '04021040',             '040',          '21',         '?'            FROM DUAL UNION ALL
    SELECT '17',         'T2-DF4',         '04021041',             '040',          '21',         '?'            FROM DUAL
),
TONG AS (                                    -- 통물 코너 → 통물 장치장  ※ [확인 1] 보고 채움 (장치장 모르면 '????????')
    SELECT '961' CORN_CD, '????????' SHED_CD FROM DUAL UNION ALL     -- 예) 04077090 제2 통합물류센터 ?
    SELECT '965',         '????????'         FROM DUAL               -- 예) 04077137 은산 통합물류창고 ?
),

-- 판매취소 아닌 상품 매출 라인  ← 고객 쿼리 "1. 매출조회 기본" (수정분 동일)
SALE AS (
    SELECT A.COMP_CD, A.STOR_CD, A.BILL_NO, A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD,
           NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) STOC_STOR_CD,        -- 재고가 빠지는 점
           NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) STOC_CORN_CD,        -- 재고가 빠지는 코너
           C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY QTY
      FROM SA0100M A, SA0103D C, PRM P
     WHERE A.COMP_CD = C.COMP_CD
       AND A.STOR_CD = C.STOR_CD
       AND A.SALE_DT = C.SALE_DT
       AND A.POS_NO  = C.POS_NO
       AND A.RCPT_NO = C.RCPT_NO
       AND A.COMP_CD = P.COMP_CD
       AND A.SALE_TYPE_CD = '1'
       AND A.SALE_DT <= P.BASE_DT
       AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E                       -- 판매취소가 아닌것 (다른 날 취소 포함)
                        WHERE E.COMP_CD = A.COMP_CD
                          AND E.STOR_CD = A.STOR_CD
                          AND E.BILL_NO = A.BILL_NO
                          AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)
),

-- H신고 재반입면장 교환권 빌  ← 고객 쿼리 "2." (147행 오타 대신 UNION 으로 중복 제거)
H_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO                         /* WM038 면장기준 IFWM11M */
      FROM BO0110M BM, BO0110D BD, IFWM11M IM, MA0151D MD, PRM P
     WHERE BM.COMP_CD = BD.COMP_CD
       AND BM.STOR_CD = BD.STOR_CD
       AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
       AND BM.COMP_CD = IM.COMP_CD
       AND BM.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_STAT_CD = 'G1'                                  /* 확정통보 */
       AND BM.COMP_CD = MD.COMP_CD
       AND BM.PMIT_CLS_CD = MD.COMM_CTG_DTL_CD
       AND MD.WRK_MDUL_CD = 'WM'
       AND MD.COMM_CTG_CD = 'WM038'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91')
       AND MD.COMM_PROP_CONT_1 = 'H'                                  -- H신고
       AND NVL(BM.DEL_YN, 'N') = 'N'
       AND IM.EDI_RPT_DT <= P.BASE_DT
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO                         /* WM038에 없지만 대상 */
      FROM MK5010D MK, IFWM12M IM, PRM P
     WHERE MK.COMP_CD = IM.COMP_CD
       AND MK.EDI_RPT_NO = IM.EDI_RPT_NO
       AND IM.EDI_DOC_CLS_CD = '5KP'
       AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')                           /* B:반품(인도후), R:미인도물품재반입 */
       AND IM.EDI_DOC_STAT_CD = 'F1'                                  /* 결과통보 */
       AND IM.EDI_RPT_DT <= P.BASE_DT
),

-- ① 구성요소 (점·코너·상품·에이징 단위, 부호 포함)
COMP AS (
    -- 수불 기말재고 (통물 코너만)
    SELECT 'SUBUL' SRC, S.STOR_CD, S.CORN_CD, S.GOOS_CD, S.AGIG_CD, S.QTY
      FROM WM0053L S, PRM P
     WHERE S.COMP_CD = P.COMP_CD
       AND S.YMON = P.YMON
       AND S.STOR_CD IN (SELECT STOR_CD FROM BOND)
       AND S.CORN_CD IN (SELECT CORN_CD FROM TONG)
    UNION ALL
    -- 교환권 (+) : 매출/통물창고, 매출/통물미래보세, 면장등록/통물미래보세
    SELECT 'EXCH', X.STOC_STOR_CD, X.STOC_CORN_CD, X.GOOS_CD, X.AGIG_CD, X.QTY
      FROM SALE X
     WHERE (X.BILL_PROC_CLS_CD, X.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
       AND X.STOC_STOR_CD IN (SELECT STOR_CD FROM BOND)
    UNION ALL
    -- H신고 재반입 교환권 (−)
    SELECT 'HREENT', X.STOC_STOR_CD, X.STOC_CORN_CD, X.GOOS_CD, X.AGIG_CD, -X.QTY
      FROM SALE X
     WHERE (X.COMP_CD, X.STOR_CD, X.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
       AND X.STOC_STOR_CD IN (SELECT STOR_CD FROM BOND)
),

-- ② 환급코드 먼저 반영 (행 단위) + 보세구역·장치장 붙이기
TAGGED AS (
    SELECT B.BOND_GRN_CD,
           NVL(T.SHED_CD, '미매핑:' || X.CORN_CD)                  SHED_CD,     -- 통물 코너가 아니면 드러나게
           X.SRC, X.GOOS_CD, X.QTY,
           CASE WHEN SUBSTR(X.AGIG_CD, 6, 1) = '1' THEN 'W'
                WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                ELSE 'D' END                                       CSTM_GOODS_TYPE_CD,
           G.GOOS_CD                                               MST_GOOS_CD,
           G.GOOS_TYPE_CD
      FROM COMP X
      JOIN BOND B          ON B.STOR_CD = X.STOR_CD
      LEFT JOIN TONG T     ON T.CORN_CD = X.CORN_CD
      LEFT JOIN MA0040C G  ON G.COMP_CD = '01' AND G.GOOS_CD = X.GOOS_CD
),
CODED AS (
    SELECT T.*,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                     THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
           END                                                     NEW_CSTM_GOOS_CD,
           CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                ELSE 'NO_TYPE' END                                 MATCH_BY
      FROM TAGGED T
      LEFT JOIN MA9301C R ON R.COMP_CD = '01' AND R.USE_YN = 'Y'
                         AND R.GOOS_CD = T.GOOS_CD AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
),

-- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드  (구성요소별 수량도 같이)
AGG AS (
    SELECT C.BOND_GRN_CD, C.SHED_CD, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY,
           SUM(C.QTY)                                              QTY,
           SUM(CASE WHEN C.SRC = 'SUBUL'  THEN C.QTY ELSE 0 END)   Q_SUBUL,
           SUM(CASE WHEN C.SRC = 'EXCH'   THEN C.QTY ELSE 0 END)   Q_EXCH,
           SUM(CASE WHEN C.SRC = 'HREENT' THEN C.QTY ELSE 0 END)   Q_HREENT
      FROM CODED C
     GROUP BY C.BOND_GRN_CD, C.SHED_CD, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD, C.MATCH_BY
    HAVING SUM(C.QTY) > 0                                           -- 0 이하는 신고 제외 → [점검 1]
),

-- ④ 신고서 나누기 : (보세구역, 장치장) 마다, 9,999 품목 넘으면 다음 신고서
NUMBERED AS (
    SELECT A.*,
           ROW_NUMBER() OVER (PARTITION BY A.BOND_GRN_CD, A.SHED_CD
                              ORDER BY A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD) RN
      FROM AGG A
),
DECL AS (
    SELECT N.*,
           MOD(N.RN - 1, 9999) + 1 DOC_SEQ,
           D.STOR_NM,
           -- 신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+일련번호(8: 접두문자 + 케이스 '2'(통물 상품) + 순번 6)
           D.CSTM_CD || D.DEPT_CD || N.BOND_GRN_CD || SUBSTR(P.DECL_DT, 3, 2) || 'A'
             || D.SEQ_PREFIX || '2' || LPAD(DENSE_RANK() OVER (PARTITION BY N.BOND_GRN_CD
                                                                ORDER BY N.SHED_CD, CEIL(N.RN / 9999)), 6, '0') DECLARATION_NO
      FROM NUMBERED N
      JOIN BOND D ON D.BOND_GRN_CD = N.BOND_GRN_CD
      CROSS JOIN PRM P
)

SELECT X.DECLARATION_NO                                   AS DECLARATION_NO,        --  1 신고번호
       X.BOND_GRN_CD                                      AS WH_CODE,               --  2 신고지점
       'DLG'                                              AS DOC_TYPE,              --  3 문서구분
       P.DECL_DT                                          AS DECLARATION_DATE,      --  4 신고일자
       NULL                                               AS AMEND_TYPE,            --  5 정정구분
       X.SHED_CD                                          AS CARRYIN_LOC,           --  6 반입장치장소 = 통물 장치장
       NULL                                               AS REFERENCE_NO,          --  7 근거번호
       'Z'                                                AS DECLARATION_TYPE,      --  8 Z 기초재고반입
       'A1'                                               AS STATUS,                --  9 A1 생성
       SYSDATE                                            AS C_DATETIME,            -- 10 생성일시
       NULL                                               AS INTERNATIONAL_MAIL_YN, -- 11 국제우편여부
       ----------------------------------------------- 참고 (적재 제외)
       X.STOR_NM                                          AS REF_STOR_NM,
       COUNT(*)                                           AS REF_ITEM_CNT,
       SUM(X.QTY)                                         AS REF_QTY,
       SUM(X.Q_SUBUL)                                     AS REF_Q_SUBUL,
       SUM(X.Q_EXCH)                                      AS REF_Q_EXCH,
       SUM(X.Q_HREENT)                                    AS REF_Q_HREENT
  FROM DECL X
  CROSS JOIN PRM P
 GROUP BY X.DECLARATION_NO, X.BOND_GRN_CD, P.DECL_DT, X.SHED_CD, X.STOR_NM
 ORDER BY X.DECLARATION_NO;



/* =====================================================================
   [점검]
   ===================================================================== */
-- 점검 1) 0 이하라 신고에서 빠지는 것 / 통물 코너가 아닌 데로 잡힌 교환권·H재반입 (SHED '미매핑:코너')
--   Detail 쿼리의 AGG 의 HAVING 을 "SUM(C.QTY) <= 0 OR C.SHED_CD LIKE '미매핑%'" 로 바꿔서 확인
--   - 미매핑 코너가 교환권에서 나오면: 상품위치는 통물(02/12)인데 재고코너가 통물 코너가 아님 → TONG 에 추가할지 확인
--   - H재반입이 미매핑이면: 재반입 물건이 어디로 들어갔는지(어느 코너 수불에 잡혔는지) 확인

-- 점검 2) Header 의 REF_Q_SUBUL / REF_Q_EXCH / REF_Q_HREENT 합계를 고객에게 보여주고 사인오프
--         (점·장치장별 수불 + 교환권 − H재반입 = 계산재고)
