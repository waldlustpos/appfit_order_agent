# 기능 소개 문서 안내

> **이 문서의 내용은 [docs/guide/appfit-agent-guide.html](guide/appfit-agent-guide.html) 로 이관되었습니다.**
>
> 점주·브랜드 담당자에게 배포하는 안내서(단일 HTML, 브라우저에서 A4 PDF 저장 가능)가 정본이며,
> 기능·화면·설정 설명은 그쪽만 갱신한다. 여기에 내용을 다시 적으면 두 벌 관리가 되므로 금지.

## 배경 (내부 참고용)

주문접수에이전트는 별도 기획·디자인 없이 매머드커피 초기 버전을 토대로, 운영 경험과
매머드커피 및 타 브랜드 요구사항을 종합적으로 반영하며 진행되어온 프로젝트다.

## 안내서 갱신이 필요한 변경

아래 성격의 변경이 있으면 `docs/guide/appfit-agent-guide.html` 도 함께 갱신한다.

- 설정 화면 항목 추가/삭제/문구 변경 (`lib/i18n/strings_ko.i18n.json` 의 `settings.*`)
- 주문 상태 전이 버튼·취소 사유·조리 시간 선택지 변경 (`lib/widgets/order/order_detail_popup.dart`)
- 프린터 지원 모델 추가 (`settings.label_printer.desc` 등)
- 업데이트 채널 정책 변경 ([RELEASE.md](RELEASE.md))
- 화면(탭·모드) 구성 변경
