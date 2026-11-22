# 01. 테이블 명세서 (사진 판독본)

> 출처: 폐쇄망 Excel 명세서(Sheet2: 데이터타입, Sheet3: 코멘트) 및 Toad 화면 사진 판독.
> 사진 해상도 문제로 **`(?)` 표시는 판독 불확실** → 실제 DB에서 `ALL_TAB_COLUMNS` / `ALL_COL_COMMENTS`로 반드시 재확인.
> PK/인덱스는 사진에 없음 → 아래 쿼리로 확인 필요.

```sql
-- 컬럼/코멘트 일괄 확인
SELECT c.TABLE_NAME, c.COLUMN_ID, c.COLUMN_NAME, c.DATA_TYPE, c.DATA_LENGTH, c.NULLABLE, m.COMMENTS
  FROM ALL_TAB_COLUMNS c
  LEFT JOIN ALL_COL_COMMENTS m
    ON m.OWNER = c.OWNER AND m.TABLE_NAME = c.TABLE_NAME AND m.COLUMN_NAME = c.COLUMN_NAME
 WHERE c.OWNER = 'US_OWNER'
   AND c.TABLE_NAME IN ('SA0100M','SA0103D','SA0109D','SA2000I','MA0100I','MA0150M','MA0151D',
                        'WM054L','WM053L','BO0110M','BO0110D','IFWM11M','IFWM12M','MK5010D','WM0121L','WM0121S')
 ORDER BY c.TABLE_NAME, c.COLUMN_ID;

-- PK / UK 확인 (조인 시 중복 발생 여부 판단에 필수)
SELECT con.TABLE_NAME, con.CONSTRAINT_NAME, con.CONSTRAINT_TYPE,
       LISTAGG(col.COLUMN_NAME, ', ') WITHIN GROUP (ORDER BY col.POSITION) AS COLS
  FROM ALL_CONSTRAINTS con
  JOIN ALL_CONS_COLUMNS col
    ON col.OWNER = con.OWNER AND col.CONSTRAINT_NAME = con.CONSTRAINT_NAME
 WHERE con.OWNER = 'US_OWNER'
   AND con.CONSTRAINT_TYPE IN ('P','U')
   AND con.TABLE_NAME IN ('SA0100M','SA0103D','SA0109D','SA2000I','MA0100I','BO0110M','BO0110D',
                          'IFWM11M','IFWM12M','MK5010D','WM0121L','WM0121S')
 GROUP BY con.TABLE_NAME, con.CONSTRAINT_NAME, con.CONSTRAINT_TYPE;
```

---

## 테이블 목록

| 테이블 | 한글명 (추정 포함) | 재고 마이그레이션에서의 역할 |
|---|---|---|
| SA0100M | 영업_매출기본 (빌 헤더) | 교환권/판매취소 판정, 빌 상태(BO015)·상품위치(BO014) |
| SA0103D | 영업_매출상세 (상품) | **상품 판매수량** (교환권 수량 산출) |
| SA0109D | 영업_매출상세 (GWP) | **GWP 판매수량** — ※ 명세서 사진 없음, 별도 확인 필요 |
| **WM054L** | 수불 (일반상품) | **통물 상품 계산재고의 베이스 (수불 기말재고)** — ※ 명세서 사진 없음 |
| **WM053L** | 수불 (GWP) | **GWP 기초 (본점·통물 계산재고 베이스 / T1·T2 수불재고)** — ※ 명세서 사진 없음 |
| SA2000I | 영업_매출기본부속정보 | 배송/멤버십 정보 (재고 계산에는 불필요) |
| MA0100I | 마스터_점코너구역정보 | 코너 → 창고/구역 매핑 |
| MA0150M | 공통코드 기본 (분류) | 코드 분류 정의 |
| MA0151D | 공통코드 상세 | 코드값 (WM038 면장구분 등) |
| BO0110M | 보세운송 기본 | 면장(반입면장) 헤더, 면장구분코드 |
| BO0110D | 보세운송 상세 | 면장 ↔ 빌번호 연결 |
| IFWM11M | EDI 인터페이스(보세운송/반입 신고) | 세관 확정통보(G1) 여부 |
| IFWM12M | EDI 인터페이스(반입신고 5KP) | 세관 결과통보(F1) 여부 |
| MK5010D | 판매취소(회수) 상세 | 판매취소/재반입 신고번호 |
| WM0121L | 보세구역 장치장소별 세관신고 내역 (SP_WMCM_CSTM_RPT_LIST_8) | HS세관재고 원천(상세) |
| WM0121S | 보세구역별 세관재고 수기집계 (SP_WMCM_CSTM_RPT_LIST_5_SUM) | HS세관재고 원천(집계) |

