/* =====================================================================
   06. C01 HS세관재고 (본점, T1-DF4, T2-DF4 상품) / C02 수불기말재고 (통물 상품, GWP)
       + 변환(환급분리 → 구코드) + 최종 집계
   ※ 원천 테이블 단위가 확정되지 않아 초안. 확인 사항:
     - WM0121S 에 GOOS_CD 가 있는지 (없으면 WM0121L 기준으로 산출)
     - 집계 프로시저(SP_WMCM_CSTM_RPT_LIST_5_SUM / _8)를 기준일까지 돌린 뒤 사용하는지
     - 환급 분리 기준 컬럼 (CSTM_ITEM_CLS_CD 가정)
     - 수불: WM0053L(물류 월별수불내역, 월 단위). WM0054L 은 폐기신고로 보여 수불 아님 → 일반상품/GWP·일별 수불 테이블 재확인
   바인드: :RUN_ID, :COMP_CD, :BASE_DT
   ===================================================================== */

/* ---------- C01: HS세관재고 = WM0121L 반입-반출 누계 (WM0121S 에는 GOOS_CD/HS_CD 없음 확인 → 대사용) ---------- */
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, BOND_GRN_CD, SHED_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, REFUND_CLS, QTY)
SELECT :RUN_ID, :BASE_DT, L.COMP_CD,
       MS.STOR_CD,                                   -- 보세구역 → 점 매핑 (매핑표 필요, 가칭 MIG_MAP_BOND)
       L.BOND_GRN_CD, L.SHED_CD, 'G', 'N', 'C01', +1,
       L.GOOS_CD,
       L.CSTM_ITEM_CLS_CD,                           -- 환급 분리 기준 (가정) — 집계 전에 보존
       SUM(NVL(L.CARI_QTY,0) - NVL(L.TAKE_OUT_QTY,0))
  FROM WM0121L L
  JOIN MIG_MAP_BOND MS                               -- TODO: (BOND_GRN_CD, SHED_CD) → STOR_CD 매핑표
    ON MS.BOND_GRN_CD = L.BOND_GRN_CD AND MS.SHED_CD = L.SHED_CD
 WHERE L.COMP_CD = :COMP_CD
   AND L.EDI_REPA_DT <= :BASE_DT                     -- 세관 수리일 기준 컷오프
   -- AND L.TOT_YN = 'Y'                             -- 집계유무 의미 확인
 GROUP BY L.COMP_CD, MS.STOR_CD, L.BOND_GRN_CD, L.SHED_CD, L.GOOS_CD, L.CSTM_ITEM_CLS_CD
HAVING SUM(NVL(L.CARI_QTY,0) - NVL(L.TAKE_OUT_QTY,0)) <> 0;

-- 세관재고 산출값 검증: 위 결과를 보세구역 단위로 합산 → WM0121S 누적(ACUM_CARI_QTY-ACUM_TAKE_OUT_QTY)과 비교
SELECT C.BOND_GRN_CD, C.SHED_CD, SUM(C.QTY) CALC_QTY, S.CSTM_QTY, SUM(C.QTY) - S.CSTM_QTY DIFF
  FROM MIG_STOC_COMP C
  LEFT JOIN (SELECT BOND_GRN_CD, SHED_CD, SUM(ACUM_CARI_QTY - ACUM_TAKE_OUT_QTY) CSTM_QTY
               FROM WM0121S
              WHERE COMP_CD = :COMP_CD
                AND EDI_REPA_DT = (SELECT MAX(EDI_REPA_DT) FROM WM0121S WHERE COMP_CD = :COMP_CD AND EDI_REPA_DT <= :BASE_DT)
              GROUP BY BOND_GRN_CD, SHED_CD) S
    ON S.BOND_GRN_CD = C.BOND_GRN_CD AND S.SHED_CD = C.SHED_CD
 WHERE C.MIG_RUN_ID = :RUN_ID AND C.COMP_TYPE = 'C01'
 GROUP BY C.BOND_GRN_CD, C.SHED_CD, S.CSTM_QTY;

/* ---------- C02: 수불재고 (WM0053L 물류 월별수불내역) ----------
   가정: QTY = 해당 월(YMON) 말 재고수량, 기준일 = 월말
   - 기준일이 월말이 아니면: 전월 YMON 재고 + 당월 1일~기준일 일별 수불 (일별 수불 테이블 확인 후 추가)
   - 상품/GWP 구분 방법 미확인: 상품마스터의 상품유형(GOOS_TYPE_CD) 등으로 ITEM_TYPE 판정 필요 → 아래는 MIG_MAP_ITEM_TYPE 가정
   - 대상: 통물 상품, 본점/통물 GWP(계산재고 베이스), T1·T2 GWP(수불재고 그대로)                     */
INSERT INTO MIG_STOC_COMP
      (MIG_RUN_ID, BASE_DT, COMP_CD, STOR_CD, CORN_CD, ITEM_TYPE, STOC_TYPE, COMP_TYPE, SIGN,
       GOOS_CD_ORG, REFUND_CLS, STOC_CLS_CD, FALT_CLS_CD, AGIG_CD, QTY, SRC_KEY)
