/* ==========================================================================
   STEP 4. 상품 및 GWP 미인도 기초 — 신고구분 Y (PL/SQL 적재)
   --------------------------------------------------------------------------
   대상 : 미인도반입면장(06/76/86, G1 확정) 교환권 중 판매취소 아닌 것의 판매수량 (상품 + GWP)
          본점 자기 장치장 / 통물 장치장만 (T1·T2 자기 장치장은 없음)
   위치 : 반입면장 EDI 도착보세구역·도착장치장 (없으면 판매점 보세구역)
   참조번호(REGISTER_NO) = 교환권번호(BILL_NO)

   - 조회 로직은 SELECT 버전(step4_undelivered.sql)과 동일, 적재만 LOOP 로
   - (보세구역, 장치장) 바뀔 때 또는 9,999 품목 찰 때 → 새 신고서 (DECL_KEY)
   - 채번은 여기서 안 함 (FN_MA_AUTO_NO 가 내부 COMMIT) → step5_tmp_load.sql [채번] 블록에서 부여
   - 적재 대상 : TMP_ITEMCARRYIN_H / TMP_ITEMCARRYIN_D (MIG_STEP = 4)

   사용법 : V_DRY_RUN = 'Y' (끝나면 ROLLBACK) → 'N' 실행 → 건수 확인 후 COMMIT → [채번] 블록
   ========================================================================== */