공통 감사 컬럼(대부분 테이블에 존재): `REG_PGM_ID`(등록프로그램ID), `FIRS_REGR_ID`/`FIRS_REG_DTTM`(최초등록자/일시, DATE), `FINA_REGR_ID`/`FINA_REG_DTTM`(최종등록자/일시, DATE). 아래 표에서는 생략.

---

## SA0100M — 영업_매출기본

| 컬럼 | 타입 | 설명 / 코드 |
|---|---|---|
| COMP_CD | CHAR | 회사코드 ('01') |
| STOR_CD | VARCHAR2 | 점코드 |
| SALE_DT | VARCHAR2 | 매출일자 (YYYYMMDD) |
| POS_NO | VARCHAR2 | POS번호 |
| RCPT_NO | NUMBER | 영수증번호 |
| SALE_STOR_CD | VARCHAR2 | 매출점코드 |
| BILL_NO | VARCHAR2 | 빌번호 (15자리, **Excel에서 지수표기로 깨짐 주의**) |
| BILL_BRCD | VARCHAR2 | 빌바코드 |
| CORN_CD | VARCHAR2 | 코너코드 |
| SYSM_DT / SYSM_TM | VARCHAR2 | 시스템일자/시간 |
| EMP_NO / EMP_NM | VARCHAR2 | 사원번호/사원명 |
| TOT_SALE_DOLR_AMT / TOT_SALE_WON_AMT | NUMBER | 총매출 달러/원화금액 |
| DC_DOLR_AMT / DC_WON_AMT | NUMBER | 할인 달러/원화금액 |
| NET_SELL_DOLR_AMT / NET_SELL_WON_AMT | NUMBER | 순매출 달러/원화금액 |
| OFLN_SETT_DC_DOLR_AMT / _WON_AMT | NUMBER | 오프라인결제할인 달러/원화 |
| ONLN_SETT_DC_DOLR_AMT / _WON_AMT | NUMBER | 온라인결제할인 달러/원화 |
| DTL_CNT | NUMBER | 상세건수 |
| GOOS_QTY | NUMBER | 상품수량 |
| **SALE_TYPE_CD** | VARCHAR2 | 매출형태코드 (MA0150M, SA, **SA101**) — 샘플 '1'=정상매출(추정), 그 외=취소/반품 |
| SALE_CHL_CD | VARCHAR2 | 매출채널코드 (SA, SA103) |
| SALE_CRS_CLS_CD | VARCHAR2 | 판매경로구분코드 (MA, MA038) — 샘플 'OFF' |
| SALE_TYPE_CLS_CD | VARCHAR2 | 판매유형구분코드 (MA, MA039) |
| CUST_TYPE_CD | VARCHAR2 | 고객유형코드 (MA, MA006) |
| IFLW_CRS_CLS_CD | VARCHAR2 | 유입경로구분코드 (MA, MA007) |
| SPSA_SER_NO / SPSA_YMON | VARCHAR2 | 특판일련번호 / 특판년월 |
| SALE_CNCL_RESN_CD / _CONT | VARCHAR2 | 판매취소사유코드(SA, SA104) / 내용 |
| CUST_GRP_CD | VARCHAR2 | 고객그룹코드 |
| SRVC_SALE_CLS_CD | VARCHAR2 | 서비스매출구분코드 (SA, SA105) |
| PSPT_NO / CUST_NM / TEL_NO | VARCHAR2 | 여권번호/고객명/전화번호 (**암호화**) |
| MBSH_NO | VARCHAR2 | 회원번호 |
| CUST_LVL_CD | VARCHAR2 | 고객등급코드 (MA, MA005) |
| NATI_CD | VARCHAR2 | 국가코드 (MA, MA024) |
| SEX_CD / BIRT_DT | | 성별(MA013) / 생년월일 |
| DPAT_DT / DPAT_TM / OPEN_NM | VARCHAR2 | 출국일자/출국시간/편명 |
| ARRV_AIRP_CD | VARCHAR2 | 도착공항코드 |
| PSNG_TRAN_WAY_CD | VARCHAR2 | 여객운송수단코드 (MA, MA021) |
| BCA_CD | VARCHAR2 | 인도장코드 (MA, MA025) |
| COUP_PUBL_YN / CASH_RCPT_PUBL_YN | CHAR | 쿠폰발행/현금영수증발행 여부 |
| INET_SALE_REQ_ORD_NO | VARCHAR2 | 인터넷판매요청주문번호 |
| ETC_LOSS_CUR_CD / ETC_LOSS_FC_AMT | | 잡손실 통화/외화금액 |
| GRP_CD_CHG_YN | CHAR | 그룹코드변경여부 |
| CUST_MEMO / EMP_MEMO | VARCHAR2 | 고객/직원 메모 |
| STF_COMP_CD / STF_EMP_NO | VARCHAR2 | 임직원 회사코드/사번 |
| GATE_DELV_TARG_YN / GATE_NO / SEAT_NO | | GATE인도대상여부/게이트/좌석 |
| DISP_SALE_YN | CHAR | 전시판매여부 |
| **GOOS_LOC_CLS_CD** | VARCHAR2 | **상품위치구분코드 (MA0150M, BO, BO014)** — 교환권 판정 키 |
| **BILL_PROC_CLS_CD** | VARCHAR2 | **빌처리구분코드 = 빌상태 (MA0150M, BO, BO015)** — 교환권 판정 키 |
| LGMT_PUR_RPT_YN | CHAR | 고액구매신고여부 |
| DISP_ISSU_INDC_YN | CHAR | (?)전시 관련 여부 |
| **STOC_STOR_CD / STOC_CORN_CD** | VARCHAR2 | **재고점코드 / 재고코너코드** — 재고 귀속처 |

