---
name: reference-cloudflare-worker-traps
description: Cloudflare Workers/D1 첫 배포에서 밟은 함정 — 원클릭 Access가 기기 경로까지 차단, d1 create가 바인딩을 덧붙임
metadata:
  type: reference
---

`appfit-fleet` 첫 배포(2026-07-31)에서 실제로 막혔던 것들. 상세는 그 레포 `README.md` 의 "첫 배포에서 실제로 막혔던 것들".

**workers.dev 원클릭 Access 는 호스트네임 전체를 잠근다.** Workers 대시보드 Settings → Domains & Routes 의 "Enable Cloudflare Access" 는 경로를 가리지 않아 기기용 REST 경로까지 302 로 막는다. 브라우저 SSO 를 못 하는 클라이언트(매장 기기)가 있으면 켜면 안 된다. 대시보드는 멀쩡해 보이고 기기만 조용히 사라져서 원인 찾기가 어렵다. 확인은 `curl -o /dev/null -w '%{http_code}' <worker>/v1/...` → 302 면 Access. 꼭 쓰려면 Path 를 지정한 Access 앱을 Bypass/Everyone 으로 하나 더 만든다(더 구체적인 경로가 우선).

**`wrangler d1 create` 는 기존 바인딩을 교체하지 않고 덧붙인다.** 같은 `database_name` 이 둘이 되어 `--remote` 조회가 placeholder id 를 집으면 `[code: 7404] could not be found`. 자동 추가 항목은 바인딩 이름도 다르고(코드가 `env.DB` 면 런타임 파손) `"remote": true` 가 붙어 **`wrangler dev` 가 운영 D1 에 직접 붙는다**. 항목은 하나만 유지할 것.

**`wrangler secret put` 이 Worker 를 먼저 만든다.** 배포 전에 시크릿을 넣으면 스텁 Worker 가 생성되고 `deployments list` 에 버전이 잡혀 배포된 것처럼 보인다. 실제 코드 배포는 `wrangler deploy`.

**무료 티어 예산은 기기와 대시보드가 나눠 쓴다.** Workers 100,000요청/일, D1 쓰기 100,000행/일. 대시보드 3초 폴링을 하루 종일 켜두면 28,800요청으로 기기 20대분을 혼자 태운다 — 평소 15초 + 진행 중에만 3초 + 탭 숨김 시 중단이 필요하다.

관련: [[project-fleet-monitoring]]
