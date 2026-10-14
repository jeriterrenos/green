// Busca por lote, comprador ou matrícula — PLANO § 8.4
import { FAIXAS } from '../config.js';
import { estado } from '../estado.js';
import { esc, icone } from '../util/html.js';
import { normalizar } from '../util/formatos.js';
import { desempilhar, empilhar } from './navegacao.js';

const MAX = 8;

export function iniciarBusca(caixa, botaoMovel, aoEscolher) {
  caixa.innerHTML = `
    <div class="busca-campo">
      ${icone('search')}
      <input type="search" placeholder="Buscar lote, comprador ou matrícula" aria-label="Buscar lote, comprador ou matrícula"
             autocomplete="off" role="combobox" aria-expanded="false" aria-controls="busca-lista">
      <button type="button" class="icone-btn busca-fechar" aria-label="Fechar busca">${icone('close')}</button>
    </div>
    <ul id="busca-lista" class="busca-lista" role="listbox" hidden></ul>`;
  const input = caixa.querySelector('input');
  const lista = caixa.querySelector('ul');
  let resultados = [];
  let ativo = -1;

  function buscar() {
    const q = normalizar(input.value.trim());
    if (!q) return [];
    return (estado.lotes?.features ?? [])
      .map((f) => f.properties)
      .filter((p) => [p.codigo, p.adquirente_nome, p.matricula].some((v) => normalizar(v).includes(q)))
      .slice(0, MAX);
  }

  function render() {
    resultados = buscar();
    ativo = resultados.length ? 0 : -1;
    lista.hidden = !input.value.trim();
    input.setAttribute('aria-expanded', String(!lista.hidden));
    lista.innerHTML = resultados.length
      ? resultados
          .map(
            (p, i) => `
          <li role="option" data-id="${p.id}" aria-selected="${i === ativo}">
            <span class="amostra ${FAIXAS[p.faixa].tracejado ? 'amostra-tracejada' : ''}" style="--cor:${FAIXAS[p.faixa].cor}"></span>
            <span class="busca-item"><b>Lote ${esc(p.codigo)}</b> · Mat. ${esc(p.matricula ?? '—')}
              <small>${esc(p.adquirente_nome ?? 'Disponível')}</small></span>
          </li>`,
          )
          .join('')
      : '<li class="busca-vazio">Nenhum lote encontrado</li>';
  }

  function marcar(i) {
    ativo = i;
    lista.querySelectorAll('[role="option"]').forEach((li, j) => li.setAttribute('aria-selected', String(j === i)));
  }

  function escolher(id) {
    input.value = '';
    lista.hidden = true;
    input.setAttribute('aria-expanded', 'false');
    fecharMovel();
    aoEscolher(id);
  }

  input.addEventListener('input', render);
  input.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown' && resultados.length) marcar((ativo + 1) % resultados.length);
    else if (e.key === 'ArrowUp' && resultados.length) marcar((ativo - 1 + resultados.length) % resultados.length);
    else if (e.key === 'Enter' && ativo >= 0) escolher(resultados[ativo].id);
    else if (e.key === 'Escape') {
      input.value = '';
      render();
      fecharMovel();
      return;
    } else return;
    e.preventDefault();
  });
  lista.addEventListener('click', (e) => {
    const li = e.target.closest('[data-id]');
    if (li) escolher(Number(li.dataset.id));
  });
  document.addEventListener('click', (e) => {
    if (!caixa.contains(e.target) && e.target !== botaoMovel && !botaoMovel.contains(e.target)) lista.hidden = true;
  });

  // Celular: a busca abre como sobreposição em tela cheia
  const fecharPorVoltar = () => fecharMovel(true);
  function abrirMovel() {
    caixa.classList.add('aberta');
    empilhar(fecharPorVoltar);
    input.focus();
  }
  function fecharMovel(porVoltar = false) {
    if (!caixa.classList.contains('aberta')) return;
    caixa.classList.remove('aberta');
    if (!porVoltar) desempilhar(fecharPorVoltar);
  }
  botaoMovel.addEventListener('click', abrirMovel);
  caixa.querySelector('.busca-fechar').addEventListener('click', () => fecharMovel());
}
