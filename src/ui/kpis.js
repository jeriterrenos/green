// KPIs (cards no desktop, chips no celular) e legenda do mapa — PLANO § 8.3
import { FAIXAS, ORDEM_FAIXAS } from '../config.js';
import { atualizar, estado, ouvir } from '../estado.js';
import { esc, icone } from '../util/html.js';

function contar() {
  const n = Object.fromEntries(ORDEM_FAIXAS.map((f) => [f, 0]));
  for (const f of estado.lotes?.features ?? []) n[f.properties.faixa]++;
  return n;
}

function amostra(faixa) {
  const f = FAIXAS[faixa];
  return `<span class="amostra ${f.tracejado ? 'amostra-tracejada' : ''}" style="--cor:${f.cor}"></span>`;
}

export function iniciarKpis(nav, legenda) {
  function render() {
    const n = contar();
    const total = estado.lotes?.features.length ?? 0;
    nav.innerHTML =
      ORDEM_FAIXAS.map(
        (k) => `
        <button type="button" class="kpi" data-faixa="${k}" aria-pressed="${estado.filtroFaixa === k}" style="--cor:${FAIXAS[k].cor}">
          ${amostra(k)}
          <span class="kpi-rotulo">${esc(FAIXAS[k].rotulo)}</span>
          <strong class="kpi-valor">${n[k]}</strong>
        </button>`,
      ).join('') +
      `<button type="button" class="kpi kpi-total" data-faixa="" aria-pressed="false">
         ${icone('apps')}<span class="kpi-rotulo">Total</span><strong class="kpi-valor">${total}</strong>
       </button>`;

    legenda.innerHTML = `
      <button type="button" class="legenda-botao" aria-expanded="${legenda.classList.contains('aberta')}">${icone('legend_toggle')} Legenda</button>
      <ul class="legenda-lista">
        ${ORDEM_FAIXAS.map((k) => `<li>${amostra(k)} ${esc(FAIXAS[k].rotulo)} <b>${n[k]}</b></li>`).join('')}
      </ul>`;
  }

  nav.addEventListener('click', (e) => {
    const b = e.target.closest('[data-faixa]');
    if (!b) return;
    const f = b.dataset.faixa || null;
    atualizar({ filtroFaixa: estado.filtroFaixa === f ? null : f });
  });
  legenda.addEventListener('click', (e) => {
    const b = e.target.closest('.legenda-botao');
    if (!b) return;
    const aberta = legenda.classList.toggle('aberta');
    b.setAttribute('aria-expanded', String(aberta));
  });

  ouvir((_, p) => {
    if ('lotes' in p || 'filtroFaixa' in p) render();
  });
  render();
}