## SA0103D — 영업_매출상세(상품)

| 컬럼 | 타입 | 설명 / 코드 |
|---|---|---|
| COMP_CD, STOR_CD, SALE_DT, POS_NO, RCPT_NO | | SA0100M 조인키 |
| SEQ | NUMBER | 순번 |
| SALE_STOR_CD, BILL_NO, CORN_CD | | 매출점/빌번호/코너 |
| SALE_TYPE_CD, SALE_CHL_CD, SALE_CRS_CLS_CD, SALE_TYPE_CLS_CD, CUST_TYPE_CD, IFLW_CRS_CLS_CD | | 헤더와 동일 의미 |
| **GOOS_CD** | VARCHAR2 | **상품코드** (12자리, Excel 지수표기 주의) |
| AGIG_CD | VARCHAR2 | 에이징코드 |
| GOOS_TYPE_CD | VARCHAR2 | 상품유형코드 (MA, MA009?) |
| BRAN_CD / BRAN_GRP_CD | VARCHAR2 | 브랜드 / 브랜드그룹 |
| GOOS_HIGP_CD / GOOS_MLF_CD / GOOS_LGRP_CD | VARCHAR2 | 상품 대/중/소분류 |
| REF_NO | VARCHAR2 | 레퍼런스번호 |
| SALE_DOLR_UCST / SALE_WON_UCST | NUMBER | 판매단가 달러/원화 |
| COST_DOLR_UCST / COST_WON_UCST | NUMBER | 원가단가 달러/원화 |
| **GOOS_QTY** | NUMBER | **상품수량** |
| DC_TYPE_CD_n / DC_RATE_n / DC_DOLR_AMT_n / DC_WON_AMT_n / DC_CUP_NO_n / DC_EVT_CD_n (n=1~3) | | 할인 1~3 |
| MANA_DC_EMP_NO / MANA_DC_CLS_CD / MANA_DC_RESN_CONT | | 관리자할인 |
| TOT_SALE_*, DC_*, NET_SELL_* | NUMBER | 금액 |
| **SALE_CNCL_YN** | CHAR | **판매취소여부 (라인단위)** |
| **RTN_QTY** | NUMBER | **반품수량 (부분반품 가능성)** |
| SALE_CNCL_RESN_CD | VARCHAR2 | 판매취소사유 (SA104) |
| SALE_CNCL_RCEP_QTY | NUMBER | 판매취소접수수량 |
| FEE_LVL_CD | VARCHAR2 | 수수료등급코드 (MA, MA003) |
| LGMT_PUR_YN / LQD_YN / FREE_YN | CHAR | 고액구매/액체류/(?)무상 여부 |
| SPSA_SER_NO / SPSA_SEQ / SPSA_YMON | | 특판 |
| OFLN_SETT_DC_* / ONLN_SETT_DC_* | NUMBER | 결제할인 |
| **STOC_STOR_CD / STOC_CORN_CD** | VARCHAR2 | **재고점 / 재고코너** |
| REFU_OBRK_YN | CHAR | (?) |
| RSVG_DOLR_AMT | NUMBER | (?)적립 달러금액 |
| TCMP_CD | VARCHAR2 | (?)통합업체코드 |

