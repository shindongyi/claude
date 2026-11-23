# 면세점 기초재고 마이그레이션

| 문서 | 내용 |
|---|---|
| [docs/01_table_spec.md](docs/01_table_spec.md) | 관련 테이블 명세 (사진 판독본, 확인 쿼리 포함) |
| [docs/02_common_codes.md](docs/02_common_codes.md) | BO014 상품위치 / BO015 빌상태 / WM038 면장구분 등 코드, 교환권 정의 |
| [docs/03_query_analysis.md](docs/03_query_analysis.md) | 고객 제공 쿼리(`재고관련_정리.sql`) 분석 및 버그 |
| [docs/04_migration_plan.md](docs/04_migration_plan.md) | 기초재고 규칙 매트릭스, 진행 절차, 고객 확인사항, 리허설 계획 |
| [docs/05_todo_and_questions.md](docs/05_todo_and_questions.md) | 내가 할 일 체크리스트, 고객 문의 목록 |
| [docs/06_findings.md](docs/06_findings.md) | 조회 결과와 그로부터 확인된 사실 |
| [docs/07_declaration_format.md](docs/07_declaration_format.md) | 최종 산출물: 세관 물품반입검사신청서(Z/Y) 양식과 매핑 |

| SQL (Oracle, 초안) | 내용 |
|---|---|
| sql/01_staging_ddl.sql | 스테이징/매핑 테이블 |
| sql/02_common_valid_sale.sql | 판매취소 아닌 정상매출 상세 뷰 (상품/GWP) |
| sql/03_exchange_plus.sql | C03 교환권 (+) |
| sql/04_h_reentry_minus.sql | C04 H신고 재반입 교환권 (−) — 고객 쿼리 수정본 |
| sql/05_undelivered_minus.sql | C05 미인도반입 교환권 (−) — 고객 쿼리 수정본 |
| sql/06_cstm_stock_and_subul.sql | C01 HS세관재고, C02 수불, 환급분리·구코드 변환, 최종 집계 |
| sql/07_verify.sql | 검증/대사 쿼리 |
| sql/08_declaration_output.sql | 세관 신고 Header/Detail 생성 (스테이징) |
| sql/10_one_shot.sql | **한방 쿼리 3종** (① 상품 Z ② GWP Z ③ 미인도 Y) — 스테이징 없이 신고 Detail 직전 결과 |
| **sql/11_insert_final.sql** | **최종 INSERT 3종** (상품 Z / GWP Z / 미인도 Y) — 한방 쿼리 + 품목정보 + 신고번호로 SR_ItemCarryIn_H/D 에 바로 INSERT |
| sql/09_insert_target.sql | SR_ItemCarryIn_H / _D 에 INSERT (같은 DB: INSERT…SELECT / 다른 DB: INSERT 문 생성) |

실행 순서 (한방 방식): 10 SELECT 로 점검 → 11 INSERT

실행 순서 (단계 방식): 01 → 02 → (매핑표 적재) → 06의 C01/C02 → 03 → 04 → 05 → 06 변환·집계 → 07 → 08 → 09
