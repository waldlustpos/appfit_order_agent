/* ============================================================
   c4.js — 특화 뷰 공통 탭 헤더를 주입한다.
   각 뷰 HTML은 <header id="c4-hdr"></header> 하나만 두면 된다.
   뷰 추가/수정은 아래 VIEWS 배열만 고치면 전부 반영된다.
   ============================================================ */
(function () {
  const VIEWS = [
    { file: 'c4-order-flow.html',     label: '주문 흐름',     num: '01' },
    { file: 'c4-print-pipeline.html', label: '출력 파이프라인', num: '02' },
    { file: 'c4-ota-variants.html',   label: 'OTA·변형',      num: '03' },
  ];

  const cur = location.pathname.split('/').pop() || '';
  const host = document.getElementById('c4-hdr');
  if (!host) return;

  const tabs = VIEWS.map(v => {
    const active = v.file === cur ? ' active' : '';
    return `<a class="tab${active}" href="${v.file}"><span class="ti">${v.num}</span>${v.label}</a>`;
  }).join('');

  host.className = 'c4hdr';
  host.innerHTML =
    `<a class="home" href="../c4core-context.html">&larr; Context</a>` +
    `<span class="brand">C4 · Order Agent</span>` +
    `<div class="tabs">${tabs}</div>`;
})();
