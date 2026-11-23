# 05. 할 일 & 고객 문의 목록

## A. 출근 후 내가 할 일

### A-1. 테이블 정보 확보 (캡처)
- [x] **SA0109D**(매출 GWP) 명세서
- [x] 수불 4종 확인: 상품 **WM0052L(일)/WM0053L(월)**, GWP **WM0352L(일)/WM0353L(월)**
- [ ] **수불 QTY 가 잔량인지 증감인지 판별** (`sql/06` 의 [판별] 쿼리, 마감된 달 하나로)
- [ ] 수불 샘플 10행 (상품 일수불 / GWP 일수불) — 하루에 모든 상품 행이 있는지, 변동 있는 상품만 있는지
- [ ] `docs/01_table_spec.md` 맨 위 **컬럼/PK 확인 쿼리** 실행 결과 (사진 판독 오류 바로잡기용)
- [x] WM0121S 에 GOOS_CD / HS_CD 없음 확인 → 상품 단위는 WM0121L 로 산출
- [ ] WM0121L 이력 범위 / 합계 대사 (아래 쿼리)
```sql
-- (1) WM0121L 이력이 언제부터 있는지, 상품코드 빈 값이 있는지
SELECT MIN(EDI_REPA_DT) MIN_DT, MAX(EDI_REPA_DT) MAX_DT, COUNT(*) CNT,
       COUNT(CASE WHEN GOOS_CD IS NULL THEN 1 END) NO_GOOS_CNT,
       COUNT(DISTINCT GOOS_CD) GOOS_CNT, COUNT(DISTINCT HS_CD) HS_CNT
  FROM WM0121L WHERE COMP_CD = '01';

-- (2) 보세구역별: WM0121L 반입-반출 합계 vs WM0121S 최신 누적
WITH L AS (
  SELECT BOND_GRN_CD, SHED_CD, SUM(NVL(CARI_QTY,0) - NVL(TAKE_OUT_QTY,0)) L_QTY
    FROM WM0121L WHERE COMP_CD = '01' AND EDI_REPA_DT <= :BASE_DT
   GROUP BY BOND_GRN_CD, SHED_CD),
S AS (
  SELECT BOND_GRN_CD, SHED_CD, SUM(ACUM_CARI_QTY - ACUM_TAKE_OUT_QTY) S_QTY
    FROM WM0121S
   WHERE COMP_CD = '01'
     AND EDI_REPA_DT = (SELECT MAX(EDI_REPA_DT) FROM WM0121S WHERE COMP_CD = '01' AND EDI_REPA_DT <= :BASE_DT)
   GROUP BY BOND_GRN_CD, SHED_CD)
SELECT NVL(L.BOND_GRN_CD, S.BOND_GRN_CD) BOND_GRN_CD, NVL(L.SHED_CD, S.SHED_CD) SHED_CD,
       L.L_QTY, S.S_QTY, NVL(L.L_QTY,0) - NVL(S.S_QTY,0) DIFF
  FROM L FULL OUTER JOIN S ON S.BOND_GRN_CD = L.BOND_GRN_CD AND S.SHED_CD = L.SHED_CD
 ORDER BY 1, 2;
-- 차이 0 → WM0121L 합계만으로 상품별 세관재고 산출 가능
-- 차이 있음 → WM0121L 이력이 잘렸거나, WM0121S 가 다른 기준(수기 조정 등) → 고객 확인
```
- [ ] 보세구역코드(BOND_GRN_CD)·장치장(SHED_CD)이 본점/T1/T2/통물 중 어디인지 (MA041 코드 조회)
- [ ] `sql/06` 의 C02 점검 쿼리 (수불에 어떤 점/코너/재고구분/환급구분이 있는지 → 통물·본점·T1·T2 포함 여부)
- [ ] `sql/06` 의 GWP 키 확인 쿼리 (SA0109D.GOOS_CD 가 GWP 수불에 있는지)

### A-2. 재고 귀속 위치 확인 (지난번 1·2번)
- [ ] 판매점·매출점·재고점·재고코너 분포 쿼리
- [ ] `MA0100I` 에서 코너 961 / 965 / 813 / 765 / 607 조회 → **통합물류가 별도 점코드인지, 점 5 밑의 창고 코너인지**

