# 03. 고객 제공 쿼리 분석 (`재고관련_정리.sql`)

심각도: 🔴 결과가 틀림 / 🟠 상황에 따라 틀릴 수 있음 / 🟡 개선 권장

---

## 쿼리 1. 매출조회 기본 (line 1~37)

```sql
SELECT *
  FROM SA0100M A                         -- 매출기본
  JOIN SA2000I B ON A.COMP_CD=B.COMP_CD AND A.STOR_CD=B.STOR_CD AND A.SALE_DT=B.SALE_DT
                AND A.POS_NO=B.POS_NO AND A.RCPT_NO=B.RCPT_NO        -- 매출기본부속정보
  JOIN SA0103D C ON (A와 동일 5개 키)                                  -- 매출상세
  JOIN MA0100I D ON C.COMP_CD=D.COMP_CD AND C.STOR_CD=D.STOR_CD AND C.CORN_CD=D.CORN_CD
 WHERE A.COMP_CD=:COMP_CD AND A.STOR_CD=:STOR_CD AND A.SALE_STOR_CD=:SALE_STOR_CD
-- AND A.SALE_DT = :STD_DT / A.BILL_PROC_CLS_CD = '' / A.GOOS_LOC_CLS_CD = ''   (주석)
   AND NOT EXISTS (SELECT 1 FROM SA0100M E
                    WHERE E.COMP_CD=A.COMP_CD AND E.STOR_CD=A.STOR_CD
                      AND E.SALE_DT=A.SALE_DT AND E.BILL_NO=A.BILL_NO
                      AND E.SALE_TYPE_CD != A.SALE_TYPE_CD)   -- 판매취소가 아닌 것
```

**의도**: 판매취소되지 않은 매출을 상품 단위로 조회 → 교환권(빌상태 × 상품위치) 수량 산출의 기반.

| # | 심각도 | 문제 | 영향 / 수정안 |
|---|---|---|---|
| 1-1 | 🔴 | 취소 판정 NOT EXISTS 에 `E.SALE_DT = A.SALE_DT` | **다른 날 취소된 빌을 정상으로 판단**. 면세점은 출국 전/인도장 취소가 대부분 후일 발생 → 교환권 과다. **SALE_DT 조건 제거**, 대신 `E.SALE_DT <= :BASE_DT`(기준일까지 발생한 취소만). |
| 1-2 | 🟠 | `JOIN SA2000I` (INNER) | 부속정보가 없는 매출은 누락. 재고 계산에 불필요하므로 **제거** (필요 시 LEFT JOIN). |
| 1-3 | 🟠 | `JOIN MA0100I` 키가 COMP/STOR/CORN 3개 | MA0100I PK가 더 많은 컬럼(구역 등)이면 행 복제 → 수량 중복. PK 확인 후 필요시 제거. |
| 1-4 | 🟠 | 빌 단위 취소만 판정 | SA0103D에 `SALE_CNCL_YN`, `RTN_QTY`, `SALE_CNCL_RCEP_QTY` 존재 → **부분취소/부분반품** 가능성. 라인단위 취소 처리 방식 확인 필요. |
| 1-5 | 🟡 | NOT EXISTS 가 양방향(`!=`) | 원매출('1')이든 취소전표든 짝이 있으면 둘 다 제외 → 의도대로 동작. 단, 정상매출만 대상이면 `A.SALE_TYPE_CD='1'` 명시가 더 명확. |
| 1-6 | 🟡 | `BILL_PROC_CLS_CD='08'(판매취소)` 미활용 | 이중 안전장치로 `A.BILL_PROC_CLS_CD <> '08'` 병행 + 두 방식 결과 차이 건수 대사 권장. |
| 1-7 | 🟡 | 쿼리 끝에 `;` 없음 | 그래서 line 42 `SELECT` 에 Toad 오류 표시(빨간 !). 실행 범위 문제일 뿐 로직 문제는 아님. |
| 1-8 | 🟡 | 재고 귀속처 | 교환권 재고를 어느 창고에 넣을지는 `STOR_CD`가 아니라 **`SA0103D.STOC_STOR_CD / STOC_CORN_CD`(재고점/재고코너)** 기준이어야 함. 샘플: 판매점 5, 재고코너 965/961/813. |

> ⚠️ **중요**: `BILL_PROC_CLS_CD`, `GOOS_LOC_CLS_CD` 는 **현재 상태(스냅샷)** 컬럼. 과거 시점으로 되돌려 계산할 수 없음
> → 교환권 수량은 **오픈 직전 영업마감 후 동결 시점에 추출**해야 하며, 리허설 때 값과 본 이행 때 값이 다른 것이 정상.

---

## 공통코드 조회 (line 41~73)

- line 42~47: `MA0150M` BO 모듈 공통분류 조회, line 50~54: `MA0151D` BO015 상세 → 정상.
- line 71~73: `MA0151D WHERE COMM_CTG_DTL_CD IN ('05','75',...)` 🟡 **WRK_MDUL_CD / COMM_CTG_CD 조건 없음** → 모든 분류의 '05' 등이 섞여 나옴. `AND WRK_MDUL_CD='WM' AND COMM_CTG_CD='WM038'` 추가.
- line 57~68: 집계 테이블 `WM0121L`(SP_WMCM_CSTM_RPT_LIST_8, 장치장소별 세관신고 내역), `WM0121S`(SP_WMCM_CSTM_RPT_LIST_5_SUM, 보세구역별 세관재고 수기집계) → **HS세관재고의 원천**.

---

## 쿼리 2. H신고 재반입면장 교환권 중 판매취소 아닌 교환권의 판매수량 (line 76~185)