## SA0109D — 영업_매출상세(GWP)
**명세서 사진 없음.** SA0103D와 동일 키(COMP_CD, STOR_CD, SALE_DT, POS_NO, RCPT_NO, SEQ) + GWP코드 + 수량 구조로 추정. 컬럼 확인 후 `sql/02` GWP 부분 수정 필요.

## WM054L — 수불(일반상품) / WM053L — 수불(GWP)
**명세서 사진 없음.** 확인 필요 항목: 키(점/창고·코너/상품/일자 or 월), 기말수량 컬럼, 마감 기준(일마감/월마감),
보세구역·로케이션 단위 여부. 확인 후 `sql/06` C02 부분 작성.

## SA2000I — 영업_매출기본부속정보
COMP_CD, STOR_CD, SALE_DT, POS_NO, RCPT_NO, BILL_NO, BILL_BRCD, MG_CUST_CD, MG_CUST_RQMT_NO(?), NEW_CUST_TYPE_CD(신규고객유형), MG_ADDR_SEQ(MG주소순번), DELV_ADDR_1/2(배송주소), MBS_CD(멤버십코드), MBS_LVL_TYPE_CD, MBS_LVL_CD.
→ 재고 계산에는 **불필요**. (고객 쿼리 1에서 INNER JOIN 하고 있음 → 분석 문서 참고)

## MA0100I — 마스터_점코너구역정보

| 컬럼 | 설명 |
|---|---|
| COMP_CD (CHAR), STOR_CD, CORN_CD | 회사/점/코너 (코너코드: MA0100C) |
| SALE_CORN_RGN_CD | 매출코너구역코드 (MA9071C) |
| CORN_RGN_CD | 코너구역코드 (MA9070C) |
| AIRP_RGN_CD | 공항구역코드 |
| WH_CLS_CD | **창고구분코드** |
| OTSD_BUP_CD | 외부업체코드 (MA9072C) |
| AIRP_SHOP_NO | 공항매장번호 (MA0150M, MA, MA126) |
| SHOP_CLS_CD | 매장구분코드 (MA9087C) |

## MA0150M — 공통코드 기본 / MA0151D — 공통코드 상세