### A-3. 코드값 조회
```sql
SELECT M.COMM_CTG_CD, M.COMM_CTG_NM, D.COMM_CTG_DTL_CD, D.COMM_CTG_DTL_NM,
       D.COMM_PROP_CONT_1, D.COMM_PROP_CONT_2, D.COMM_PROP_CONT_3
  FROM MA0150M M
  JOIN MA0151D D ON D.COMP_CD = M.COMP_CD AND D.WRK_MDUL_CD = M.WRK_MDUL_CD AND D.COMM_CTG_CD = M.COMM_CTG_CD
 WHERE M.COMP_CD = '01'
   AND M.COMM_CTG_CD IN ('SA101','BO014','BO015','WM038','WM014','WM037','GO407','MA071','MA077','MA082','MA083','MK502','MK503')
 ORDER BY 1, 3;

-- BO014 / BO015 의 속성 1~3 이 무슨 뜻인지
SELECT COMM_CTG_CD, COMM_PROP_NM_1, COMM_PROP_NM_2, COMM_PROP_NM_3
  FROM MA0150M WHERE COMP_CD = '01' AND COMM_CTG_CD IN ('BO014','BO015','WM038');
```
특히 **SA101**(매출형태: '1' 외 값), **GO407**(환급구분: 환급 분리 기준 유력), **WM014**(재고구분), **WM037**(불량구분), **MA071**(세관물품구분), **MA083**(G1/F1).

### A-4. 고객 쿼리 문제 영향도 측정 (고객 설명용 숫자)
- [ ] `sql/04` 하단: [A]·[B] 양쪽에 걸린 빌 수 = 147행 오타로 **이중 차감되던 빌 수**
- [ ] `sql/04` 하단: BO0110D 빌당 최대 행 수 = 카톤 중복 여부
- [ ] `sql/02` 하단: 취소 판정 방식 차이 건수
- [ ] 다른 날 취소된 빌 수 (고객 쿼리가 놓치는 건):
```sql
SELECT COUNT(DISTINCT A.BILL_NO) LATE_CNCL_BILLS
  FROM SA0100M A
  JOIN SA0100M E ON E.COMP_CD = A.COMP_CD AND E.STOR_CD = A.STOR_CD
                AND E.BILL_NO = A.BILL_NO AND E.SALE_TYPE_CD <> A.SALE_TYPE_CD
 WHERE A.COMP_CD = '01' AND A.SALE_TYPE_CD = '1'
   AND E.SALE_DT <> A.SALE_DT
   AND A.SALE_DT >= :FR_DT;
```

### A-5. 우리 쪽(프로젝트 내부) 확인
- [ ] **신규 시스템 기초재고 타겟 테이블 스펙** (창고/로케이션/재고유형/단가·금액 필요 여부) — 설계 담당자
- [ ] 스테이징 테이블(MIG_*)을 만들 수 있는 스키마·권한 — DBA
- [ ] 신규 시스템의 점·창고 코드 체계 (매핑표 오른쪽 값)
- [ ] 이행 일정(리허설 회차, 오픈일)

> 조회 결과를 Excel로 내릴 때는 **텍스트 형식**으로. 빌번호·상품코드가 지수로 깨지고 '02' 같은 코드의 앞자리 0이 사라짐.

---

## B. 고객 문의 목록

### B-1. 규칙 해석
| # | 질문 | 왜 필요한가 |
|---|---|---|
| Q1 | 통합물류 계산재고에서 **H신고 재반입면장 교환권을 빼는 이유**가 무엇인지? (재반입 시 수불에 이미 반입으로 잡혀 교환권(+)과 이중이 되기 때문인지) 그렇다면 차감 대상은 교환권(+)에도 해당하는 빌만인지, 전체인지? | 차감 범위가 달라짐 |
| Q2 | 미인도 기초의 "−"는 **(a) 미인도 재고로 별도 적재 + 정상재고에서 차감**인지, **(b) 정상재고에서 차감만**인지? | 타겟 재고유형 설계 |
| Q3 | 본점 GWP "계산재고"는 통합물류와 같은 공식(수불 + 교환권 − H재반입)인지? 본점용 교환권은 어떤 빌상태×상품위치 조합인지? (통물창고·통물미래보세 외에 점창고 01, 점미래보세 11 도 포함?) | 공식 미정의 |
| Q4 | T1·T2 상품은 HS세관재고만 쓰면 되는지? 판매 후 인도 대기 중인 상품은 세관재고에 포함돼 있는 것이 맞는지? | 교환권 보정 필요 여부 |
| Q5 | **통합물류는 별도 점코드인지, 각 점 밑의 창고 코너(예: 961/965)인지?** | 이행 범위·매핑 |
| Q6 | 재고 차감 위치는 매출의 **재고점/재고코너(STOC_STOR_CD/STOC_CORN_CD)** 기준이 맞는지? | 귀속 창고 |

