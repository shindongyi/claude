/* ==========================================================================
   STEP 2. 상품 기초 — 통합물류 : 계산재고 (PL/SQL 적재)
   --------------------------------------------------------------------------
   계산재고 = 수불 기말재고 (11월 월수불 WM0053L, 통물 코너)
            + 교환권 (매출/통물창고 00·02, 매출/통물미래보세 00·12, 면장등록/통물미래보세 01·12)
            − H신고 재반입면장 교환권 중 판매취소 아닌 것의 판매수량
            − 미인도반입면장 교환권 중 판매취소 아닌 것의 판매수량 (통물 장치장분)

   - 조회 로직은 SELECT 버전(step2_goods_tongmul.sql)과 동일, 적재만 LOOP 로
   - (보세구역, 장치장) 바뀔 때 또는 9,999 품목 찰 때 → 채번 1번 + Header 1건, 그 아래 Detail
   - 채번 : 여기서는 안 함. 신고서마다 DECL_KEY + NO_PREFIX(세관||과||보세구역||YY||'A') 만 저장
   - 신고지점 = 점의 보세구역, 반입장치장소 = 통물 장치장 (04077090 제2 / 04077137 은산)
   - 적재 대상 : TMP_ITEMCARRYIN_H / TMP_ITEMCARRYIN_D (MIG_STEP = 2)
   - 통물 코너가 아닌 곳에 잡힌 교환권·H재반입(장치장 '미매핑:코너')은 적재 안 하고 건수만 출력

   사용법 : V_DRY_RUN = 'Y' 로 먼저 (끝나면 ROLLBACK) → 'N' 으로 실행 → 건수 확인 후 COMMIT
   ※ 빌상태·상품위치는 현재 상태 값 → 12/1 영업 시작 전 실행
   ※ FN_MA_AUTO_NO 가 내부에서 COMMIT 함 → 이 블록에서는 채번 안 함 (DRY RUN·ROLLBACK 이 정상 동작)
     신고번호는 적재 후 step5_tmp_load.sql 의 [채번] 블록에서 DECL_KEY 별로 한 번에 부여
   ========================================================================== */