| MA0150M | MA0151D |
|---|---|
| COMP_CD, WRK_MDUL_CD(업무모듈, MA030), COMM_CTG_CD(공통분류코드), COMM_CTG_NM, COMM_PROP_NM_1~10(속성명), USE_YN, USR_MNGE_YN(사용자관리여부), COMM_CD_DNUM(코드자릿수), ALIN_SEQ_ORD(정렬순서), RMK | COMP_CD, WRK_MDUL_CD, COMM_CTG_CD, **COMM_CTG_DTL_CD**(상세코드), COMM_CTG_DTL_NM, **COMM_PROP_CONT_1~10**(속성값), RMK, USE_YN, ALIN_SEQ_ORD |

## BO0110M — 보세운송 기본(면장 헤더)

| 컬럼 | 타입 | 설명 / 코드 |
|---|---|---|
| COMP_CD, STOR_CD | | |
| **BOND_TRAN_MNGE_NO** | VARCHAR2 | 보세운송관리번호 (BO0110D 조인키) |
| **PMIT_CLS_CD** | VARCHAR2 | **면장구분코드 (MA0150M, WM, WM038)** |
| CHG_RPT_CLS_CD | VARCHAR2 | 정정신고구분코드 (MA, MA072) |
| CHG_BOND_TRAN_MNGE_NO | VARCHAR2 | 정정 보세운송관리번호 (**정정 시 중복 집계 위험**) |
| BOND_TRAN_GRP_NO | VARCHAR2 | 보세운송그룹번호 |
| TAKE_OUT_RPT_NO | VARCHAR2 | 반출신고번호 |
| LOAD_MNGE_NO | VARCHAR2 | 적재(?)관리번호 |
| BCA_TAKE_OUT_CD | VARCHAR2 | 인도장반출코드 |
| DEPA_PLAC_CD / ARRV_PLAC_CD | VARCHAR2 | 출발/도착 장소코드 |
| RPT_DT / PMIT_DT | VARCHAR2 | 신고일자 / 면장일자 |
| SND_CFM_DT / ARRV_CFM_DT | VARCHAR2 | 발송확인 / 도착확인 일자 |
| CFM_CSTM_WON_CD | VARCHAR2 | 확인세관원코드 (BO, BO039) |
| TRAN_ST_DT / TRAN_END_DT | VARCHAR2 | 운송 시작/종료 일자 |
| CAR_NO_CD | VARCHAR2 | 차량번호코드 (BO, BO028) |
| CT_QTY | NUMBER | 카톤수량 |
| **FIX_YN / DEL_YN / RPT_YN** | CHAR | **확정 / 삭제 / 신고 여부** |
| **EDI_RPT_NO**, EDI_RPT_DT, EDI_RPT_TM | VARCHAR2 | EDI신고번호(IFWM11M 조인키) / 일자 / 시간 |
| FTP_RPT_YN, FTP_RPT_DT, FTP_RPT_NO | | FTP 전송 |
| INFC_ID | VARCHAR2 | 인터페이스ID |

## BO0110D — 보세운송 상세(면장 ↔ 빌)

| 컬럼 | 타입 | 설명 / 코드 |
|---|---|---|
| COMP_CD, STOR_CD, BOND_TRAN_MNGE_NO | | BO0110M 조인키 |
| BOND_TRAN_SEQ | NUMBER | 보세운송순번 |
| **BILL_NO** | VARCHAR2 | 빌번호 (SA0100M 조인키) |
| BILL_PROC_CLS_CD | VARCHAR2 | 빌처리구분코드 (BO, BO015) |
| RCPT_NO | NUMBER | 영수증번호 |
| UDLV_RESN_CD | VARCHAR2 | 미인도사유코드 (BO, BO027) |
| DPAT_DT / DEPA_TM / OPEN_NM | VARCHAR2 | 출국일자/시간/편명 |
| BCA_CD | VARCHAR2 | 인도장코드 (MA, MA025) |
| **CT_NO** | NUMBER | **카톤번호 — 한 빌이 여러 카톤이면 여러 행 → 조인 시 수량 뻥튀기 위험** |
| PROC_DT | VARCHAR2 | 처리일자 |
| PSPT_NO, CUST_NM, NATI_CD(MA024) | | 고객정보(암호화) |
| RAMEND_TYPE | VARCHAR2 | (?)정정구분 |
| CHG_PSPT_NO, CHG_CUST_NM, CHG_NATI_CD | | 변경 고객정보 |

