/* ==========================================================================
   STEP 1. 상품 기초 — 본점 / T1-DF4 / T2-DF4 : HS세관재고 (PL/SQL 적재)
   --------------------------------------------------------------------------
   - 조회 로직은 SELECT 버전(step1_goods_cstm.sql)과 동일, 적재만 LOOP 로
   - (보세구역, 장치장) 바뀔 때 또는 품목 9,999 건 찰 때 → 채번 1번 + Header 1건
     그 아래 품목은 같은 신고번호로 Detail → Header-Detail 쌍 보장
   - 채번 : FN_MA_AUTO_NO('01', 'BO15'(물품반입신고번호),
                          세관(MA041 속성1) || 과(MA041 속성2) || 보세구역 || YY || 'A', 등록자)
   - 적재 대상 : TMP_ITEMCARRYIN_H / TMP_ITEMCARRYIN_D (MIG_STEP = 1)   ※ DDL 은 step5_tmp_load.sql

   사용법
     1) V_DRY_RUN = 'Y' 로 실행 → DBMS_OUTPUT 건수 확인 (끝나면 자동 ROLLBACK)
     2) 이상 없으면 V_DRY_RUN = 'N' 으로 실행 → 건수 확인 후 COMMIT
     ※ DBMS_OUTPUT 켜고 실행
     ※ 채번 함수 안에서 COMMIT 하면 SAVEPOINT 가 지워져 ROLLBACK TO 가 실패함 → 함수 소스 확인
        (PRAGMA AUTONOMOUS_TRANSACTION 이면 문제 없음. 단 DRY RUN 이어도 번호는 소모됨 → 개발기에서 먼저)
   ========================================================================== */