DECLARE
    V_DRY_RUN     VARCHAR2(1)  := 'Y';            -- Y: 끝나고 ROLLBACK / N: 반영
    V_REGR_ID     VARCHAR2(10) := 'MIG';          -- 채번 등록자 (확인)
    V_BASE_DT     VARCHAR2(8)  := '20261130';     -- 기준일
    V_YMON        VARCHAR2(6)  := '202611';       -- 수불 년월
    V_DECL_DT     VARCHAR2(8)  := '20261201';     -- 신고일자

    V_DECL_NO     VARCHAR2(27);                  -- 신고번호 (루프에서 FN_MA_AUTO_NO)
    V_DECL_KEY    VARCHAR2(100);
    V_GRP         NUMBER := 0;
    V_BOND        VARCHAR2(20);
    V_SHED        VARCHAR2(30);
    V_SEQ         NUMBER := 0;
    V_H_CNT       NUMBER := 0;
    V_D_CNT       NUMBER := 0;
    V_QTY         NUMBER := 0;
    V_SKIP_CNT    NUMBER := 0;
    V_SKIP_QTY    NUMBER := 0;
    V_EXIST       NUMBER;
    V_CUR_KEY     VARCHAR2(200);

    CURSOR C_SRC IS
    WITH
    BOND AS (
        SELECT '05' AS STOR_CD, '본점'   AS STOR_NM, '01022006' AS BOND_GRN_CD FROM DUAL UNION ALL
        SELECT '15' AS STOR_CD, 'T1-DF4' AS STOR_NM, '04021040' AS BOND_GRN_CD FROM DUAL UNION ALL
        SELECT '17' AS STOR_CD, 'T2-DF4' AS STOR_NM, '04021041' AS BOND_GRN_CD FROM DUAL
    ),
    TONG AS (
        SELECT '961' AS CORN_CD, '04077090' AS SHED_CD FROM DUAL UNION ALL      -- 제2 통합물류센터
        SELECT '965' AS CORN_CD, '04077137' AS SHED_CD FROM DUAL                -- 은산 통합물류센터
    ),
    -- H신고 재반입면장 교환권 빌
    H_BILL AS (
        SELECT BD.COMP_CD
             , BD.STOR_CD
             , BD.BILL_NO
          FROM BO0110M BM
             , BO0110D BD
             , IFWM11M IM
             , MA0151D MD
         WHERE BM.COMP_CD           = BD.COMP_CD
           AND BM.STOR_CD           = BD.STOR_CD
           AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
           AND BM.COMP_CD           = IM.COMP_CD
           AND BM.EDI_RPT_NO        = IM.EDI_RPT_NO
           AND IM.EDI_DOC_STAT_CD   = 'G1'
           AND BM.COMP_CD           = MD.COMP_CD
           AND BM.PMIT_CLS_CD       = MD.COMM_CTG_DTL_CD
           AND MD.WRK_MDUL_CD       = 'WM'
           AND MD.COMM_CTG_CD       = 'WM038'
           AND MD.COMM_CTG_DTL_CD  IN ('05','75','85','10','80','90','20','91')
           AND MD.COMM_PROP_CONT_1  = 'H'
           AND NVL(BM.DEL_YN, 'N')  = 'N'
           AND IM.EDI_RPT_DT       <= V_BASE_DT
        UNION
        SELECT MK.COMP_CD
             , MK.STOR_CD
             , MK.BILL_NO
          FROM MK5010D MK
             , IFWM12M IM
         WHERE MK.COMP_CD          = IM.COMP_CD
           AND MK.EDI_RPT_NO       = IM.EDI_RPT_NO
           AND IM.EDI_DOC_CLS_CD   = '5KP'
           AND IM.CSTM_RPT_CLS_CD IN ('B', 'R')                              /* B:반품(인도후), R:미인도물품재반입 */
           AND IM.EDI_DOC_STAT_CD  = 'F1'                                    /* 결과통보 */
           AND IM.EDI_RPT_DT      <= V_BASE_DT
    ),
    -- 미인도 (−)
    U_BILL AS (
        SELECT BD.COMP_CD
             , BD.STOR_CD
             , BD.BILL_NO
             , MAX(IM.ARRV_BOND_RGN_CD) AS ARRV_BOND
             , MAX(IM.ARRV_SHED_CD)     AS ARRV_SHED
          FROM BO0110M BM
             , BO0110D BD
             , IFWM11M IM
         WHERE BM.COMP_CD           = BD.COMP_CD
           AND BM.STOR_CD           = BD.STOR_CD
           AND BM.BOND_TRAN_MNGE_NO = BD.BOND_TRAN_MNGE_NO
           AND BM.COMP_CD           = IM.COMP_CD
           AND BM.EDI_RPT_NO        = IM.EDI_RPT_NO
           AND IM.EDI_DOC_STAT_CD   = 'G1'
           AND BM.PMIT_CLS_CD      IN ('06', '76', '86')
           AND NVL(BM.DEL_YN, 'N')  = 'N'
           AND BM.COMP_CD           = '01'
           AND IM.EDI_RPT_DT       <= V_BASE_DT
         GROUP BY BD.COMP_CD, BD.STOR_CD, BD.BILL_NO
    ),
    -- ① 필요한 빌만 : 교환권 상태 빌 + H재반입 빌 + 미인도 빌  (튜닝: 매출 전체 이력 대신)
    SALE_KEY AS (
        SELECT /*+ FULL(A) PARALLEL(A 4) */                          -- 빌상태·상품위치 인덱스 없음 → FULL + 병렬 (DBA 허용 시)
               A.COMP_CD, A.STOR_CD, A.SALE_DT, A.POS_NO, A.RCPT_NO, A.BILL_NO
             , A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD, A.STOC_STOR_CD, A.STOC_CORN_CD, A.SALE_TYPE_CD
          FROM SA0100M A
         WHERE A.COMP_CD      = '01'
           AND A.SALE_TYPE_CD = '1'
           AND A.SALE_DT     <= V_BASE_DT
        -- AND A.SALE_DT     >= :MIN_DT                              -- 남은 교환권 최소 매출일 확인 후 하한 (선택)
           AND (A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
        UNION
        SELECT A.COMP_CD, A.STOR_CD, A.SALE_DT, A.POS_NO, A.RCPT_NO, A.BILL_NO
             , A.BILL_PROC_CLS_CD, A.GOOS_LOC_CLS_CD, A.STOC_STOR_CD, A.STOC_CORN_CD, A.SALE_TYPE_CD
          FROM SA0100M A
          JOIN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL
                UNION
                SELECT COMP_CD, STOR_CD, BILL_NO FROM U_BILL) K
            ON K.COMP_CD = A.COMP_CD
           AND K.STOR_CD = A.STOR_CD
           AND K.BILL_NO = A.BILL_NO
         WHERE A.SALE_TYPE_CD = '1'
           AND A.SALE_DT     <= V_BASE_DT
    ),
    -- ② 판매취소 아닌 것만 + 라인
    SALE AS (
        SELECT A.COMP_CD
             , A.STOR_CD
             , A.BILL_NO
             , A.BILL_PROC_CLS_CD
             , A.GOOS_LOC_CLS_CD
             , NVL(C.STOC_STOR_CD, A.STOC_STOR_CD) AS STOC_STOR_CD
             , NVL(C.STOC_CORN_CD, A.STOC_CORN_CD) AS STOC_CORN_CD
             , C.GOOS_CD
             , C.AGIG_CD
             , C.GOOS_QTY                          AS QTY
          FROM SALE_KEY A
             , SA0103D C
         WHERE A.COMP_CD = C.COMP_CD
           AND A.STOR_CD = C.STOR_CD
           AND A.SALE_DT = C.SALE_DT
           AND A.POS_NO  = C.POS_NO
           AND A.RCPT_NO = C.RCPT_NO
           AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
           AND NOT EXISTS (SELECT 1
                             FROM SA0100M E
                            WHERE E.COMP_CD       = A.COMP_CD
                              AND E.STOR_CD       = A.STOR_CD
                              AND E.BILL_NO       = A.BILL_NO
                              AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                              AND E.SALE_DT      <= V_BASE_DT)
    ),
    UDLV AS (
        SELECT NVL(U.ARRV_BOND, B.BOND_GRN_CD)                       AS WH_CODE
             , NVL(U.ARRV_SHED, NVL(U.ARRV_BOND, B.BOND_GRN_CD))     AS SHED_CD
             , X.GOOS_CD
             , X.AGIG_CD
             , X.QTY
          FROM SALE X
          JOIN U_BILL U
            ON U.COMP_CD = X.COMP_CD
           AND U.STOR_CD = X.STOR_CD
           AND U.BILL_NO = X.BILL_NO
          LEFT JOIN BOND B
            ON B.STOR_CD = X.STOR_CD
    ),
    -- ① 구성요소 (보세구역·장치장까지 붙여서)
    COMP AS (
        -- 수불 기말재고 (통물 코너만)
        SELECT 'SUBUL' AS SRC, B.BOND_GRN_CD, T.SHED_CD, S.GOOS_CD, S.AGIG_CD, S.QTY
          FROM WM0053L S
          JOIN BOND B
            ON B.STOR_CD = S.STOR_CD
          JOIN TONG T
            ON T.CORN_CD = S.CORN_CD
         WHERE S.COMP_CD = '01'
           AND S.YMON    = V_YMON
        UNION ALL
        -- 교환권 (+)
        SELECT 'EXCH', B.BOND_GRN_CD, NVL(T.SHED_CD, '미매핑:' || X.STOC_CORN_CD), X.GOOS_CD, X.AGIG_CD, X.QTY
          FROM SALE X
          JOIN BOND B
            ON B.STOR_CD = X.STOC_STOR_CD
          LEFT JOIN TONG T
            ON T.CORN_CD = X.STOC_CORN_CD
         WHERE (X.BILL_PROC_CLS_CD, X.GOOS_LOC_CLS_CD) IN (('00','02'), ('00','12'), ('01','12'))
        UNION ALL
        -- H신고 재반입 (−)
        SELECT 'HREENT', B.BOND_GRN_CD, NVL(T.SHED_CD, '미매핑:' || X.STOC_CORN_CD), X.GOOS_CD, X.AGIG_CD, -X.QTY
          FROM SALE X
          JOIN BOND B
            ON B.STOR_CD = X.STOC_STOR_CD
          LEFT JOIN TONG T
            ON T.CORN_CD = X.STOC_CORN_CD
         WHERE (X.COMP_CD, X.STOR_CD, X.BILL_NO) IN (SELECT COMP_CD, STOR_CD, BILL_NO FROM H_BILL)
        UNION ALL
        -- 미인도 (−) : 통물 장치장분만
        SELECT 'UDLV', U.WH_CODE, U.SHED_CD, U.GOOS_CD, U.AGIG_CD, -U.QTY
          FROM UDLV U
         WHERE U.SHED_CD IN ('04077090', '04077137')
           AND U.WH_CODE IN (SELECT BOND_GRN_CD FROM BOND)
    ),
    -- ② 환급코드 먼저 반영
    CODED AS (
        SELECT C.SRC
             , C.BOND_GRN_CD
             , C.SHED_CD
             , C.GOOS_CD
             , C.QTY
             , CASE WHEN SUBSTR(C.AGIG_CD, 6, 1) = '1' THEN 'W'
                    WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                    ELSE 'D' END                                         AS CSTM_GOODS_TYPE_CD
             , G.GOOS_CD                                                 AS MST_GOOS_CD
             , G.GOOS_TYPE_CD
          FROM COMP C
          LEFT JOIN MA0040C G
            ON G.COMP_CD = '01'
           AND G.GOOS_CD = C.GOOS_CD
    ),
    CODED2 AS (
        SELECT T.*
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                    WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                         THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
               END                                                       AS NEW_CSTM_GOOS_CD
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                    WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                    WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                    ELSE 'NO_TYPE' END                                   AS MATCH_BY
          FROM CODED T
          LEFT JOIN MA9301C R
            ON R.COMP_CD            = '01'
           AND R.USE_YN             = 'Y'
           AND R.GOOS_CD            = T.GOOS_CD
           AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
    ),
    -- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드
    AGG AS (
        SELECT C.BOND_GRN_CD
             , C.SHED_CD
             , C.CSTM_GOODS_TYPE_CD
             , C.NEW_CSTM_GOOS_CD
             , C.GOOS_CD
             , MAX(C.MATCH_BY)                                           AS MATCH_BY
             , SUM(C.QTY)                                                AS QTY
             , SUM(CASE WHEN C.SRC = 'SUBUL'  THEN C.QTY ELSE 0 END)     AS Q_SUBUL
             , SUM(CASE WHEN C.SRC = 'EXCH'   THEN C.QTY ELSE 0 END)     AS Q_EXCH
             , SUM(CASE WHEN C.SRC = 'HREENT' THEN C.QTY ELSE 0 END)     AS Q_HREENT
             , SUM(CASE WHEN C.SRC = 'UDLV'   THEN C.QTY ELSE 0 END)     AS Q_UDLV
          FROM CODED2 C
         GROUP BY C.BOND_GRN_CD, C.SHED_CD, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD
        HAVING SUM(C.QTY) > 0
    )
    SELECT A.*
         , D.STOR_NM
         -- 채번 접두 : 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'A'
         , N.COMM_PROP_CONT_1 || N.COMM_PROP_CONT_2 || A.BOND_GRN_CD
           || TO_CHAR(SYSDATE, 'YY') || 'A'                             AS NO_PREFIX
         , M.HS_CD
         , B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM             AS ITEM_NAME
         , M.STDZ_CONT
         , M.GOOS_PUR_FC_UCST
         , M.BRAN_CD
         , B.BRAN_NM
         , M.UNIT
         , M.REF_NO
         , V.GOOS_CAPA
      FROM AGG A
      JOIN BOND D
        ON D.BOND_GRN_CD = A.BOND_GRN_CD
      LEFT JOIN MA0151D N
        ON N.COMP_CD         = '01'
       AND N.WRK_MDUL_CD     = 'MA'
       AND N.COMM_CTG_CD     = 'MA041'
       AND N.COMM_CTG_DTL_CD = A.BOND_GRN_CD
      LEFT JOIN MA0040C M
        ON M.COMP_CD = '01'
       AND M.GOOS_CD = A.GOOS_CD
      LEFT JOIN MA0030C B
        ON B.COMP_CD = M.COMP_CD
       AND B.BRAN_CD = M.BRAN_CD
      LEFT JOIN MA3118I V
        ON V.COMP_CD = '01'
       AND V.GOOS_CD = A.GOOS_CD
     ORDER BY A.BOND_GRN_CD, A.SHED_CD, A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD;