## IFWM11M — EDI 신고 인터페이스 (면장/보세운송)

| 컬럼 | 설명 / 코드 |
|---|---|
| COMP_CD (CHAR), **EDI_RPT_NO** | 조인키 |
| **EDI_DOC_STAT_CD** | EDI문서상태코드 (MA, MA083) — **'G1' = 확정통보** |
| EDI_DOC_CLS_CD | EDI문서구분코드 (MA, MA082) |
| CSTM_RPT_CLS_CD | 세관신고구분코드 |
| EDI_BCA_CLS_CD | EDI인도장구분코드 (MA, MA112) |
| CHG_RPT_CLS_CD / CHG_RPT_DT | 정정신고구분(MA072) / 정정신고일자 |
| BOND_GRN_CD | 보세구역코드 (MA, MA041) |
| ARRV_BOND_RGN_CD / VIA_BOND_RGN_CD | 도착 / 경유 보세구역코드 |
| ARRV_SHED_CD / DEPA_SHED_CD | 도착 / 출발 장치장코드 |
| ARRV_TRAN_BUP_CD / DEPA_TRAN_BUP_CD | 도착 / 출발 운송업체코드 |
| DELIVERY_TYPE (CHAR) | 인도구분 |
| EDI_RPT_DT, TRAN_END_DT | EDI신고일자, 운송종료일자 |
| DEL_YN (CHAR), INFC_ID | 삭제여부, 인터페이스ID |

## IFWM12M — EDI 신고 인터페이스 (반입신고)

| 컬럼 | 설명 / 코드 |
|---|---|
| COMP_CD (CHAR), **EDI_RPT_NO** | 조인키 (MK5010D.EDI_RPT_NO) |
| **EDI_DOC_CLS_CD** | EDI문서구분코드 (MA082) — 쿼리상 **'5KP'** |
| **CSTM_RPT_CLS_CD** | 세관신고구분코드 — **'B' 반품(인도후), 'R' 미인도물품재반입** |
| **EDI_DOC_STAT_CD** | EDI문서상태코드 (MA083) — **'F1' = 결과통보** |
| EDI_REF_NO | EDI참조번호 |
| CHG_RPT_CLS_CD | 정정신고구분 (MA072) |
| BOND_GRN_CD, ARRV_SHED_CD | 보세구역 / 도착장치장 |
| EDI_RPT_DT | EDI신고일자 |
| OVSE_ZIP_YN | 해외우편(국제우편)여부 |
| DEL_YN, INFC_ID | |

## MK5010D — 판매취소(회수) 상세

| 컬럼 | 설명 / 코드 |
|---|---|
| COMP_CD, STOR_CD, **BILL_NO** | SA0100M 조인키 |
| SACL_CLS_CD | 판매취소구분코드 |
| SACL_COMP_CD / SACL_STOR_CD / SACL_DT / SACL_POS_NO / SACL_RCPT_NO / SACL_BILL_NO | **판매취소 거래 키 (원매출과 다른 날짜일 수 있음)** |
| SACL_RCEP_DT | 판매취소접수일자 |
| GOOS_QTY, TOT_SACL_QTY, TOT_SACL_DOLR_AMT | 수량/취소수량/취소금액 |
| CARI_CLS_CD | (?)반입구분코드 |
| RCEP_PLAC_CLS_CD | 접수처구분코드 (MK, MK505) |
| EMS_NO | EMS번호 |
| COLL_DT / COLL_SER_NO | 회수일자 / 회수일련번호 |
| PMNT_DT / PMNT_SER_NO | 지급일자 / 지급일련번호 |
| **EDI_RPT_NO**, EDI_RPT_DT, EDI_FIX_DT, EDI_REF_NO, EDI_RPT_YN | EDI 신고 (IFWM12M 조인키) |
| UDLV_CARI_RPT_NO / _DT / UDLV_CARI_FIX_DT | **미인도반입 신고번호/일자/확정일자** |
| SALE_CNCL_YN | 판매취소여부 |
| SACL_PROC_CD | 판매취소처리코드 (MK, MK503) |
| SACL_STAT_CD | 판매취소상태코드 (MK, MK502) |
| SACL_FIX_YN | 판매취소확정여부 |
| CNCL_GOOS_CHOI_YN | 취소상품선택여부 (부분취소?) |
| SPTM_COLL_YN / POIN_COLL_YN / GWP_COLL_YN | 회수 여부 (?/포인트/GWP) |
| GWP_COLL_IPSB_RESN_CD | GWP회수불가사유코드 |
| SETT_CNCL_YN / REPY_SUSP_YN | 결제취소 / (?)환불보류 여부 |
| BCA_CD | 인도장코드 (MA025) |
| BOND_RCEP_DT / BOND_RCEP_TM / BOND_RCEP_USR_ID | 보세접수 일자/시간/접수자 |
| RMK | 비고 |