DECLARE
    V_DRY_RUN     VARCHAR2(1)  := 'Y';            -- Y: 끝나고 ROLLBACK / N: 반영
    V_REGR_ID     VARCHAR2(10) := 'MIG';          -- 채번 등록자 (확인)
    V_BASE_DT     VARCHAR2(8)  := '20261130';     -- 기준일
    V_DECL_DT     VARCHAR2(8)  := '20261201';     -- 신고일자

    V_DECL_NO     VARCHAR2(27);
    V_BOND        VARCHAR2(20);
    V_SHED        VARCHAR2(20);
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
    -- ① HS세관재고 : 자기 장치장, 반입 − 반출 누계
    CSTM AS (
        SELECT L.BOND_GRN_CD
             , L.SHED_CD
             , L.GOOS_CD
             , L.CSTM_GOOS_CD
             , L.HS_CD
             , L.CSTM_ITEM_CLS_CD
             , SUM(NVL(L.CARI_QTY, 0) - NVL(L.TAKE_OUT_QTY, 0)) AS QTY
          FROM WM0121L L
         WHERE L.COMP_CD      = '01'
           AND L.BOND_GRN_CD IN (SELECT BOND_GRN_CD FROM BOND)
           AND L.EDI_REPA_DT <= V_BASE_DT
           AND L.SHED_CD      = L.BOND_GRN_CD                       -- 자기 장치장만
         GROUP BY L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_GOOS_CD, L.HS_CD, L.CSTM_ITEM_CLS_CD
    ),
    -- 환급코드 마스터
    REFU AS (
        SELECT R.GOOS_CD
             , R.CSTM_GOODS_TYPE_CD
             , R.CSTM_GOOS_CD
          FROM MA9301C R
         WHERE R.COMP_CD = '01'
           AND R.USE_YN  = 'Y'
    ),
    -- ② 환급코드 먼저 반영
    TAGGED AS (
        SELECT C.BOND_GRN_CD
             , C.SHED_CD
             , C.HS_CD
             , C.QTY
             , C.GOOS_CD
             , C.CSTM_ITEM_CLS_CD                                       AS CSTM_GOODS_TYPE_CD
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN R.CSTM_GOOS_CD
                    WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL
                         THEN DECODE(G.GOOS_TYPE_CD, '1', '5', '6') || SUBSTR(G.GOOS_CD, 2)
               END                                                      AS NEW_CSTM_GOOS_CD
             , CASE WHEN R.CSTM_GOOS_CD IS NOT NULL THEN 'MA9301C'
                    WHEN C.CSTM_ITEM_CLS_CD = 'W' AND G.GOOS_CD IS NOT NULL THEN 'W_RULE'
                    WHEN G.GOOS_CD IS NULL THEN 'NO_MASTER'
                    ELSE 'NO_TYPE' END                                  AS MATCH_BY
          FROM CSTM C
          LEFT JOIN MA0040C G
            ON G.COMP_CD = '01'
           AND G.GOOS_CD = C.GOOS_CD
          LEFT JOIN REFU R
            ON R.GOOS_CD            = C.GOOS_CD
           AND R.CSTM_GOODS_TYPE_CD = C.CSTM_ITEM_CLS_CD
    ),
    -- ③ 집계 : 보세구역 × 장치장 × 환급구분 × 세관상품코드
    AGG AS (
        SELECT T.BOND_GRN_CD
             , T.SHED_CD
             , T.CSTM_GOODS_TYPE_CD
             , T.NEW_CSTM_GOOS_CD
             , T.GOOS_CD
             , MAX(T.MATCH_BY)   AS MATCH_BY
             , MAX(T.HS_CD)      AS HS_CD
             , SUM(T.QTY)        AS QTY
          FROM TAGGED T
         GROUP BY T.BOND_GRN_CD, T.SHED_CD, T.CSTM_GOODS_TYPE_CD, T.NEW_CSTM_GOOS_CD, T.GOOS_CD
        HAVING SUM(T.QTY) > 0
    )
    SELECT A.BOND_GRN_CD
         , A.SHED_CD
         , A.CSTM_GOODS_TYPE_CD
         , A.NEW_CSTM_GOOS_CD
         , A.GOOS_CD
         , A.MATCH_BY
         , A.HS_CD
         , A.QTY
         , D.STOR_NM
         -- 채번 접두 : 세관(3) + 과(2) + 보세구역(8) + 년도(2) + 'A'
         , N.COMM_PROP_CONT_1 || N.COMM_PROP_CONT_2 || A.BOND_GRN_CD
           || TO_CHAR(SYSDATE, 'YY') || 'A'                             AS NO_PREFIX
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
      LEFT JOIN MA0151D N                                           -- 보세구역 → 세관·과
        ON N.COMP_CD         = '01'
       AND N.WRK_MDUL_CD     = 'MA'
       AND N.COMM_CTG_CD     = 'MA041'
       AND N.COMM_CTG_DTL_CD = A.BOND_GRN_CD
      LEFT JOIN MA0040C M                                           -- 상품마스터
        ON M.COMP_CD = '01'
       AND M.GOOS_CD = A.GOOS_CD
      LEFT JOIN MA0030C B                                           -- 브랜드
        ON B.COMP_CD = M.COMP_CD
       AND B.BRAN_CD = M.BRAN_CD
      LEFT JOIN MA3118I V                                           -- 상품용량추가정보
        ON V.COMP_CD = '01'
       AND V.GOOS_CD = A.GOOS_CD
     ORDER BY A.BOND_GRN_CD, A.SHED_CD, A.CSTM_GOODS_TYPE_CD, A.NEW_CSTM_GOOS_CD, A.GOOS_CD;