DECLARE
    V_DRY_RUN     VARCHAR2(1)  := 'Y';            -- Y: 끝나고 ROLLBACK / N: 반영
    V_REGR_ID     VARCHAR2(10) := 'MIG';          -- 채번 등록자 (확인)
    V_DECL_NO     VARCHAR2(27);                  -- 신고번호 (루프에서 FN_MA_AUTO_NO)
    V_BASE_DT     VARCHAR2(8)  := '20261130';
    V_DECL_DT     VARCHAR2(8)  := '20261201';

    V_DECL_KEY    VARCHAR2(100);
    V_GRP         NUMBER := 0;
    V_BOND        VARCHAR2(20);
    V_SHED        VARCHAR2(30);
    V_SEQ         NUMBER := 0;
    V_H_CNT       NUMBER := 0;
    V_D_CNT       NUMBER := 0;
    V_QTY         NUMBER := 0;
    V_EXIST       NUMBER;
    V_CUR_KEY     VARCHAR2(200);

    CURSOR C_SRC IS
    WITH
    BOND AS (
        SELECT '05' AS STOR_CD, '본점'   AS STOR_NM, '01022006' AS BOND_GRN_CD FROM DUAL UNION ALL
        SELECT '15' AS STOR_CD, 'T1-DF4' AS STOR_NM, '04021040' AS BOND_GRN_CD FROM DUAL UNION ALL
        SELECT '17' AS STOR_CD, 'T2-DF4' AS STOR_NM, '04021041' AS BOND_GRN_CD FROM DUAL
    ),
    -- ① 미인도반입면장 교환권 빌
    U_BILL AS (
        SELECT BD.COMP_CD
             , BD.STOR_CD
             , BD.BILL_NO
             , MAX(IM.ARRV_BOND_RGN_CD)             AS ARRV_BOND      -- 도착보세구역
             , MAX(IM.ARRV_SHED_CD)                 AS ARRV_SHED      -- 도착장치장
             , COUNT(DISTINCT BM.BOND_TRAN_MNGE_NO) AS PMIT_CNT       -- 2 이상이면 재반입 여러 번
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
    -- ② 판매취소 아닌 빌
    VALID_BILL AS (
        SELECT A.COMP_CD, A.STOR_CD, A.SALE_DT, A.POS_NO, A.RCPT_NO, A.BILL_NO, A.BILL_PROC_CLS_CD
             , U.ARRV_BOND, U.ARRV_SHED, U.PMIT_CNT
          FROM SA0100M A
             , U_BILL U
         WHERE A.COMP_CD      = U.COMP_CD
           AND A.STOR_CD      = U.STOR_CD
           AND A.BILL_NO      = U.BILL_NO
           AND A.SALE_TYPE_CD = '1'
           AND A.SALE_DT     <= V_BASE_DT
           AND NOT EXISTS (SELECT 1
                             FROM SA0100M E
                            WHERE E.COMP_CD       = A.COMP_CD
                              AND E.STOR_CD       = A.STOR_CD
                              AND E.BILL_NO       = A.BILL_NO
                              AND E.SALE_TYPE_CD != A.SALE_TYPE_CD
                              AND E.SALE_DT      <= V_BASE_DT)
    ),
    -- ③ 판매수량 : 상품 + GWP
    LINES AS (
        SELECT 'G' AS KIND, V.*, C.GOOS_CD, C.AGIG_CD, C.GOOS_QTY AS QTY
          FROM VALID_BILL V
             , SA0103D C
         WHERE C.COMP_CD = V.COMP_CD
           AND C.STOR_CD = V.STOR_CD
           AND C.SALE_DT = V.SALE_DT
           AND C.POS_NO  = V.POS_NO
           AND C.RCPT_NO = V.RCPT_NO
           AND NVL(C.SALE_CNCL_YN, 'N') = 'N'
        UNION ALL
        SELECT 'W' AS KIND, V.*, G.GOOS_CD, NULL, G.PMNT_QTY
          FROM VALID_BILL V
             , SA0109D G
         WHERE G.COMP_CD = V.COMP_CD
           AND G.STOR_CD = V.STOR_CD
           AND G.SALE_DT = V.SALE_DT
           AND G.POS_NO  = V.POS_NO
           AND G.RCPT_NO = V.RCPT_NO
    ),
    -- ④ 위치 + 환급코드
    TAGGED AS (
        SELECT L.KIND, L.BILL_NO, L.GOOS_CD, L.QTY, L.BILL_PROC_CLS_CD, L.PMIT_CNT
             , NVL(L.ARRV_BOND, B.BOND_GRN_CD)                         AS WH_CODE
             , NVL(L.ARRV_SHED, NVL(L.ARRV_BOND, B.BOND_GRN_CD))       AS SHED_CD
             , CASE WHEN L.KIND = 'W'                  THEN 'D'
                    WHEN SUBSTR(L.AGIG_CD, 6, 1) = '1' THEN 'W'
                    WHEN G.GOOS_TYPE_CD = '1'          THEN 'T'
                    ELSE 'D' END                                        AS CSTM_GOODS_TYPE_CD
             , G.GOOS_CD                                                AS MST_GOOS_CD
             , G.GOOS_TYPE_CD
          FROM LINES L
          LEFT JOIN BOND B
            ON B.STOR_CD = L.STOR_CD
          LEFT JOIN MA0040C G
            ON L.KIND    = 'G'
           AND G.COMP_CD = '01'
           AND G.GOOS_CD = L.GOOS_CD
    ),
    CODED AS (
        SELECT T.*
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                    WHEN T.KIND = 'W' THEN T.GOOS_CD
                    WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL
                         THEN DECODE(T.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(T.GOOS_CD, 2)
               END                                                      AS NEW_CSTM_GOOS_CD
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                    WHEN T.KIND = 'W' THEN 'GWP_CD'
                    WHEN T.CSTM_GOODS_TYPE_CD = 'W' AND T.MST_GOOS_CD IS NOT NULL THEN 'W_RULE'
                    WHEN T.MST_GOOS_CD IS NULL THEN 'NO_MASTER'
                    ELSE 'NO_TYPE' END                                  AS MATCH_BY
          FROM TAGGED T
          LEFT JOIN MA9301C R
            ON R.COMP_CD            = '01'
           AND R.USE_YN             = 'Y'
           AND R.GOOS_CD            = T.GOOS_CD
           AND R.CSTM_GOODS_TYPE_CD = T.CSTM_GOODS_TYPE_CD
         WHERE T.WH_CODE = '01022006'                                    -- 본점
            OR T.SHED_CD IN ('04077090', '04077137')                     -- 통물
    ),
    -- ⑤ 집계 : 보세구역 × 장치장 × 교환권 × 환급구분 × 세관상품코드
    AGG AS (
        SELECT C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD
             , MAX(C.MATCH_BY)         AS MATCH_BY
             , MAX(C.BILL_PROC_CLS_CD) AS BILL_PROC_CLS_CD
             , MAX(C.PMIT_CNT)         AS PMIT_CNT
             , SUM(C.QTY)              AS QTY
          FROM CODED C
         GROUP BY C.WH_CODE, C.SHED_CD, C.BILL_NO, C.KIND, C.CSTM_GOODS_TYPE_CD, C.NEW_CSTM_GOOS_CD, C.GOOS_CD
        HAVING SUM(C.QTY) > 0
    )
    SELECT A.*
         , D.STOR_NM
         -- 채번 접두 : 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'A'
         , N.COMM_PROP_CONT_1 || N.COMM_PROP_CONT_2 || A.WH_CODE
           || TO_CHAR(SYSDATE, 'YY') || 'A'                                       AS NO_PREFIX
         , CASE A.KIND WHEN 'W' THEN WP.HS_CD ELSE M.HS_CD END                    AS HS_CD
         , CASE A.KIND WHEN 'W' THEN WP.CSTM_GOOS_NM
                       ELSE B.BRAN_NM || ' ' || M.REF_NO || ' ' || M.GOOS_NM END  AS ITEM_NAME
         , CASE A.KIND WHEN 'W' THEN WP.STDZ_CONT ELSE M.STDZ_CONT END            AS STDZ_CONT
         , CASE A.KIND WHEN 'W' THEN 0 ELSE M.GOOS_PUR_FC_UCST END                AS ITEM_COST
         , CASE A.KIND WHEN 'W' THEN WP.GOOS_CAPA ELSE V.GOOS_CAPA END            AS CAPACITY
         , CASE A.KIND WHEN 'W' THEN WM.BRAN_CD ELSE M.BRAN_CD END                AS BRAN_CD
         , CASE A.KIND WHEN 'W' THEN WB.BRAN_NM ELSE B.BRAN_NM END                AS BRAN_NM
         , CASE A.KIND WHEN 'W' THEN WP.SIZE_UNIT_CD ELSE M.UNIT END              AS UNIT_CODE
         , CASE A.KIND WHEN 'W' THEN WI.MNGE_LVL_CD END                           AS GWP_GRADE
         , CASE A.KIND WHEN 'W' THEN WP.REF_NO ELSE M.REF_NO END                  AS REF_NO
      FROM AGG A
      LEFT JOIN BOND D
        ON D.BOND_GRN_CD = A.WH_CODE
      LEFT JOIN MA0151D N
        ON N.COMP_CD         = '01'
       AND N.WRK_MDUL_CD     = 'MA'
       AND N.COMM_CTG_CD     = 'MA041'
       AND N.COMM_CTG_DTL_CD = A.WH_CODE
      LEFT JOIN MA0040C M
        ON A.KIND    = 'G'
       AND M.COMP_CD = '01'
       AND M.GOOS_CD = A.GOOS_CD
      LEFT JOIN MA0030C B
        ON B.COMP_CD = M.COMP_CD
       AND B.BRAN_CD = M.BRAN_CD
      LEFT JOIN MA3118I V
        ON A.KIND    = 'G'
       AND V.COMP_CD = '01'
       AND V.GOOS_CD = A.GOOS_CD
      LEFT JOIN WM0310C WM
        ON A.KIND     = 'W'
       AND WM.COMP_CD = '01'
       AND WM.GOOS_CD = A.GOOS_CD
      LEFT JOIN MA0030C WB
        ON WB.COMP_CD = WM.COMP_CD
       AND WB.BRAN_CD = WM.BRAN_CD
      LEFT JOIN WM0314C WP
        ON A.KIND     = 'W'
       AND WP.COMP_CD = '01'
       AND WP.GOOS_CD = A.GOOS_CD
      LEFT JOIN WM0310I WI
        ON A.KIND     = 'W'
       AND WI.COMP_CD = '01'
       AND WI.GOOS_CD = A.GOOS_CD
     ORDER BY A.WH_CODE, A.SHED_CD, A.BILL_NO, A.KIND, A.NEW_CSTM_GOOS_CD, A.GOOS_CD;

BEGIN
    DBMS_OUTPUT.ENABLE(NULL);

    SELECT COUNT(*) INTO V_EXIST FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 4;
    IF V_EXIST > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'STEP 4 가 이미 TMP 에 있음 → DELETE (H/D, MIG_STEP = 4) 후 실행');
    END IF;


    FOR R IN C_SRC LOOP
        V_CUR_KEY := R.WH_CODE || '/' || R.SHED_CD || '/' || R.BILL_NO || '/' || R.GOOS_CD;

        -- 새 신고서 : 보세구역·장치장이 바뀌거나 9,999 품목 찼을 때
        IF V_BOND IS NULL OR R.WH_CODE <> V_BOND OR R.SHED_CD <> V_SHED OR V_SEQ >= 9999 THEN

            IF R.NO_PREFIX IS NULL OR LENGTH(R.NO_PREFIX) < 16 THEN
                RAISE_APPLICATION_ERROR(-20002, '채번 접두 이상 (MA041 세관·과 코드 확인) : ' || R.WH_CODE);
            END IF;

            V_GRP      := V_GRP + 1;
            V_DECL_KEY := 'S4|' || R.WH_CODE || '|' || R.SHED_CD || '|' || LPAD(V_GRP, 4, '0');
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
                  4, V_BASE_DT, SYSDATE
                , V_DECL_NO                                                         --  1 신고번호 (채번)
                , R.WH_CODE                                                    --  2 신고지점
                , 'DLG'                                                        --  3 문서구분
                , V_DECL_DT                                                    --  4 신고일자
                , NULL                                                         --  5 정정구분
                , CASE WHEN R.SHED_CD = R.WH_CODE THEN NULL ELSE R.SHED_CD END --  6 반입장치장소 (통물이면 값)
                , NULL                                                         --  7 근거번호
                , 'Y'                                                          --  8 신고구분 미인도물품재고반입
                , 'A1'                                                         --  9 상태
                , SYSDATE                                                      -- 10 생성일시
                , NULL                                                         -- 11 국제우편여부
                , R.STOR_NM
                , CASE WHEN R.SHED_CD IN ('04077090', '04077137') THEN 'LOGI' ELSE 'MAIN' END
                , V_DECL_KEY, R.NO_PREFIX
            );

            V_BOND  := R.WH_CODE;
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
            , REF_STOR_NM, REF_SHED_CD, REF_GOOS_CD, REF_GOOS_GWP, REF_MATCH_BY, REF_REF_NO
            , REF_BILL_STAT, REF_PMIT_CNT, DECL_KEY
        )
        VALUES
        (
              4, V_BASE_DT, SYSDATE
            , V_DECL_NO                                        --  1 신고번호 (채번)
            , R.WH_CODE                                   --  2 신고지점
            , 'DLG'                                       --  3 문서구분
            , V_SEQ                                       --  4 품목일련번호
            , NULL                                        --  5 란정정구분
            , R.CSTM_GOODS_TYPE_CD                        --  6 물품구분 T/D/W
            , R.HS_CD                                     --  7 HS코드
            , R.NEW_CSTM_GOOS_CD                          --  8 세관신고 상품코드
            , R.ITEM_NAME                                 --  9 품명
            , R.STDZ_CONT                                 -- 10 규격
            , R.QTY                                       -- 11 수량
            , R.ITEM_COST                                 -- 12 단가(미화) GWP 0
            , R.QTY * R.ITEM_COST                         -- 13 금액
            , R.CAPACITY                                  -- 14 용량
            , R.BRAN_CD                                   -- 15 브랜드코드
            , R.BRAN_NM                                   -- 16 브랜드명
            , R.UNIT_CODE                                 -- 17 용량단위
            , R.GWP_GRADE                                 -- 18 GWP물품등급
            , R.BILL_NO                                   -- 19 참조번호 = 교환권번호
            , CASE R.KIND WHEN 'W' THEN 0 END             -- 20 단가(원화)
            , NULL                                        -- 21 수량단위
            , R.STOR_NM, R.SHED_CD, R.GOOS_CD, DECODE(R.KIND, 'G', '상품', 'GWP'), R.MATCH_BY, R.REF_NO
            , R.BILL_PROC_CLS_CD, R.PMIT_CNT, V_DECL_KEY
        );

        V_D_CNT := V_D_CNT + 1;
        V_QTY   := V_QTY + R.QTY;
    END LOOP;

    -- Header 참고 합계
    UPDATE TMP_ITEMCARRYIN_H H
       SET (REF_ITEM_CNT, REF_BILL_CNT, REF_QTY, REF_QTY_GOODS, REF_QTY_GWP) =
           (SELECT COUNT(*), COUNT(DISTINCT D.REGISTER_NO), SUM(D.ITEM_QTY)
                 , SUM(CASE D.REF_GOOS_GWP WHEN '상품' THEN D.ITEM_QTY ELSE 0 END)
                 , SUM(CASE D.REF_GOOS_GWP WHEN 'GWP'  THEN D.ITEM_QTY ELSE 0 END)
              FROM TMP_ITEMCARRYIN_D D
             WHERE D.DECL_KEY = H.DECL_KEY)
     WHERE H.MIG_STEP = 4;

    DBMS_OUTPUT.PUT_LINE('STEP 4 SUCCESS');
    DBMS_OUTPUT.PUT_LINE('Header(신고서) = ' || V_H_CNT);
    DBMS_OUTPUT.PUT_LINE('Detail(품목)   = ' || V_D_CNT);
    DBMS_OUTPUT.PUT_LINE('수량 합계      = ' || V_QTY);

    IF V_DRY_RUN = 'Y' THEN
        ROLLBACK;                                   -- 채번 함수가 COMMIT 하므로 마지막 신고서 이후분만 되돌려짐
        DBMS_OUTPUT.PUT_LINE('DRY RUN 은 채번 때문에 완전한 ROLLBACK 이 안 됨 → 개발기에서 테스트');
    ELSE
        DBMS_OUTPUT.PUT_LINE('반영됨 → 건수 확인 후 COMMIT → [채번] 블록 실행');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK;
        DBMS_OUTPUT.PUT_LINE('FAIL → 마지막 채번 이후분만 ROLLBACK (그 전 신고서는 이미 COMMIT 됨)');
        DBMS_OUTPUT.PUT_LINE('→ DELETE (MIG_STEP = 4) 후 재실행');
        DBMS_OUTPUT.PUT_LINE('실패 위치 : ' || V_CUR_KEY);
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        RAISE;
END;
/

/* 다시 돌릴 때
DELETE FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP = 4;
DELETE FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 4;
COMMIT;
*/