SELECT :RUN_ID, :BASE_DT, S.COMP_CD, S.STOR_CD, S.CORN_CD,
       NVL(T.ITEM_TYPE, 'G'),                         -- TODO: 상품/GWP 판정 기준 확인
       'N',                                           -- TODO: STOC_CLS_CD(WM014) 값별 정상/미인도 매핑
       'C02', +1,
       S.GOOS_CD, S.REFU_CLS_CD, S.STOC_CLS_CD, S.FALT_CLS_CD, S.AGIG_CD,
       S.QTY,
       S.YMON
  FROM WM0053L S
  LEFT JOIN MIG_MAP_ITEM_TYPE T ON T.GOOS_CD = S.GOOS_CD   -- 가칭: 상품코드 → G/W
 WHERE S.COMP_CD = :COMP_CD
   AND S.YMON = SUBSTR(:BASE_DT, 1, 6)
   AND S.QTY <> 0;

-- C02 점검: 월별수불에 어떤 점/코너/구분값이 들어 있는지 (통물 전용인지 확인)
SELECT STOR_CD, CORN_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD,
       COUNT(*) ROW_CNT, COUNT(DISTINCT GOOS_CD) GOOS_CNT, SUM(QTY) QTY
  FROM WM0053L
 WHERE COMP_CD = :COMP_CD AND YMON = :YMON
 GROUP BY STOR_CD, CORN_CD, STOC_CLS_CD, REFU_CLS_CD, FALT_CLS_CD
 ORDER BY 1, 2, 3, 4, 5;

/* ---------- 변환 1: 환급코드 분리 (집계 전, REFUND_CLS 보존 상태에서) ---------- */
UPDATE MIG_STOC_COMP C
   SET C.GOOS_CD = NVL((SELECT R.GOOS_CD_REF FROM MIG_MAP_REFUND R
                         WHERE R.GOOS_CD_ORG = C.GOOS_CD_ORG AND R.REFUND_CLS = C.REFUND_CLS),
                       C.GOOS_CD_ORG)
 WHERE C.MIG_RUN_ID = :RUN_ID;

/* ---------- 변환 2: 구코드 정리 ---------- */
UPDATE MIG_STOC_COMP C
   SET C.GOOS_CD = (SELECT G.NEW_GOOS_CD FROM MIG_MAP_GOOS G WHERE G.OLD_GOOS_CD = C.GOOS_CD)
 WHERE C.MIG_RUN_ID = :RUN_ID
   AND EXISTS (SELECT 1 FROM MIG_MAP_GOOS G WHERE G.OLD_GOOS_CD = C.GOOS_CD);

/* ---------- 최종 집계: 고객 규칙 매트릭스 적용 ---------- */
INSERT INTO MIG_BASE_STOC (MIG_RUN_ID, BASE_DT, COMP_CD, NEW_WH_CD, ITEM_TYPE, STOC_TYPE, GOOS_CD, QTY)
SELECT C.MIG_RUN_ID, C.BASE_DT, C.COMP_CD, M.NEW_WH_CD, C.ITEM_TYPE, C.STOC_TYPE, C.GOOS_CD,
       SUM(C.SIGN * C.QTY)
  FROM MIG_STOC_COMP C
  JOIN MIG_MAP_STOR M
    ON M.COMP_CD = C.COMP_CD AND M.STOR_CD = C.STOR_CD
   AND M.CORN_CD = (SELECT NVL(MAX(M2.CORN_CD), '*') FROM MIG_MAP_STOR M2      -- 코너 매핑 우선, 없으면 점 전체
                     WHERE M2.COMP_CD = C.COMP_CD AND M2.STOR_CD = C.STOR_CD AND M2.CORN_CD = C.CORN_CD)
 WHERE C.MIG_RUN_ID = :RUN_ID
   AND (   (C.ITEM_TYPE = 'G' AND C.STOC_TYPE = 'N' AND M.SITE_GRP IN ('MAIN','T1','T2') AND C.COMP_TYPE = 'C01')
        OR (C.ITEM_TYPE = 'G' AND C.STOC_TYPE = 'N' AND M.SITE_GRP = 'LOGI' AND C.COMP_TYPE IN ('C02','C03','C04'))
        OR (C.ITEM_TYPE = 'W' AND C.STOC_TYPE = 'N' AND M.SITE_GRP IN ('MAIN','LOGI') AND C.COMP_TYPE IN ('C02','C03','C04'))  -- Q3 확인
        OR (C.ITEM_TYPE = 'W' AND C.STOC_TYPE = 'N' AND M.SITE_GRP IN ('T1','T2') AND C.COMP_TYPE = 'C02')
        OR (C.STOC_TYPE = 'U' AND M.SITE_GRP IN ('MAIN','LOGI') AND C.COMP_TYPE = 'C05')  -- Q2 확인 (부호/정상재고 차감 여부)
       )
 GROUP BY C.MIG_RUN_ID, C.BASE_DT, C.COMP_CD, M.NEW_WH_CD, C.ITEM_TYPE, C.STOC_TYPE, C.GOOS_CD
HAVING SUM(C.SIGN * C.QTY) <> 0;
