---
name: feedback-model-tier-lever
description: "모델 티어·effort 최적화의 실효 절감은 프로젝트당 $200 규모. 진짜 레버는 검증가능성 선투자이며, 실기기가 심판인 구간에서 모델 상향은 무효다."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 8ff84e1d-7bbc-4fd2-922d-ca0cbb4bf9f8
  modified: 2026-08-28T01:34:04.029Z
---

Claude Code 모델 배치(Opus/Sonnet/Fable × low~max)를 최적화해서 아낄 수 있는 돈은 **중형 프로젝트 1개당 $200 상한** — 시니어 1인 하루 인건비 수준이다. Swagger 전문(≈200K tok) 1회 통독도 Opus로 $1이다. **"조사 구간을 아끼는 것"은 경제적으로 무의미하고, 아껴서 필드를 놓치면 재작업이 그 100배다.**

모델을 고르기 전에 항상 먼저 물을 것: **"이 판단을 기계가 판정하는 실험으로 바꿀 수 있나?"** (원본 대조 게이트 / staging 실응답 / worktree 컴파일 / 강제 재현 빌드). 검증가능성이 올라가면 모델 티어는 저절로 한 칸 내려간다.

`max`·Fable 5·fast mode 는 기본 0칸이 옳다. 특히 **Fable 5 는 판정 작업에 쓰지 말 것** — raw CoT 를 반환하지 않아 판정 근거의 감사 비용을 사람에게 전가하고, "Opus 였어도 같았나"를 영원히 알 수 없다. [[reference-observable-guard]] 규율("관측할 수 없는 가드는 없는 가드")이 모델 선정에도 그대로 적용된다.

**Why:** 2026-08-28 Simple POS 신규 개발용 모델 운용 가이드를 12에이전트 워크플로로 설계하면서, 반박 에이전트가 "그냥 Opus 5 xhigh 로 다 하면 안 되나"를 공격했고 **전면 수용**됐다. 실측 근거 — appfit_order_agent 실패 이력 34건 중 최다·최고비용 유형이 하드웨어/OEM 실동작이었고 전부 실기기만이 정답이었다([[project_d2s_kds_32bit_only]], [[reference_rexod_label_printer_signals]]). 다중 파일 불변식 누락([[reference_shop_catalog_display_order]] 계열)은 모델 등급이 아니라 전수 열거로 막힌다.

**How to apply:** 모델 선정 질문을 받으면 티어 비교부터 하지 말고 ① 심판이 누구인지(사람/컴파일러/실기기) ② 검증가능성을 올릴 수 있는지를 먼저 답할 것. 비용 절감을 근거로 하위 티어를 권하려면 절감액을 실제로 계산해 제시할 것 — 대개 무시할 수준이라 근거가 안 된다. 판정형 배치는 "측정된 결론"이 아니라 "손실 비대칭에 근거한 기본값"이라고 정직하게 말할 것. 상세: `~/.claude/plans/simple-pos-groovy-naur.md`