### B-2. 원천 데이터
| # | 질문 | 왜 필요한가 |
|---|---|---|
| Q7 | 수불재고: 일수불(WM0052L/WM0352L) **QTY 가 그날 잔량인지 증감인지**, 월수불 마감은 언제 도는지, "수불 기말재고"는 기준일 일수불 기준이 맞는지 (판별 쿼리 결과와 함께 확인) | C02 추출 |
| Q7-1 | GWP 재고 키는 **상품코드(GOOS_CD)** 가 맞는지 (수불이 GOOS_CD 기준). SA0109D 의 판촉품코드(SPTM_CD)와는 어떤 관계인지 | GWP 기초 |
| Q7-2 | 재고구분(WM014)·불량구분(WM037)별 처리: 불량·폐기예정 재고도 기초에 넣는지, 재고구분별로 신규 시스템 재고유형을 나누는지 | 타겟 재고유형 |
| Q8 | WM0121S 는 상품코드가 없으므로 **상품별 HS세관재고는 WM0121L 의 반입−반출 합계로 산출해도 되는지?** WM0121L 에 전체 이력이 있는지(없으면 시작 잔량은 어디서?). 세관재고 쪽 **환급 구분은 무엇으로 나누는지**(WM0121L 에는 환급구분 컬럼이 없고 세관물품구분·면장구분만 있음). 집계 프로시저를 기준일로 다시 돌려야 하는지 | C01 추출 |
| Q9 | **환급코드 분리**는 WM0053L 의 **환급구분(REFU_CLS_CD, GO407)** 기준인지? 신규 시스템에서 환급구분을 별도 상품코드로 나누는지, 재고 속성으로 두는지. 세관재고(HS) 쪽은 무엇으로 환급 여부를 나누는지 | 변환 |
| Q10 | **구코드 정리** 매핑표 제공 (구→신, N:1 합산 허용 여부, 매핑표 관리 주체) | 변환 |
| Q11 | 판매취소 판정 기준: 매출형태 짝(SALE_TYPE_CD) / 빌상태 08 / MK5010D 중 무엇이 기준인지 | 공통 로직 |
| Q12 | **부분취소·부분반품**(SA0103D 반품수량 RTN_QTY, 라인 취소여부) 발생 여부와 처리 방식 | 수량 산식 |
| Q13 | H면장은 있으나 **G1 확정 전** + 5KP F1 결과통보가 있는 빌은 포함인지 제외인지 | 쿼리 2 [B] 조건 |
| Q14 | 삭제(DEL_YN)·정정신고(CHG_RPT_CLS_CD, CHG_BOND_TRAN_MNGE_NO) 건 처리 방식 | 중복 방지 |

### B-3. 일정·검증
| # | 질문 | 왜 필요한가 |
|---|---|---|
| Q15 | **기준일시(컷오프)**: 영업 마감, 세관 EDI 수신 마감, 수불 마감 시각. 이행 당일 동결 가능 시간 | 본 이행 절차 |
| Q16 | 검증 기준: 무엇과 대사할지(세관재고/실사/현 시스템 재고 화면), **허용 오차**, 사인오프 승인자 | 완료 기준 |
| Q17 | 리허설 일정과 운영 데이터 사용 가능 여부 | 리허설 계획 |
| Q18 | 계산 결과 **음수 재고**가 나오면 처리 원칙 (0 처리 / 원인 확인 후 조정 / 그대로) | 예외 처리 |
| Q19 | 수량 외에 **원가·금액, 로케이션, 유통기한·로트**도 이행 대상인지 | 타겟 범위 |

### B-4. 고객에게 공유할 내용 (질문 아님)
제공 쿼리 검토 결과, 아래는 수정이 필요해 보여 수정본으로 진행하겠다는 확인 요청.
1. 쿼리 2 147행 `SA.COMP_CD = S.BILL_NO` → `S.COMP_CD` 오타로 [A]·[B] 중복 빌이 이중 차감됨 (영향 빌 수: A-4 결과)
2. 판매취소 판정에 같은 매출일 조건이 있어 **다른 날 취소된 건이 정상으로 집계**됨 (영향 빌 수: A-4 결과)
3. 쿼리 2·3 에 상품/GWP 상세 테이블 조인이 없어 수량이 아닌 빌 목록만 나옴
4. 보세운송 상세가 카톤 단위라 수량을 붙이면 중복 가능
