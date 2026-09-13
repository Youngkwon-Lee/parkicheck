# Assessment Storage Plan

## Goal

이 프로젝트에서 평가 데이터를 저장할 때, `평가도구 이름`이 아니라 `데이터 형태`를 기준으로 저장 위치를 결정한다.

## Current Buckets

### 1. Form-style assessments

설문형, 체크리스트형, 총점 중심 평가는 기존 공통 평가 테이블에 저장한다.

Examples:

- `BBS`
- `NPRS`
- `ODI`
- `PHQ-9`
- `TUG` when only total time / summary score is recorded
- `Y-Balance` when only composite or direction summary scores are recorded

Recommended shape:

- `assessment_form_responses`
- key fields:
  - `subject_person_id`
  - `performer_person_id`
  - `form_template_id`
  - `responses`
  - `total_score`
  - `assessment_date`
  - `source_type`
  - `organization_id`
  - `encounter_id`

### 2. Structured pre-visit intake

사전문진, 초진 문진처럼 문항은 있지만 임상 intake 자체가 독립 도메인인 경우 intake 전용 구조를 사용한다.

Examples:

- chief complaint
- medications
- red flags
- psychosocial context

Recommended shape:

- `previsit_intakes`

### 3. Quantitative session measurements

세션 중 측정된 정량값이나 요약 metric은 `observations`에 저장한다.

Examples:

- pain
- ROM
- MMT
- manual or device-derived simple values
- shuttle run stage / total time / HR if treated as session observations

### 4. Sensor / vision / signal-native assessments

센서, 비디오, 시계열, 파형, frequency/variability/amplitude 같은 상세 metric이 핵심인 평가는 전용 결과 테이블을 둔다.

Examples:

- finger tapping AI analysis
- tremor analysis
- gait motion metrics
- posture / facial expression computer vision outputs

Recommended shape:

- dedicated result table per metric family
- this project: `updrs_results`

## Why finger-tap should be dedicated

Current finger-tap payload is not a questionnaire response. It stores:

- `score`
- `raw_score`
- `n_taps`
- `frequency`
- `arrests`
- `iti_cv`
- `max_amplitude`
- `fatigability`
- `confidence`
- `duration_sec`
- `factors.test_type`

This is easier to query, chart, and aggregate in a dedicated table than inside generic `responses jsonb`.

## Practical rule

- If the data is mainly `questions -> answers -> total score`, use `assessment_form_responses`.
- If the data is mainly `metrics over time or signal-derived features`, use a dedicated results table.
- If both are useful, store:
  - a high-level summary event in `assessment_form_responses`
  - detailed metrics in a dedicated table

## Suggested mapping

| Assessment | Default home | Notes |
| --- | --- | --- |
| BBS | `assessment_form_responses` | total score + item scores |
| TUG | `assessment_form_responses` or `observations` | use form if summary only, observation if single metric |
| Y-Balance | `assessment_form_responses` | store composite / directional scores in responses |
| Shuttle run | `observations` or dedicated table | depends on whether raw stage/HR/time streams are needed |
| Finger tapping AI | `updrs_results` | detailed vision metrics |
| Tremor / gait CV | `updrs_results` or another motion table | signal-native output |

## Status in this repo

- App code already writes finger-tap history to `updrs_results`
- `updrs_results` migration exists in `supabase/migrations/20260526031059_create_updrs_results.sql`
- Admin aggregation exists in `supabase/migrations/20260526031115_admin_get_stats.sql`
- Remote `moai_web` still needs the migration applied
