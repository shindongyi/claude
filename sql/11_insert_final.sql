/* =====================================================================
   11. 최종 INSERT — SR_ItemCarryIn_H / SR_ItemCarryIn_D  (케이스별 한방 INSERT 3개)
   ---------------------------------------------------------------------
   구조: INSERT ALL  (Header = DOC_SEQ 1 인 행에서 신고서마다 1건, Detail = 모든 행)
         = sql/10 한방 쿼리 + 품목정보(MA0040C / WM0310C) + 신고번호 채번
   바인드: :BASE_DT     기준일 (YYYYMMDD)
           :DECL_DT     신고일자 (YYYYMMDD)
           :SEQ_PREFIX  일련번호 첫 글자 (면세점 A~T 중 고객 지정, Y·U 금지)
   신고번호 = 세관(3)+과(2)+보세구역(8)+년도(2)+'A'+[접두문자 1 + 케이스 1 + 순번 6]
             케이스 1 상품 / 2 GWP / 3 미인도 → 세 INSERT 의 번호가 겹치지 않음

   ★ 실행 전 반드시
     1) sql/10 의 SELECT 3개를 먼저 돌려 아래가 0건인지 확인 (이 행들은 INSERT 에서 조용히 빠짐)
        - UNMAPPED_KEY 있는 행 (코너→장치장 매핑 누락)
        - ITEM_TYPE = '?' (물품구분 미판정)   - ITEM_QTY < 0 (음수 재고)
     2) TODO 채우기: MAP_STOR, MAP_CLS, GWP_TYPE, CSTM_OFFICE, GOOS_INFO(MA0040C/WM0310C 컬럼명·추가 조인)
     3) 맨 아래 "적재 전 필수값 점검" 0건 확인 (NOT NULL 컬럼이 하나라도 비면 INSERT 전체 실패)

   ※ H/D 사이에 FK 가 있으면 INSERT ALL 은 Header→Detail 순서를 보장하지 않음 → 실패하면
     같은 WITH ... SELECT 로 두 번:  INSERT INTO SR_ItemCarryIn_H ... SELECT ... WHERE DOC_SEQ = 1
                                     INSERT INTO SR_ItemCarryIn_D ... SELECT ...
   ※ 대상 테이블이 다른 DB(DB Link 포함)면 INSERT ALL 불가 → SELECT 결과를 MIG_DECL_H/D 에 넣고 sql/09 방법 2
   ※ 재실행 시 같은 신고번호가 생기므로 맨 아래 "되돌리기"로 먼저 지울 것
   ===================================================================== */


/* ============================ ① 상품 → 신고구분 Z (기초재고반입) ============================ */
INSERT ALL
  WHEN DOC_SEQ = 1 THEN                     -- 신고서마다 Header 1건
    INTO SR_ItemCarryIn_H
         (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, reference_no,
          declaration_type, status, c_datetime, international_mail_yn)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, NULL, CARRYIN_LOC, NULL,
            DECLARATION_TYPE, 'A1', SYSDATE, 'N')
  WHEN 1 = 1 THEN                           -- 모든 행 Detail
    INTO SR_ItemCarryIn_D
         (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name,
          item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, unit_code,
          gwp_product_grade, register_no, item_cost_krw, qty_unit_code)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, NULL, ITEM_TYPE, HS_CODE, ITEM_CODE, ITEM_NAME,
            ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME, UNIT_CODE,
            GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE)
WITH
PRM AS (SELECT '01' COMP_CD, :BASE_DT BASE_DT FROM DUAL),
CSTM_OFFICE AS (                            -- 보세구역별 세관(3)·과(2) 코드  ※ Q24 확인 후 채움
    SELECT '01022006' WH_CODE, '???' CSTM_CD, '??' DEPT_CD FROM DUAL UNION ALL
    SELECT '04021040', '???', '??' FROM DUAL UNION ALL
    SELECT '04021041', '???', '??' FROM DUAL),
GOOS_INFO AS (                              -- 품목 정보  ※ 컬럼명은 MA0040C / WM0310C 확인 후 교체 (TODO)
    SELECT 'G' KIND, M.GOOS_CD,
           M.HS_CD, M.GOOS_NM, M.GOOS_NORM, M.BRAN_CD, M.BRAN_NM,                         -- TODO
           M.SALE_DOLR_UCST, M.SALE_WON_UCST, M.CAPACITY, M.CAPA_UNIT_CD, M.QTY_UNIT_CD,  -- TODO
           CAST(NULL AS CHAR(1)) GWP_GRADE
      FROM MA0040C M WHERE M.COMP_CD = '01'
    UNION ALL
    SELECT 'W', W.GOOS_CD,
           W.HS_CD, W.GOOS_NM, W.GOOS_NORM, W.BRAN_CD, W.BRAN_NM,                         -- TODO
           0, 0, W.CAPACITY, W.CAPA_UNIT_CD, W.QTY_UNIT_CD,                               -- TODO (GWP 단가 0)
           W.GWP_GRADE                                                                    -- TODO
      FROM WM0310C W WHERE W.COMP_CD = '01'),
BOND AS (                                   -- 보세구역 → 자기 장치장 구분
    SELECT '01022006' WH_CODE, 'MAIN' SITE_GRP FROM DUAL UNION ALL
    SELECT '04021040', 'T1' FROM DUAL UNION ALL
    SELECT '04021041', 'T2' FROM DUAL),