BEGIN
    DBMS_OUTPUT.ENABLE(NULL);

    -- 재실행 방지 (번호가 또 나가므로)
    SELECT COUNT(*) INTO V_EXIST FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 1;
    IF V_EXIST > 0 THEN
        RAISE_APPLICATION_ERROR(-20001, 'STEP 1 이 이미 TMP 에 있음 → DELETE (H/D, MIG_STEP = 1) 후 실행');
    END IF;

    SAVEPOINT SP_STEP1;

    FOR R IN C_SRC LOOP
        V_CUR_KEY := R.BOND_GRN_CD || '/' || R.SHED_CD || '/' || R.GOOS_CD;

        -- 새 신고서 : 보세구역·장치장이 바뀌거나 9,999 품목 찼을 때
        IF V_BOND IS NULL OR R.BOND_GRN_CD <> V_BOND OR R.SHED_CD <> V_SHED OR V_SEQ >= 9999 THEN

            IF R.NO_PREFIX IS NULL OR LENGTH(R.NO_PREFIX) < 16 THEN
                RAISE_APPLICATION_ERROR(-20002, '채번 접두 이상 (MA041 세관·과 코드 확인) : ' || R.BOND_GRN_CD);
            END IF;

            V_DECL_NO := FN_MA_AUTO_NO('01', 'BO15', R.NO_PREFIX, V_REGR_ID);

            INSERT INTO TMP_ITEMCARRYIN_H
            (
                  MIG_STEP, BASE_DT, LOAD_DTTM
                , DECLARATION_NO, WH_CODE, DOC_TYPE, DECLARATION_DATE, AMEND_TYPE, CARRYIN_LOC
                , REFERENCE_NO, DECLARATION_TYPE, STATUS, C_DATETIME, INTERNATIONAL_MAIL_YN
                , REF_STOR_NM, REF_SITE
            )
            VALUES
            (
                  1, V_BASE_DT, SYSDATE
                , V_DECL_NO                                                        --  1 신고번호
                , R.BOND_GRN_CD                                                    --  2 신고지점
                , 'DLG'                                                            --  3 문서구분
                , V_DECL_DT                                                        --  4 신고일자
                , NULL                                                             --  5 정정구분
                , CASE WHEN R.SHED_CD = R.BOND_GRN_CD THEN NULL ELSE R.SHED_CD END --  6 반입장치장소
                , NULL                                                             --  7 근거번호
                , 'Z'                                                              --  8 신고구분 기초재고반입
                , 'A1'                                                             --  9 상태
                , SYSDATE                                                          -- 10 생성일시
                , NULL                                                             -- 11 국제우편여부
                , R.STOR_NM, 'OWN'
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
            , REF_STOR_NM, REF_SHED_CD, REF_SITE, REF_GOOS_CD, REF_GOOS_GWP, REF_MATCH_BY, REF_REF_NO, REF_Q_CSTM
        )
        VALUES
        (
              1, V_BASE_DT, SYSDATE
            , V_DECL_NO                                   --  1 신고번호 (Header 와 동일)
            , R.BOND_GRN_CD                               --  2 신고지점
            , 'DLG'                                       --  3 문서구분
            , V_SEQ                                       --  4 품목일련번호
            , NULL                                        --  5 란정정구분
            , R.CSTM_GOODS_TYPE_CD                        --  6 물품구분 T/D/W
            , R.HS_CD                                     --  7 HS코드
            , R.NEW_CSTM_GOOS_CD                          --  8 상품코드 (세관신고 상품코드)
            , R.ITEM_NAME                                 --  9 품명
            , R.STDZ_CONT                                 -- 10 규격
            , R.QTY                                       -- 11 수량
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
            , R.STOR_NM, R.SHED_CD, 'OWN', R.GOOS_CD, '상품', R.MATCH_BY, R.REF_NO, R.QTY
        );

        V_D_CNT := V_D_CNT + 1;
        V_QTY   := V_QTY + R.QTY;
    END LOOP;

    -- Header 참고 합계
    UPDATE TMP_ITEMCARRYIN_H H
       SET (REF_ITEM_CNT, REF_QTY, REF_Q_CSTM) =
           (SELECT COUNT(*), SUM(D.ITEM_QTY), SUM(D.REF_Q_CSTM)
              FROM TMP_ITEMCARRYIN_D D
             WHERE D.MIG_STEP       = 1
               AND D.DECLARATION_NO = H.DECLARATION_NO
               AND D.WH_CODE        = H.WH_CODE)
     WHERE H.MIG_STEP = 1;

    DBMS_OUTPUT.PUT_LINE('STEP 1 SUCCESS');
    DBMS_OUTPUT.PUT_LINE('Header(신고서) = ' || V_H_CNT);
    DBMS_OUTPUT.PUT_LINE('Detail(품목)   = ' || V_D_CNT);
    DBMS_OUTPUT.PUT_LINE('수량 합계      = ' || V_QTY);

    IF V_DRY_RUN = 'Y' THEN
        ROLLBACK TO SP_STEP1;
        DBMS_OUTPUT.PUT_LINE('DRY RUN → ROLLBACK (반영 안 됨)');
    ELSE
        DBMS_OUTPUT.PUT_LINE('반영됨 → 건수 확인 후 COMMIT');
    END IF;

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO SP_STEP1;
        DBMS_OUTPUT.PUT_LINE('FAIL → 전체 ROLLBACK');
        DBMS_OUTPUT.PUT_LINE('실패 위치 : ' || V_CUR_KEY);
        DBMS_OUTPUT.PUT_LINE(SQLERRM);
        RAISE;
END;
/

/* 다시 돌릴 때 (TMP 만 지움, 이미 나간 번호는 돌아오지 않음)
DELETE FROM TMP_ITEMCARRYIN_D WHERE MIG_STEP = 1;
DELETE FROM TMP_ITEMCARRYIN_H WHERE MIG_STEP = 1;
COMMIT;
*/