## WM0121L — 보세구역 장치장소별 세관신고 내역
(집계 프로시저 `SP_WMCM_CSTM_RPT_LIST_8` 생성)

| 컬럼 | 설명 / 코드 |
|---|---|
| COMP_CD | 회사 |
| BOND_GRN_STOC_MNG_NO | 보세구역재고관리번호 (시퀀스 SQ_WM0121L_SEQ) — PK 추정 |
| BOND_GRN_CD | 보세구역코드 (MA041) |
| SHED_CD | 장치장코드 |
| CSTM_RPT_WRK_CD | 세관신고작업코드 (MA, MA065) |
| CSTM_RPT_KIND_CD | 세관신고종류코드 (MA, MA062) |
| CHG_RPT_CLS_CD | 정정신고구분 (MA072) |
| REF_RPT_CLS_CD | 참고신고구분코드 (보세운송 신고코드) |
| PMIT_CLS_CD | 면장구분코드 (WM, WM038) |
| **GOOS_CD / CSTM_GOOS_CD / HS_CD** | 상품코드 / 세관상품코드 / HS코드 |
| CSTM_ITEM_CLS_CD | 세관물품구분코드 (MA, MA071) — **환급/비환급 구분 후보** |
| **CARI_QTY / TAKE_OUT_QTY** | **반입수량 / 반출수량** |
| BILL_NO | 빌번호 |
| EDI_RPT_NO / EDI_REPA_DT | EDI신고번호 / **EDI수리일자 (기준일 컷오프 컬럼 후보)** |
| NET_SALE_DOLR_AMT | 순매출달러금액 |
| TOT_YN | 집계유무 |

## WM0121S — 보세구역별 세관재고 수기집계
(집계 프로시저 `SP_WMCM_CSTM_RPT_LIST_5_SUM` 생성)

| 컬럼 | 설명 / 코드 |
|---|---|
| COMP_CD | |
| BOND_GRN_CD / SHED_CD | 보세구역 (MA041) / 장치장 |
| CSTM_ITEM_CLS_CD | 세관물품구분 (MA071) |
| CSTM_STOC_UNIT_CD | 세관재고단위코드 |
| CSTM_STOC_TOT_CLS_CD | 세관재고집계구분코드 (MA, MA077) |
| EDI_REPA_DT | EDI수리일자 |
| CARI_QTY / TAKE_OUT_QTY | 반입 / 반출 수량 |
| ACUM_CARI_QTY / ACUM_TAKE_OUT_QTY | **누적 반입 / 누적 반출 수량** |

> ⚠️ 사진상 WM0121S 에서 **GOOS_CD / HS_CD 컬럼이 보이지 않음**. "HS세관재고"가 HS코드 단위인지, 상품코드 단위인지가
> 마이그레이션 단위를 결정하므로 최우선 확인 필요. (HS 단위라면 상품 단위로 배분할 규칙이 별도로 필요)