구조:
```
[A] BO0110M ─ BO0110D ─ SA0100M(SALE_TYPE_CD='1')
      ─ IFWM11M (EDI_DOC_STAT_CD='G1' 확정통보)
      ─ MA0151D (WM038, PMIT_CLS_CD ∈ 05,75,85,10,80,90,20,91 AND PROP_CONT_1='H')
      + NOT EXISTS(판매취소)
UNION ALL
[B] SA0100M ─ MK5010D ─ IFWM12M ('5KP', CSTM_RPT_CLS_CD ∈ B,R, 'F1' 결과통보)      /* WM038엔 없지만 대상 */
      + NOT EXISTS(판매취소)
      + NOT EXISTS([A]에 이미 있는 빌)   ← "ZZZ" 서브쿼리
```

| # | 심각도 | 문제 | 영향 / 수정안 |
|---|---|---|---|
| 2-1 | 🔴 | **line 147 `AND SA.COMP_CD = S.BILL_NO`** | 오타. 회사코드('01')와 빌번호는 절대 같을 수 없음 → **ZZZ NOT EXISTS 가 항상 참** → [A]와 [B]에 모두 해당하는 빌이 **이중 차감**. `SA.COMP_CD = S.COMP_CD` 로 수정 (+ `SA.BILL_NO = S.BILL_NO` 권장). |
| 2-2 | 🔴 | `SELECT * ... UNION ALL SELECT *` | [A]는 5개 테이블, [B]는 3개 테이블 전체 컬럼 → 컬럼 수 불일치로 **ORA-01789** 발생. 필요한 키/수량 컬럼만 명시. |
| 2-3 | 🔴 | **수량 테이블(SA0103D / SA0109D) 조인이 없음** | 제목은 "판매수량"인데 빌 헤더만 나옴. 상품별 수량을 내려면 SA0103D(상품), SA0109D(GWP) 조인 필요. 헤더 `SA0100M.GOOS_QTY`는 상품별 재고에 못 씀. |
| 2-4 | 🔴 | BO0110D 는 카톤(CT_NO)/순번 단위 | 한 빌이 여러 카톤/순번이면 여러 행 → 상세 수량을 붙이면 **배수로 뻥튀기**. 빌 키를 먼저 `DISTINCT` 로 만든 뒤 상세를 붙일 것. |
| 2-5 | 🟠 | IFWM11M 를 `JOIN` | 한 EDI_RPT_NO 에 문서/상태 이력이 여러 건이면 중복. `EXISTS` 로 변경. |
| 2-6 | 🟠 | 삭제·정정 미처리 | `BM.DEL_YN`, `BM.FIX_YN`, `IM.DEL_YN`, 정정신고(`CHG_RPT_CLS_CD`, `CHG_BOND_TRAN_MNGE_NO`) 조건 없음 → 삭제/정정 전 면장까지 집계 가능. |
| 2-7 | 🟠 | 판매취소 NOT EXISTS 에 `E.SALE_DT = SA.SALE_DT` | 1-1과 동일. 후일 취소 누락. |
| 2-8 | 🟠 | ZZZ 서브쿼리가 [A]와 조건이 다름 | [A]는 G1 확정통보 필요, ZZZ는 G1 조건 없음 → "H면장은 있으나 G1 미확정 + 5KP F1은 있음" 빌은 **[A]·[B] 어디에도 안 잡힘**. 의도 확인 필요. (수정안은 빌 키를 `UNION` 해서 자연 중복 제거) |
| 2-9 | 🟠 | 기준일자 조건 없음 | 마이그레이션 기준일 이후 신고/매출까지 포함. `EDI_RPT_DT <= :BASE_DT`, `SALE_DT <= :BASE_DT` 필요. |
| 2-10 | 🟠 | 점(창고) 조건 없음 | 고객 정의상 이 차감은 **통합물류** 계산재고용. 귀속 창고 컬럼(`STOC_STOR_CD` or BO0110M `ARRV_PLAC_CD`) 기준 필터 확인 필요. |
| 2-11 | 🟡 | BD → SA 조인이 COMP/STOR/BILL_NO 뿐 | BILL_NO 가 점 내에서 유일하면 OK. 아니면 SALE_DT/POS/RCPT 까지 필요(BO0110D.RCPT_NO 존재). |
| 2-12 | 🟡 | IN 목록 + `PROP_CONT_1='H'` 이중 조건 | 마스터와 하드코딩 중 무엇이 기준인지 정리 (02_common_codes.md 확인 쿼리). |

---

## 쿼리 3. 미인도반입면장 교환권 중 판매취소 아닌 교환권의 판매수량 (line 187~221)

쿼리 2-[A]와 동일 구조, 면장구분만 `IN ('06','76','86')` (미인도반입면장/국산/외국인국산), `PROP_CONT_1` 조건 없음.

동일 문제: **2-3(수량 조인 없음), 2-4(카톤 중복), 2-5, 2-6, 2-7, 2-9, 2-10**.
추가: 고객 정의상 **본점 / 통물**에만 적용, T1·T2 는 "없음" → 점 필터 필수.

---

## 요약 — 꼭 고쳐야 하는 것 5가지

1. **line 147 `SA.COMP_CD = S.BILL_NO` 오타** → 이중 차감
2. **취소 판정의 `SALE_DT` 동일 조건** → 후일 취소 누락 (모든 쿼리 공통)
3. **SA0103D/SA0109D 미조인** → "판매수량"이 아니라 빌 목록만 나옴
4. **BO0110D 카톤 단위 중복** → 수량 배수
5. **기준일자/점/삭제·정정 조건 부재**

수정 버전은 `sql/` 폴더 참고.