MAP_STOR AS (                               -- (재고점, 재고코너) → 보세구역/장치장  ※ Q21 확인 후 채움
    SELECT CAST(NULL AS VARCHAR2(10)) STOR_CD, CAST(NULL AS VARCHAR2(10)) CORN_CD,
           CAST(NULL AS VARCHAR2(10)) SITE_GRP, CAST(NULL AS VARCHAR2(8)) WH_CODE, CAST(NULL AS VARCHAR2(8)) SHED_CD
      FROM DUAL WHERE 1 = 0
    -- 예) UNION ALL SELECT '05', '961', 'LOGI', '01022006', '04077090' FROM DUAL
    --     UNION ALL SELECT '05', '*',   'MAIN', '01022006', '01022006' FROM DUAL   -- '*' = 그 점의 나머지 코너
),
MAP_CLS AS (                                -- 환급 구분 원천값 → 물품구분 T/W/H/D  ※ Q23 확인 후 채움
    SELECT CAST(NULL AS VARCHAR2(4)) SRC_TYPE, CAST(NULL AS VARCHAR2(10)) SRC_VAL, CAST(NULL AS CHAR(1)) ITEM_TYPE
      FROM DUAL WHERE 1 = 0
    -- 예) UNION ALL SELECT 'CSTM', '1', 'T' FROM DUAL    -- WM0121L.CSTM_ITEM_CLS_CD (MA071)
    --     UNION ALL SELECT 'REFU', '1', 'W' FROM DUAL    -- 수불 REFU_CLS_CD (GO407)
),
VALID_BILL AS (                             -- 기준일 현재 판매취소 안 된 정상매출 빌
    SELECT SA.COMP_CD, SA.STOR_CD, SA.SALE_DT, SA.POS_NO, SA.RCPT_NO, SA.BILL_NO,
           SA.BILL_PROC_CLS_CD, SA.GOOS_LOC_CLS_CD, SA.STOC_STOR_CD, SA.STOC_CORN_CD
      FROM SA0100M SA, PRM P
     WHERE SA.COMP_CD = P.COMP_CD
       AND SA.SALE_TYPE_CD = '1'
       AND SA.SALE_DT <= P.BASE_DT
       AND NVL(SA.BILL_PROC_CLS_CD, '00') <> '08'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = SA.COMP_CD AND E.STOR_CD = SA.STOR_CD AND E.BILL_NO = SA.BILL_NO
                          AND E.SALE_TYPE_CD <> SA.SALE_TYPE_CD
                          AND E.SALE_DT <= P.BASE_DT)            -- 날짜 달라도 취소면 제외
),
SALE_LINE AS (                              -- 상품 라인
    SELECT B.COMP_CD, B.STOR_CD, B.BILL_NO, B.BILL_PROC_CLS_CD, B.GOOS_LOC_CLS_CD,
           NVL(D.STOC_STOR_CD, B.STOC_STOR_CD) S_STOR, NVL(D.STOC_CORN_CD, B.STOC_CORN_CD) S_CORN,
           D.GOOS_CD, D.GOOS_QTY QTY
      FROM VALID_BILL B
      JOIN SA0103D D ON D.COMP_CD = B.COMP_CD AND D.STOR_CD = B.STOR_CD AND D.SALE_DT = B.SALE_DT
                    AND D.POS_NO = B.POS_NO AND D.RCPT_NO = B.RCPT_NO
     WHERE NVL(D.SALE_CNCL_YN, 'N') = 'N'
),
H_BILL AS (                                 -- H신고 재반입 교환권 (빌 키, 중복 자동 제거)
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      JOIN MA0151D MD ON MD.COMP_CD = BM.COMP_CD AND MD.WRK_MDUL_CD = 'WM' AND MD.COMM_CTG_CD = 'WM038'
                     AND MD.COMM_CTG_DTL_CD = BM.PMIT_CLS_CD
      CROSS JOIN PRM P
     WHERE BM.COMP_CD = P.COMP_CD AND NVL(BM.DEL_YN, 'N') = 'N'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91') AND MD.COMM_PROP_CONT_1 = 'H'
       AND EXISTS (SELECT 1 FROM IFWM11M IM WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1' AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK CROSS JOIN PRM P
     WHERE MK.COMP_CD = P.COMP_CD
       AND EXISTS (SELECT 1 FROM IFWM12M IM WHERE IM.COMP_CD = MK.COMP_CD AND IM.EDI_RPT_NO = MK.EDI_RPT_NO
                      AND IM.EDI_DOC_CLS_CD = '5KP' AND IM.CSTM_RPT_CLS_CD IN ('B','R') AND IM.EDI_DOC_STAT_CD = 'F1'
                      AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
),
U_BILL AS (                                 -- 미인도반입면장 교환권
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      CROSS JOIN PRM P
     WHERE BM.COMP_CD = P.COMP_CD AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.PMIT_CLS_CD IN ('06','76','86')
       AND EXISTS (SELECT 1 FROM IFWM11M IM WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1' AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
),
GOOS_CLS AS (                               -- 매출에서 온 수량의 환급구분: 기준일 수불의 같은 상품 값 사용 (가정, Q23)
    SELECT S.GOOS_CD, MAX(S.REFU_CLS_CD) REFU_CLS_CD
      FROM WM0052L S, PRM P
     WHERE S.COMP_CD = P.COMP_CD AND S.RD_DT = P.BASE_DT
     GROUP BY S.GOOS_CD
),
COMP AS (                                   -- 구성요소 (부호 포함 수량)
    SELECT 'C01' SRC, CAST(NULL AS VARCHAR2(10)) STOR_CD, CAST(NULL AS VARCHAR2(10)) CORN_CD,
           L.BOND_GRN_CD WH_CODE, L.SHED_CD, L.GOOS_CD, 'CSTM' CLS_SRC, L.CSTM_ITEM_CLS_CD CLS_VAL,
           NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0) QTY
      FROM WM0121L L, PRM P                                     -- HS세관재고: 자기 장치장만
     WHERE L.COMP_CD = P.COMP_CD AND L.EDI_REPA_DT <= P.BASE_DT
       AND L.SHED_CD = L.BOND_GRN_CD AND L.BOND_GRN_CD IN (SELECT WH_CODE FROM BOND)
    UNION ALL
    SELECT 'C02', S.STOR_CD, S.CORN_CD, NULL, NULL, S.GOOS_CD, 'REFU', S.REFU_CLS_CD, S.QTY
      FROM WM0052L S, PRM P                                     -- 상품 일수불 (기준일 잔량)
     WHERE S.COMP_CD = P.COMP_CD AND S.RD_DT = P.BASE_DT
    UNION ALL
    SELECT 'C03', L.S_STOR, L.S_CORN, NULL, NULL, L.GOOS_CD, 'REFU', G.REFU_CLS_CD, L.QTY
      FROM SALE_LINE L LEFT JOIN GOOS_CLS G ON G.GOOS_CD = L.GOOS_CD   -- 교환권 (+)
     WHERE (L.BILL_PROC_CLS_CD, L.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
    UNION ALL
    SELECT 'C04', L.S_STOR, L.S_CORN, NULL, NULL, L.GOOS_CD, 'REFU', G.REFU_CLS_CD, -L.QTY
      FROM SALE_LINE L                                                  -- H신고 재반입 (−)
      JOIN H_BILL H ON H.COMP_CD = L.COMP_CD AND H.STOR_CD = L.STOR_CD AND H.BILL_NO = L.BILL_NO
      LEFT JOIN GOOS_CLS G ON G.GOOS_CD = L.GOOS_CD
    UNION ALL
    SELECT 'C05', L.S_STOR, L.S_CORN, NULL, NULL, L.GOOS_CD, 'REFU', G.REFU_CLS_CD, -L.QTY
      FROM SALE_LINE L                                                  -- 미인도 (−)
      JOIN U_BILL U ON U.COMP_CD = L.COMP_CD AND U.STOR_CD = L.STOR_CD AND U.BILL_NO = L.BILL_NO
      LEFT JOIN GOOS_CLS G ON G.GOOS_CD = L.GOOS_CD
),
MAPPED AS (
    SELECT C.SRC, C.GOOS_CD, C.CLS_SRC, C.CLS_VAL, C.QTY,
           COALESCE(BD.SITE_GRP, M1.SITE_GRP, M2.SITE_GRP) SITE_GRP,
           COALESCE(C.WH_CODE, M1.WH_CODE, M2.WH_CODE)     WH,
           COALESCE(C.SHED_CD, M1.SHED_CD, M2.SHED_CD)     SHED,
           CASE WHEN C.WH_CODE IS NULL AND M1.WH_CODE IS NULL AND M2.WH_CODE IS NULL
                THEN C.STOR_CD || '/' || C.CORN_CD END       UNMAPPED_KEY
      FROM COMP C
      LEFT JOIN BOND BD     ON BD.WH_CODE = C.WH_CODE
      LEFT JOIN MAP_STOR M1 ON M1.STOR_CD = C.STOR_CD AND M1.CORN_CD = C.CORN_CD
      LEFT JOIN MAP_STOR M2 ON M2.STOR_CD = C.STOR_CD AND M2.CORN_CD = '*'
),
RULED AS (                                  -- 고객 규칙 적용
    SELECT M.* FROM MAPPED M
     WHERE (M.SRC = 'C01' AND M.SITE_GRP IN ('MAIN','T1','T2'))
        OR (M.SRC IN ('C02','C03','C04') AND M.SITE_GRP = 'LOGI')
        OR (M.SRC = 'C05' AND M.SITE_GRP IN ('MAIN','LOGI'))
        OR M.UNMAPPED_KEY IS NOT NULL                              -- 매핑 누락은 결과에 드러나게
),
AGG AS (
    SELECT R.WH, R.SHED, R.UNMAPPED_KEY, NVL(MC.ITEM_TYPE, '?') ITEM_TYPE, R.GOOS_CD,
           SUM(R.QTY) QTY,
           SUM(CASE WHEN R.SRC = 'C01' THEN R.QTY END) Q_CSTM,
           SUM(CASE WHEN R.SRC = 'C02' THEN R.QTY END) Q_SUBUL,
           SUM(CASE WHEN R.SRC = 'C03' THEN R.QTY END) Q_EXCH,
           SUM(CASE WHEN R.SRC = 'C04' THEN R.QTY END) Q_HREENT,
           SUM(CASE WHEN R.SRC = 'C05' THEN R.QTY END) Q_UDLV
      FROM RULED R
      LEFT JOIN MAP_CLS MC ON MC.SRC_TYPE = R.CLS_SRC AND MC.SRC_VAL = R.CLS_VAL
     GROUP BY R.WH, R.SHED, R.UNMAPPED_KEY, NVL(MC.ITEM_TYPE, '?'), R.GOOS_CD
),
SRC_ROWS AS (                               -- 문제 행(매핑 누락, '?', 0 이하)은 제외 → sql/10 으로 미리 0건 확인
    SELECT A.WH, A.SHED, A.ITEM_TYPE, 'G' KIND, A.GOOS_CD, CAST(NULL AS VARCHAR2(24)) REGISTER_NO, A.QTY
      FROM AGG A
     WHERE A.QTY > 0 AND A.UNMAPPED_KEY IS NULL AND A.ITEM_TYPE <> '?'
),
NUMBERED AS (
    SELECT S.*, ROW_NUMBER() OVER (PARTITION BY S.WH, S.SHED
                                   ORDER BY S.REGISTER_NO, S.KIND, S.ITEM_TYPE, S.GOOS_CD) RN
      FROM SRC_ROWS S
),
GRP AS (                                    -- 9,999 품목씩 신고서 분할
    SELECT N.*, CEIL(N.RN / 9999) DECL_GRP, MOD(N.RN - 1, 9999) + 1 DOC_SEQ FROM NUMBERED N
),
FIN AS (                                    -- 보세구역 안 신고서 순번
    SELECT G.*, DENSE_RANK() OVER (PARTITION BY G.WH ORDER BY G.SHED, G.DECL_GRP) DECL_SEQ FROM GRP G
)
SELECT O.CSTM_CD || O.DEPT_CD || F.WH || SUBSTR(:DECL_DT, 3, 2) || 'A'
       || :SEQ_PREFIX || '1' || LPAD(F.DECL_SEQ, 6, '0')      AS DECLARATION_NO,
       F.WH                                                 AS WH_CODE,
       'DLG'                                                AS DOC_TYPE,
       :DECL_DT                                             AS DECLARATION_DATE,
       CASE WHEN F.SHED = F.WH THEN NULL ELSE F.SHED END    AS CARRYIN_LOC,
       'Z'                                                  AS DECLARATION_TYPE,
       F.DOC_SEQ,
       F.ITEM_TYPE,
       I.HS_CD                                              AS HS_CODE,
       F.GOOS_CD                                            AS ITEM_CODE,
       I.GOOS_NM                                            AS ITEM_NAME,
       NVL(I.GOOS_NORM, '-')                                AS ITEM_NORM,
       F.QTY                                                AS ITEM_QTY,
       NVL(I.SALE_DOLR_UCST, 0)                             AS ITEM_COST,
       F.QTY * NVL(I.SALE_DOLR_UCST, 0)                     AS ITEM_AMOUNT,
       NVL(I.CAPACITY, 0)                                   AS CAPACITY,
       I.BRAN_CD                                            AS BRAND_CODE,
       I.BRAN_NM                                            AS BRAND_NAME,
       I.CAPA_UNIT_CD                                       AS UNIT_CODE,
       I.GWP_GRADE                                          AS GWP_PRODUCT_GRADE,
       F.REGISTER_NO,
       NVL(I.SALE_WON_UCST, 0)                              AS ITEM_COST_KRW,
       I.QTY_UNIT_CD                                        AS QTY_UNIT_CODE
  FROM FIN F
  JOIN CSTM_OFFICE O    ON O.WH_CODE = F.WH
  LEFT JOIN GOOS_INFO I ON I.KIND = F.KIND AND I.GOOS_CD = F.GOOS_CD;

-- 건수 확인 후 COMMIT;


/* ============================ ② GWP → 신고구분 Z (기초재고반입) ============================ */
INSERT ALL
  WHEN DOC_SEQ = 1 THEN                     -- 신고서마다 Header 1건
    INTO SR_ItemCarryIn_H
         (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, reference_no,
          declaration_type, status, c_datetime, international_mail_yn)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, NULL, CARRYIN_LOC, NULL,
            DECLARATION_TYPE, 'A1', SYSDATE, 'N')
  WHEN 1 = 1 THEN                           -- 모든 행 Detail
    INTO SR_ItemCarryIn_D
         (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name,
          item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, unit_code,
          gwp_product_grade, register_no, item_cost_krw, qty_unit_code)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, NULL, ITEM_TYPE, HS_CODE, ITEM_CODE, ITEM_NAME,
            ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME, UNIT_CODE,
            GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE)
WITH
PRM AS (SELECT '01' COMP_CD, :BASE_DT BASE_DT FROM DUAL),
CSTM_OFFICE AS (                            -- 보세구역별 세관(3)·과(2) 코드  ※ Q24 확인 후 채움
    SELECT '01022006' WH_CODE, '???' CSTM_CD, '??' DEPT_CD FROM DUAL UNION ALL
    SELECT '04021040', '???', '??' FROM DUAL UNION ALL
    SELECT '04021041', '???', '??' FROM DUAL),
GOOS_INFO AS (                              -- 품목 정보  ※ 컬럼명은 MA0040C / WM0310C 확인 후 교체 (TODO)
    SELECT 'G' KIND, M.GOOS_CD,
           M.HS_CD, M.GOOS_NM, M.GOOS_NORM, M.BRAN_CD, M.BRAN_NM,                         -- TODO
           M.SALE_DOLR_UCST, M.SALE_WON_UCST, M.CAPACITY, M.CAPA_UNIT_CD, M.QTY_UNIT_CD,  -- TODO
           CAST(NULL AS CHAR(1)) GWP_GRADE
      FROM MA0040C M WHERE M.COMP_CD = '01'
    UNION ALL
    SELECT 'W', W.GOOS_CD,
           W.HS_CD, W.GOOS_NM, W.GOOS_NORM, W.BRAN_CD, W.BRAN_NM,                         -- TODO
           0, 0, W.CAPACITY, W.CAPA_UNIT_CD, W.QTY_UNIT_CD,                               -- TODO (GWP 단가 0)
           W.GWP_GRADE                                                                    -- TODO
      FROM WM0310C W WHERE W.COMP_CD = '01'),
GWP_TYPE AS (SELECT '?' ITEM_TYPE FROM DUAL),    -- GWP 물품구분(T/W/H/D) — GWP 수불엔 환급구분이 없음 → 고객 확인 후 고정값 (Q23)
MAP_STOR AS (
    SELECT CAST(NULL AS VARCHAR2(10)) STOR_CD, CAST(NULL AS VARCHAR2(10)) CORN_CD,
           CAST(NULL AS VARCHAR2(10)) SITE_GRP, CAST(NULL AS VARCHAR2(8)) WH_CODE, CAST(NULL AS VARCHAR2(8)) SHED_CD
      FROM DUAL WHERE 1 = 0
),
VALID_BILL AS (
    SELECT SA.COMP_CD, SA.STOR_CD, SA.SALE_DT, SA.POS_NO, SA.RCPT_NO, SA.BILL_NO,
           SA.BILL_PROC_CLS_CD, SA.GOOS_LOC_CLS_CD, SA.STOC_STOR_CD, SA.STOC_CORN_CD
      FROM SA0100M SA, PRM P
     WHERE SA.COMP_CD = P.COMP_CD AND SA.SALE_TYPE_CD = '1' AND SA.SALE_DT <= P.BASE_DT
       AND NVL(SA.BILL_PROC_CLS_CD, '00') <> '08'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = SA.COMP_CD AND E.STOR_CD = SA.STOR_CD AND E.BILL_NO = SA.BILL_NO
                          AND E.SALE_TYPE_CD <> SA.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
),
SALE_LINE AS (                              -- GWP 라인 (SA0109D: 라인 취소 컬럼 없음)
    SELECT B.COMP_CD, B.STOR_CD, B.BILL_NO, B.BILL_PROC_CLS_CD, B.GOOS_LOC_CLS_CD,
           NVL(G.STOC_STOR_CD, B.STOC_STOR_CD) S_STOR, NVL(G.STOC_CORN_CD, B.STOC_CORN_CD) S_CORN,
           G.GOOS_CD, G.PMNT_QTY QTY
      FROM VALID_BILL B
      JOIN SA0109D G ON G.COMP_CD = B.COMP_CD AND G.STOR_CD = B.STOR_CD AND G.SALE_DT = B.SALE_DT
                    AND G.POS_NO = B.POS_NO AND G.RCPT_NO = B.RCPT_NO
),
H_BILL AS (
    SELECT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      JOIN MA0151D MD ON MD.COMP_CD = BM.COMP_CD AND MD.WRK_MDUL_CD = 'WM' AND MD.COMM_CTG_CD = 'WM038'
                     AND MD.COMM_CTG_DTL_CD = BM.PMIT_CLS_CD
      CROSS JOIN PRM P
     WHERE BM.COMP_CD = P.COMP_CD AND NVL(BM.DEL_YN, 'N') = 'N'
       AND MD.COMM_CTG_DTL_CD IN ('05','75','85','10','80','90','20','91') AND MD.COMM_PROP_CONT_1 = 'H'
       AND EXISTS (SELECT 1 FROM IFWM11M IM WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1' AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
    UNION
    SELECT MK.COMP_CD, MK.STOR_CD, MK.BILL_NO
      FROM MK5010D MK CROSS JOIN PRM P
     WHERE MK.COMP_CD = P.COMP_CD
       AND EXISTS (SELECT 1 FROM IFWM12M IM WHERE IM.COMP_CD = MK.COMP_CD AND IM.EDI_RPT_NO = MK.EDI_RPT_NO
                      AND IM.EDI_DOC_CLS_CD = '5KP' AND IM.CSTM_RPT_CLS_CD IN ('B','R') AND IM.EDI_DOC_STAT_CD = 'F1'
                      AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
),
U_BILL AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      CROSS JOIN PRM P
     WHERE BM.COMP_CD = P.COMP_CD AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.PMIT_CLS_CD IN ('06','76','86')
       AND EXISTS (SELECT 1 FROM IFWM11M IM WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1' AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
),
COMP AS (
    SELECT 'C02' SRC, S.STOR_CD, S.CORN_CD, S.GOOS_CD, S.QTY
      FROM WM0352L S, PRM P                                     -- GWP 일수불 (기준일 잔량)
     WHERE S.COMP_CD = P.COMP_CD AND S.RD_DT = P.BASE_DT
    UNION ALL
    SELECT 'C03', L.S_STOR, L.S_CORN, L.GOOS_CD, L.QTY
      FROM SALE_LINE L
     WHERE (L.BILL_PROC_CLS_CD, L.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
    UNION ALL
    SELECT 'C04', L.S_STOR, L.S_CORN, L.GOOS_CD, -L.QTY
      FROM SALE_LINE L JOIN H_BILL H ON H.COMP_CD = L.COMP_CD AND H.STOR_CD = L.STOR_CD AND H.BILL_NO = L.BILL_NO
    UNION ALL
    SELECT 'C05', L.S_STOR, L.S_CORN, L.GOOS_CD, -L.QTY
      FROM SALE_LINE L JOIN U_BILL U ON U.COMP_CD = L.COMP_CD AND U.STOR_CD = L.STOR_CD AND U.BILL_NO = L.BILL_NO
),
MAPPED AS (
    SELECT C.SRC, C.GOOS_CD, C.QTY,
           COALESCE(M1.SITE_GRP, M2.SITE_GRP) SITE_GRP,
           COALESCE(M1.WH_CODE, M2.WH_CODE)   WH,
           COALESCE(M1.SHED_CD, M2.SHED_CD)   SHED,
           CASE WHEN M1.WH_CODE IS NULL AND M2.WH_CODE IS NULL THEN C.STOR_CD || '/' || C.CORN_CD END UNMAPPED_KEY
      FROM COMP C
      LEFT JOIN MAP_STOR M1 ON M1.STOR_CD = C.STOR_CD AND M1.CORN_CD = C.CORN_CD
      LEFT JOIN MAP_STOR M2 ON M2.STOR_CD = C.STOR_CD AND M2.CORN_CD = '*'
),
RULED AS (
    SELECT M.* FROM MAPPED M
     WHERE (M.SRC = 'C02')                                        -- 수불은 전 장치장
        OR (M.SRC IN ('C03','C04','C05') AND M.SITE_GRP IN ('MAIN','LOGI'))   -- 보정은 본점·통물만
        OR M.UNMAPPED_KEY IS NOT NULL
),
AGG AS (
    SELECT R.WH, R.SHED, R.UNMAPPED_KEY, R.GOOS_CD,
           SUM(R.QTY) QTY,
           SUM(CASE WHEN R.SRC = 'C02' THEN R.QTY END) Q_SUBUL,
           SUM(CASE WHEN R.SRC = 'C03' THEN R.QTY END) Q_EXCH,
           SUM(CASE WHEN R.SRC = 'C04' THEN R.QTY END) Q_HREENT,
           SUM(CASE WHEN R.SRC = 'C05' THEN R.QTY END) Q_UDLV
      FROM RULED R
     GROUP BY R.WH, R.SHED, R.UNMAPPED_KEY, R.GOOS_CD
),
SRC_ROWS AS (
    SELECT A.WH, A.SHED, T.ITEM_TYPE, 'W' KIND, A.GOOS_CD, CAST(NULL AS VARCHAR2(24)) REGISTER_NO, A.QTY
      FROM AGG A CROSS JOIN GWP_TYPE T
     WHERE A.QTY > 0 AND A.UNMAPPED_KEY IS NULL AND T.ITEM_TYPE <> '?'
),
NUMBERED AS (
    SELECT S.*, ROW_NUMBER() OVER (PARTITION BY S.WH, S.SHED
                                   ORDER BY S.REGISTER_NO, S.KIND, S.ITEM_TYPE, S.GOOS_CD) RN
      FROM SRC_ROWS S
),
GRP AS (                                    -- 9,999 품목씩 신고서 분할
    SELECT N.*, CEIL(N.RN / 9999) DECL_GRP, MOD(N.RN - 1, 9999) + 1 DOC_SEQ FROM NUMBERED N
),
FIN AS (                                    -- 보세구역 안 신고서 순번
    SELECT G.*, DENSE_RANK() OVER (PARTITION BY G.WH ORDER BY G.SHED, G.DECL_GRP) DECL_SEQ FROM GRP G
)
SELECT O.CSTM_CD || O.DEPT_CD || F.WH || SUBSTR(:DECL_DT, 3, 2) || 'A'
       || :SEQ_PREFIX || '2' || LPAD(F.DECL_SEQ, 6, '0')      AS DECLARATION_NO,
       F.WH                                                 AS WH_CODE,
       'DLG'                                                AS DOC_TYPE,
       :DECL_DT                                             AS DECLARATION_DATE,
       CASE WHEN F.SHED = F.WH THEN NULL ELSE F.SHED END    AS CARRYIN_LOC,
       'Z'                                                  AS DECLARATION_TYPE,
       F.DOC_SEQ,
       F.ITEM_TYPE,
       I.HS_CD                                              AS HS_CODE,
       F.GOOS_CD                                            AS ITEM_CODE,
       I.GOOS_NM                                            AS ITEM_NAME,
       NVL(I.GOOS_NORM, '-')                                AS ITEM_NORM,
       F.QTY                                                AS ITEM_QTY,
       NVL(I.SALE_DOLR_UCST, 0)                             AS ITEM_COST,
       F.QTY * NVL(I.SALE_DOLR_UCST, 0)                     AS ITEM_AMOUNT,
       NVL(I.CAPACITY, 0)                                   AS CAPACITY,
       I.BRAN_CD                                            AS BRAND_CODE,
       I.BRAN_NM                                            AS BRAND_NAME,
       I.CAPA_UNIT_CD                                       AS UNIT_CODE,
       I.GWP_GRADE                                          AS GWP_PRODUCT_GRADE,
       F.REGISTER_NO,
       NVL(I.SALE_WON_UCST, 0)                              AS ITEM_COST_KRW,
       I.QTY_UNIT_CD                                        AS QTY_UNIT_CODE
  FROM FIN F
  JOIN CSTM_OFFICE O    ON O.WH_CODE = F.WH
  LEFT JOIN GOOS_INFO I ON I.KIND = F.KIND AND I.GOOS_CD = F.GOOS_CD;

-- 건수 확인 후 COMMIT;


/* ============================ ③ 미인도 (상품+GWP) → 신고구분 Y (미인도물품재고반입) ============================ */
INSERT ALL
  WHEN DOC_SEQ = 1 THEN                     -- 신고서마다 Header 1건
    INTO SR_ItemCarryIn_H
         (declaration_no, wh_code, doc_type, declaration_date, amend_type, carryin_loc, reference_no,
          declaration_type, status, c_datetime, international_mail_yn)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, NULL, CARRYIN_LOC, NULL,
            DECLARATION_TYPE, 'A1', SYSDATE, 'N')
  WHEN 1 = 1 THEN                           -- 모든 행 Detail
    INTO SR_ItemCarryIn_D
         (declaration_no, wh_code, doc_type, doc_seq, ramend_type, item_type, hs_code, item_code, item_name,
          item_norm, item_qty, item_cost, item_amount, capacity, brand_code, brand_name, unit_code,
          gwp_product_grade, register_no, item_cost_krw, qty_unit_code)
    VALUES (DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, NULL, ITEM_TYPE, HS_CODE, ITEM_CODE, ITEM_NAME,
            ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME, UNIT_CODE,
            GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE)
WITH
PRM AS (SELECT '01' COMP_CD, :BASE_DT BASE_DT FROM DUAL),
CSTM_OFFICE AS (                            -- 보세구역별 세관(3)·과(2) 코드  ※ Q24 확인 후 채움
    SELECT '01022006' WH_CODE, '???' CSTM_CD, '??' DEPT_CD FROM DUAL UNION ALL
    SELECT '04021040', '???', '??' FROM DUAL UNION ALL
    SELECT '04021041', '???', '??' FROM DUAL),
GOOS_INFO AS (                              -- 품목 정보  ※ 컬럼명은 MA0040C / WM0310C 확인 후 교체 (TODO)
    SELECT 'G' KIND, M.GOOS_CD,
           M.HS_CD, M.GOOS_NM, M.GOOS_NORM, M.BRAN_CD, M.BRAN_NM,                         -- TODO
           M.SALE_DOLR_UCST, M.SALE_WON_UCST, M.CAPACITY, M.CAPA_UNIT_CD, M.QTY_UNIT_CD,  -- TODO
           CAST(NULL AS CHAR(1)) GWP_GRADE
      FROM MA0040C M WHERE M.COMP_CD = '01'
    UNION ALL
    SELECT 'W', W.GOOS_CD,
           W.HS_CD, W.GOOS_NM, W.GOOS_NORM, W.BRAN_CD, W.BRAN_NM,                         -- TODO
           0, 0, W.CAPACITY, W.CAPA_UNIT_CD, W.QTY_UNIT_CD,                               -- TODO (GWP 단가 0)
           W.GWP_GRADE                                                                    -- TODO
      FROM WM0310C W WHERE W.COMP_CD = '01'),
GWP_TYPE AS (SELECT '?' ITEM_TYPE FROM DUAL),    -- ②와 같은 값
MAP_STOR AS (
    SELECT CAST(NULL AS VARCHAR2(10)) STOR_CD, CAST(NULL AS VARCHAR2(10)) CORN_CD,
           CAST(NULL AS VARCHAR2(10)) SITE_GRP, CAST(NULL AS VARCHAR2(8)) WH_CODE, CAST(NULL AS VARCHAR2(8)) SHED_CD
      FROM DUAL WHERE 1 = 0
),
MAP_CLS AS (
    SELECT CAST(NULL AS VARCHAR2(4)) SRC_TYPE, CAST(NULL AS VARCHAR2(10)) SRC_VAL, CAST(NULL AS CHAR(1)) ITEM_TYPE
      FROM DUAL WHERE 1 = 0
),
VALID_BILL AS (
    SELECT SA.COMP_CD, SA.STOR_CD, SA.SALE_DT, SA.POS_NO, SA.RCPT_NO, SA.BILL_NO, SA.STOC_STOR_CD, SA.STOC_CORN_CD
      FROM SA0100M SA, PRM P
     WHERE SA.COMP_CD = P.COMP_CD AND SA.SALE_TYPE_CD = '1' AND SA.SALE_DT <= P.BASE_DT
       AND NVL(SA.BILL_PROC_CLS_CD, '00') <> '08'
       AND NOT EXISTS (SELECT 1 FROM SA0100M E
                        WHERE E.COMP_CD = SA.COMP_CD AND E.STOR_CD = SA.STOR_CD AND E.BILL_NO = SA.BILL_NO
                          AND E.SALE_TYPE_CD <> SA.SALE_TYPE_CD AND E.SALE_DT <= P.BASE_DT)
),
U_BILL AS (
    SELECT DISTINCT BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
      FROM BO0110M BM
      JOIN BO0110D BD ON BD.COMP_CD = BM.COMP_CD AND BD.STOR_CD = BM.STOR_CD AND BD.BOND_TRAN_MNGE_NO = BM.BOND_TRAN_MNGE_NO
      CROSS JOIN PRM P
     WHERE BM.COMP_CD = P.COMP_CD AND NVL(BM.DEL_YN, 'N') = 'N'
       AND BM.PMIT_CLS_CD IN ('06','76','86')
       AND EXISTS (SELECT 1 FROM IFWM11M IM WHERE IM.COMP_CD = BM.COMP_CD AND IM.EDI_RPT_NO = BM.EDI_RPT_NO
                      AND IM.EDI_DOC_STAT_CD = 'G1' AND NVL(IM.DEL_YN, 'N') = 'N' AND IM.EDI_RPT_DT <= P.BASE_DT)
),
GOOS_CLS AS (
    SELECT S.GOOS_CD, MAX(S.REFU_CLS_CD) REFU_CLS_CD
      FROM WM0052L S, PRM P
     WHERE S.COMP_CD = P.COMP_CD AND S.RD_DT = P.BASE_DT
     GROUP BY S.GOOS_CD
),
LINES AS (
    SELECT 'G' KIND, B.BILL_NO,                                   -- 상품
           NVL(D.STOC_STOR_CD, B.STOC_STOR_CD) S_STOR, NVL(D.STOC_CORN_CD, B.STOC_CORN_CD) S_CORN,
           D.GOOS_CD, D.GOOS_QTY QTY
      FROM VALID_BILL B
      JOIN U_BILL U  ON U.COMP_CD = B.COMP_CD AND U.STOR_CD = B.STOR_CD AND U.BILL_NO = B.BILL_NO
      JOIN SA0103D D ON D.COMP_CD = B.COMP_CD AND D.STOR_CD = B.STOR_CD AND D.SALE_DT = B.SALE_DT
                    AND D.POS_NO = B.POS_NO AND D.RCPT_NO = B.RCPT_NO
     WHERE NVL(D.SALE_CNCL_YN, 'N') = 'N'
    UNION ALL
    SELECT 'W', B.BILL_NO,                                        -- GWP
           NVL(G.STOC_STOR_CD, B.STOC_STOR_CD), NVL(G.STOC_CORN_CD, B.STOC_CORN_CD),
           G.GOOS_CD, G.PMNT_QTY
      FROM VALID_BILL B
      JOIN U_BILL U  ON U.COMP_CD = B.COMP_CD AND U.STOR_CD = B.STOR_CD AND U.BILL_NO = B.BILL_NO
      JOIN SA0109D G ON G.COMP_CD = B.COMP_CD AND G.STOR_CD = B.STOR_CD AND G.SALE_DT = B.SALE_DT
                    AND G.POS_NO = B.POS_NO AND G.RCPT_NO = B.RCPT_NO
),
MAPPED AS (
    SELECT L.*,
           COALESCE(M1.SITE_GRP, M2.SITE_GRP) SITE_GRP,
           COALESCE(M1.WH_CODE, M2.WH_CODE)   WH,
           COALESCE(M1.SHED_CD, M2.SHED_CD)   SHED,
           CASE WHEN M1.WH_CODE IS NULL AND M2.WH_CODE IS NULL THEN L.S_STOR || '/' || L.S_CORN END UNMAPPED_KEY,
           CASE L.KIND WHEN 'W' THEN T.ITEM_TYPE ELSE NVL(MC.ITEM_TYPE, '?') END ITEM_TYPE
      FROM LINES L
      CROSS JOIN GWP_TYPE T
      LEFT JOIN GOOS_CLS GC ON GC.GOOS_CD = L.GOOS_CD
      LEFT JOIN MAP_CLS MC  ON MC.SRC_TYPE = 'REFU' AND MC.SRC_VAL = GC.REFU_CLS_CD
      LEFT JOIN MAP_STOR M1 ON M1.STOR_CD = L.S_STOR AND M1.CORN_CD = L.S_CORN
      LEFT JOIN MAP_STOR M2 ON M2.STOR_CD = L.S_STOR AND M2.CORN_CD = '*'
),
AGG AS (
    SELECT M.WH, M.SHED, M.UNMAPPED_KEY, M.KIND, M.ITEM_TYPE, M.GOOS_CD, M.BILL_NO, SUM(M.QTY) QTY
      FROM MAPPED M
     WHERE M.SITE_GRP IN ('MAIN','LOGI') OR M.UNMAPPED_KEY IS NOT NULL      -- T1·T2 는 미인도 기초 없음
     GROUP BY M.WH, M.SHED, M.UNMAPPED_KEY, M.KIND, M.ITEM_TYPE, M.GOOS_CD, M.BILL_NO
),
SRC_ROWS AS (
    SELECT A.WH, A.SHED, A.ITEM_TYPE, A.KIND, A.GOOS_CD, A.BILL_NO REGISTER_NO, A.QTY
      FROM AGG A
     WHERE A.QTY > 0 AND A.UNMAPPED_KEY IS NULL AND A.ITEM_TYPE <> '?'
),
NUMBERED AS (
    SELECT S.*, ROW_NUMBER() OVER (PARTITION BY S.WH, S.SHED
                                   ORDER BY S.REGISTER_NO, S.KIND, S.ITEM_TYPE, S.GOOS_CD) RN
      FROM SRC_ROWS S
),
GRP AS (                                    -- 9,999 품목씩 신고서 분할
    SELECT N.*, CEIL(N.RN / 9999) DECL_GRP, MOD(N.RN - 1, 9999) + 1 DOC_SEQ FROM NUMBERED N
),
FIN AS (                                    -- 보세구역 안 신고서 순번
    SELECT G.*, DENSE_RANK() OVER (PARTITION BY G.WH ORDER BY G.SHED, G.DECL_GRP) DECL_SEQ FROM GRP G
)
SELECT O.CSTM_CD || O.DEPT_CD || F.WH || SUBSTR(:DECL_DT, 3, 2) || 'A'
       || :SEQ_PREFIX || '3' || LPAD(F.DECL_SEQ, 6, '0')      AS DECLARATION_NO,
       F.WH                                                 AS WH_CODE,
       'DLG'                                                AS DOC_TYPE,
       :DECL_DT                                             AS DECLARATION_DATE,
       CASE WHEN F.SHED = F.WH THEN NULL ELSE F.SHED END    AS CARRYIN_LOC,
       'Y'                                                  AS DECLARATION_TYPE,
       F.DOC_SEQ,
       F.ITEM_TYPE,
       I.HS_CD                                              AS HS_CODE,
       F.GOOS_CD                                            AS ITEM_CODE,
       I.GOOS_NM                                            AS ITEM_NAME,
       NVL(I.GOOS_NORM, '-')                                AS ITEM_NORM,
       F.QTY                                                AS ITEM_QTY,
       NVL(I.SALE_DOLR_UCST, 0)                             AS ITEM_COST,
       F.QTY * NVL(I.SALE_DOLR_UCST, 0)                     AS ITEM_AMOUNT,
       NVL(I.CAPACITY, 0)                                   AS CAPACITY,
       I.BRAN_CD                                            AS BRAND_CODE,
       I.BRAN_NM                                            AS BRAND_NAME,
       I.CAPA_UNIT_CD                                       AS UNIT_CODE,
       I.GWP_GRADE                                          AS GWP_PRODUCT_GRADE,
       F.REGISTER_NO,
       NVL(I.SALE_WON_UCST, 0)                              AS ITEM_COST_KRW,
       I.QTY_UNIT_CD                                        AS QTY_UNIT_CODE
  FROM FIN F
  JOIN CSTM_OFFICE O    ON O.WH_CODE = F.WH
  LEFT JOIN GOOS_INFO I ON I.KIND = F.KIND AND I.GOOS_CD = F.GOOS_CD;

-- 건수 확인 후 COMMIT;


/* ============================ 적재 전 필수값 점검 ============================
   위 INSERT 하나에서 "INSERT ALL ~ 마지막 VALUES(...)" 를 지우고 남은 WITH ... SELECT 를 아래 < > 자리에 넣어 실행

   SELECT COUNT(*)                                   TOTAL_ROWS,
          COUNT(DISTINCT DECLARATION_NO)             DECL_CNT,
          SUM(ITEM_QTY)                              QTY,
          SUM(CASE WHEN HS_CODE IS NULL OR ITEM_NAME IS NULL OR BRAND_CODE IS NULL
                     OR BRAND_NAME IS NULL OR QTY_UNIT_CODE IS NULL THEN 1 ELSE 0 END) MISSING_REQUIRED,   -- 0 이어야 함
          SUM(CASE WHEN ITEM_COST = 0 THEN 1 ELSE 0 END)                               ZERO_PRICE          -- 상품인데 0 이면 단가 확인
     FROM ( < WITH ... SELECT ... > );
*/

/* ============================ 적재 후 확인 ============================ */
SELECT H.wh_code, H.carryin_loc, H.declaration_type,
       COUNT(DISTINCT H.declaration_no) DECL_CNT, COUNT(D.doc_seq) ITEM_CNT,
       SUM(D.item_qty) QTY, SUM(D.item_amount) AMT_USD
  FROM SR_ItemCarryIn_H H
  JOIN SR_ItemCarryIn_D D ON D.declaration_no = H.declaration_no AND D.wh_code = H.wh_code AND D.doc_type = H.doc_type
 WHERE H.declaration_date = :DECL_DT AND H.declaration_type IN ('Z','Y')
 GROUP BY H.wh_code, H.carryin_loc, H.declaration_type
 ORDER BY 1, 2, 3;

/* 리허설 되돌리기 (아직 전송 전 A1 상태만)
DELETE FROM SR_ItemCarryIn_D
 WHERE (declaration_no, wh_code, doc_type) IN
       (SELECT declaration_no, wh_code, doc_type FROM SR_ItemCarryIn_H
         WHERE declaration_date = :DECL_DT AND declaration_type IN ('Z','Y') AND status = 'A1');
DELETE FROM SR_ItemCarryIn_H
 WHERE declaration_date = :DECL_DT AND declaration_type IN ('Z','Y') AND status = 'A1';
*/
