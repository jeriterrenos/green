// Gaveta inferior (bottom sheet) do celular: recolhida / meio / cheia, arrastável, com abas — PLANO § 3.2
import { estado, ouvir } from '../estado.js';
import { desempilhar, empilhar } from './navegacao.js';

const POSICOES = ['recolhida', 'meio', 'cheia'];

export function iniciarGaveta(painel, alca, cabeca, abas) {
  let pos = 'recolhida';
  const fecharPorVoltar = () => definir('recolhida', true);
  let empilhada = false;

  function alturaDe(p) {
    return p === 'recolhida' ? 0 : null;
  }

  function definir(nova, porVoltar = false) {
    if (estado.desktop) return;
    pos = nova;
    painel.dataset.pos = nova;
    painel.style.height = '';
    if (nova !== 'recolhida' && !empilhada) {
      empilhar(fecharPorVoltar);
      empilhada = true;
    } else if (nova === 'recolhida' && empilhada) {
      empilhada = false;
      if (!porVoltar) desempilhar(fecharPorVoltar);
    }
  }

  // Arrastar pela alça ou pelo cabeçalho
  let inicioY = null;
  let alturaInicial = 0;
  let moveu = false;
  function aoPressionar(e) {
    if (estado.desktop || e.target.closest('button, a')) return;
    inicioY = e.clientY;
    alturaInicial = painel.getBoundingClientRect().height;
    moveu = false;
    painel.classList.add('arrastando');
    e.currentTarget.setPointerCapture(e.pointerId);
  }
  function aoMover(e) {
    if (inicioY == null) return;
    const dy = e.clientY - inicioY;
    if (Math.abs(dy) > 6) moveu = true;
    painel.style.height = `${Math.max(96, alturaInicial - dy)}px`;
  }
  function aoSoltar(e) {
    if (inicioY == null) return;
    const dy = e.clientY - inicioY;
    inicioY = null;
    painel.classList.remove('arrastando');
    const i = POSICOES.indexOf(pos);
    if (!moveu) definir(POSICOES[(i + 1) % POSICOES.length]);
    else if (dy < -40) definir(POSICOES[Math.min(i + (dy < -260 ? 2 : 1), 2)]);
    else if (dy > 40) definir(POSICOES[Math.max(i - (dy > 260 ? 2 : 1), 0)]);
    else definir(pos);
  }
  for (const alvo of [alca, cabeca]) {
    alvo.addEventListener('pointerdown', aoPressionar);
    alvo.addEventListener('pointermove', aoMover);
    alvo.addEventListener('pointerup', aoSoltar);
    alvo.addEventListener('pointercancel', aoSoltar);
  }

  // Abas Dados · Etapas · Histórico
  abas.addEventListener('click', (e) => {
    const b = e.target.closest('[data-aba]');
    if (!b) return;
    trocarAba(b.dataset.aba);
    if (pos === 'recolhida') definir('meio');
  });
  function trocarAba(nome) {
    abas.querySelectorAll('[data-aba]').forEach((x) => x.setAttribute('aria-selected', String(x.dataset.aba === nome)));
    painel.querySelectorAll('.aba').forEach((s) => s.classList.toggle('ativa', s.id === `aba-${nome}`));
  }

  ouvir((_, p) => {
    if ('desktop' in p && estado.desktop && empilhada) {
      empilhada = false;
      desempilhar(fecharPorVoltar);
    }
  });

  painel.dataset.pos = pos;
  return {
    abrir: (p = 'meio') => definir(p),
    recolher: () => definir('recolhida'),
    trocarAba,
    /** Altura que a gaveta cobre sobre o mapa (para o mapa não esconder o lote focado). */
    alturaCoberta: () => {
      if (estado.desktop) return 0;
      const alvo = { recolhida: 0.0, meio: 0.55, cheia: 0.9 }[pos];
      return alvo ? Math.round(window.innerHeight * alvo) : painel.getBoundingClientRect().height;
    },
    get pos() {
      return pos;
    },
    alturaDe,
  };
}