BEGIN
    DBMS_OUTPUT.ENABLE(NULL);

    SELECT COUNT(*) INTO V_EXIST FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 2;
    IF V_EXIST > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'STEP 2 가 이미 TMP 에 있음 → DELETE (H/D, MIG_STEP = 2) 후 실행');
    END IF;


    FOR R IN C_SRC LOOP
        V_CUR_KEY := R.BOND_GRN_CD || '/' || R.SHED_CD || '/' || R.GOOS_CD;

        -- 통물 코너가 아닌 곳에 잡힌 교환권·H재반입 → 적재 안 함
        IF R.SHED_CD LIKE '미매핑%' THEN
            V_SKIP_CNT := V_SKIP_CNT + 1;
            V_SKIP_QTY := V_SKIP_QTY + R.QTY;
            DBMS_OUTPUT.PUT_LINE('  [SKIP] ' || V_CUR_KEY || ' QTY=' || R.QTY);
            CONTINUE;
        END IF;

        -- 새 신고서 : 보세구역·장치장이 바뀌거나 9,999 품목 찼을 때
        IF V_BOND IS NULL OR R.BOND_GRN_CD <> V_BOND OR R.SHED_CD <> V_SHED OR V_SEQ >= 9999 THEN

            IF R.NO_PREFIX IS NULL OR LENGTH(R.NO_PREFIX) < 16 THEN
                RAISE_APPLICATION_ERROR(-20002, '채번 접두 이상 (MA041 세관·과 코드 확인) : ' || R.BOND_GRN_CD);
            END IF;

            V_GRP      := V_GRP + 1;
            V_DECL_KEY := 'S2|' || R.BOND_GRN_CD || '|' || R.SHED_CD || '|' || LPAD(V_GRP, 4, '0');
            V_DECL_NO  := FN_MA_AUTO_NO('01', 'BO15', R.NO_PREFIX, V_REGR_ID);   -- ★ 채번 (Header 1건당 1번)

            INSERT INTO TMP_ITEMCARRYIN_H
            (
                  MIG_STEP, BASE_DT, LOAD_DTTM
                , DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, AMEND_TYPE, CARRYIN_LOC
                , REFERENCE_NO, DECLARATION_TYPE, STATUS, C_DATETIME, INTERNATIONAL_MAIL_YN
                , REF_STOR_NM, REF_SITE, DECL_KEY, NO_PREFIX
            )
            VALUES
            (
                  2, V_BASE_DT, SYSDATE
                , V_DECL_NO              --  1 신고번호
                , R.BOND_GRN_CD          --  2 신고지점
                , 'DLG'                  --  3 문서구분
                , V_DECL_DT              --  4 신고일자
                , NULL                   --  5 정정구분
                , R.SHED_CD              --  6 반입장치장소 = 통물 장치장
                , NULL                   --  7 근거번호
                , 'Z'                    --  8 신고구분 기초재고반입
                , 'A1'                   --  9 상태
                , SYSDATE                -- 10 생성일시
                , NULL                   -- 11 국제우편여부
                , R.STOR_NM, 'LOGI', V_DECL_KEY, R.NO_PREFIX
            );

            V_BOND  := R.BOND_GRN_CD;
            V_SHED  := R.SHED_CD;
            V_SEQ   := 0;
            V_H_CNT := V_H_CNT + 1;
        END IF;

        V_SEQ := V_SEQ + 1;

        INSERT INTO TMP_ITEMCARRYIN_D
        (
              MIG_STEP, BASE_DT, LOAD_DTTM
            , DECLARATION_NO, WH_CODE, DOC_TYPE, DOC_SEQ, RAMEND_TYPE, ITEM_TYPE, HS_CODE, ITEM_CODE
            , ITEM_NAME, ITEM_NORM, ITEM_QTY, ITEM_COST, ITEM_AMOUNT, CAPACITY, BRAND_CODE, BRAND_NAME
            , UNIT_CODE, GWP_PRODUCT_GRADE, REGISTER_NO, ITEM_COST_KRW, QTY_UNIT_CODE
            , REF_STOR_NM, REF_SHED_CD, REF_SITE, REF_GOOS_CD, REF_GOOS_GWP, REF_MATCH_BY, REF_REF_NO
            , REF_Q_SUBUL, REF_Q_EXCH, REF_Q_HREENT, REF_Q_UDLV, DECL_KEY
        )
        VALUES
        (
              2, V_BASE_DT, SYSDATE
            , V_DECL_NO                                   --  1 신고번호 (Header 와 동일)
            , R.BOND_GRN_CD                               --  2 신고지점
            , 'DLG'                                       --  3 문서구분
            , V_SEQ                                       --  4 품목일련번호
            , NULL                                        --  5 란정정구분
            , R.CSTM_GOODS_TYPE_CD                        --  6 물품구분 T/D/W
            , R.HS_CD                                     --  7 HS코드 (상품마스터)
            , R.NEW_CSTM_GOOS_CD                          --  8 상품코드 (세관신고 상품코드)
            , R.ITEM_NAME                                 --  9 품명
            , R.STDZ_CONT                                 -- 10 규격
            , R.QTY                                       -- 11 수량 (계산재고)
            , R.GOOS_PUR_FC_UCST                          -- 12 단가(미화)
            , R.QTY * R.GOOS_PUR_FC_UCST                  -- 13 금액
            , R.GOOS_CAPA                                 -- 14 용량
            , R.BRAN_CD                                   -- 15 브랜드코드
            , R.BRAN_NM                                   -- 16 브랜드명
            , R.UNIT                                      -- 17 용량단위
            , NULL                                        -- 18 GWP물품등급
            , R.REF_NO                                    -- 19 참조번호
            , NULL                                        -- 20 단가(원화)
            , NULL                                        -- 21 수량단위
            , R.STOR_NM, R.SHED_CD, 'LOGI', R.GOOS_CD, '상품', R.MATCH_BY, R.REF_NO
            , R.Q_SUBUL, R.Q_EXCH, R.Q_HREENT, R.Q_UDLV, V_DECL_KEY
        );

        V_D_CNT := V_D_CNT + 1;
        V_QTY   := V_QTY + R.QTY;
    END LOOP;

    -- Header 참고 합계
    UPDATE TMP_ITEMCARRYIN_H H
       SET (REF_ITEM_CNT, REF_QTY, REF_Q_SUBUL, REF_Q_EXCH, REF_Q_HREENT, REF_Q_UDLV) =
           (SELECT COUNT(*), SUM(D.ITEM_QTY), SUM(D.REF_Q_SUBUL), SUM(D.REF_Q_EXCH), SUM(D.REF_Q_HREENT), SUM(D.REF_Q_UDLV)
              FROM TMP_ITEMCARRYIN_D D
             WHERE D.MIG_STEP       = 2
               AND D.DECL_KEY       = H.DECL_KEY)
     WHERE H.MIG_STEP = 2;

    DBMS_OUTPUT.PUT_LINE('STEP 2 SUCCESS');
    DBMS_OUTPUT.PUT_LINE('Header(신고서)    = ' || V_H_CNT);
    DBMS_OUTPUT.PUT_LINE('Detail(품목)      = ' || V_D_CNT);
    DBMS_OUTPUT.PUT_LINE('수량 합계         = ' || V_QTY);
    DBMS_OUTPUT.PUT_LINE('미매핑 SKIP 건/량 = ' || V_SKIP_CNT || ' / ' || V_SKIP_QTY);

    IF V_DRY_RUN = 'Y' THEN
        ROLLBACK;                                   -- 채번 함수가 COMMIT 하므로 마지막 신고서 이후분만 되돌려짐
        DBMS_OUTPUT.PUT_LINE('DRY RUN 은 채번 때문에 완전한 ROLLBACK 이 안 됨 → 개발기에서 테스트');
    ELSE
        DBMS_OUTPUT.PUT_LINE('반영됨 → 건수 확인 후 COMMIT');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FAIL → 마지막 채번 이후분만 ROLLBACK (그 전 신고서는 이미 COMMIT 됨)');
        DBMS_OUTPUT.PUT_LINE('→ DELETE (MIG_STEP = 2) 후 재실행');
        DBMS_OUTPUT.PUT_LINE('실패 위치 : ' || V_CUR_KEY);
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        RAISE;
END;
/

/* 다시 돌릴 때 (TMP 만 지움, 이미 나간 번호는 돌아오지 않음)
DELETE FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP = 2;
DELETE FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 2;
COMMIT;
*/
