import './styles.css';
import { DESKTOP_MQ } from './config.js';
import { dados, fonte } from './data/index.js';
import { atualizar, estado, ouvir } from './estado.js';
import { criarMapa } from './map/mapa.js';
import { proximaEtapa } from './regras.js';
import { configurarAcoes } from './ui/acoes.js';
import { iniciarBusca } from './ui/busca.js';
import { iniciarFluxo } from './ui/fluxo.js';
import { iniciarGaveta } from './ui/gaveta.js';
import { iniciarKpis } from './ui/kpis.js';
import { iniciarMenu } from './ui/menu.js';
import { iniciarPainel } from './ui/painel.js';
import { toast } from './ui/toast.js';

const $ = (id) => document.getElementById(id);

async function iniciar() {
  const demo = !dados.exigeLogin;
  $('ano').textContent = new Date().getFullYear();

  const sessao = await dados.sessaoAtual(); // F5: sem sessão → tela de login
  atualizar({ perfil: sessao.perfil, etapas: await dados.listarEtapas() });

  // Layout: desktop (painel lateral + fluxo horizontal) × celular (gaveta + fluxo vertical)
  const mq = window.matchMedia(DESKTOP_MQ);
  const blocoEtapas = $('bloco-etapas');
  const aplicarLayout = () => {
    const desktop = mq.matches;
    (desktop ? $('area-etapas-desktop') : $('aba-etapas')).append(blocoEtapas);
    atualizar({ desktop });
  };

  const gaveta = iniciarGaveta($('painel'), $('gaveta-alca'), $('painel-cabeca'), $('abas'));
  const mapa = criarMapa($('mapa'), {
    aoSelecionar: (id) => selecionar(id, { focar: false }),
    paddingInferior: () => gaveta.alturaCoberta(),
  });

  iniciarKpis($('kpis'), $('legenda'));
  iniciarPainel({ cabecaEl: $('painel-cabeca'), dadosEl: $('aba-dados'), historicoEl: $('aba-historico') });
  iniciarFluxo($('fluxo'), $('documentos'));
  iniciarMenu($('menu-usuario'), { demo });
  iniciarBusca($('busca'), $('btn-busca-movel'), (id) => selecionar(id, { focar: true }));

  mq.addEventListener('change', aplicarLayout);
  aplicarLayout();

  ouvir((_, p) => {
    if ('lotes' in p) mapa.atualizarDados(estado.lotes);
    if ('filtroFaixa' in p) mapa.filtrarFaixa(estado.filtroFaixa);
  });

  function etapaPadrao() {
    const lote = estado.detalhe?.lote;
    if (!lote?.tem_processo) return 1;
    return proximaEtapa({ temProcesso: true, ultimaEtapa: lote.ultima_etapa }) ?? lote.ultima_etapa;
  }

  async function selecionar(id, { focar }) {
    mapa.selecionar(id);
    if (id == null) {
      atualizar({ loteId: null, detalhe: null, etapaSel: null });
      gaveta.recolher();
      return;
    }
    const detalhe = await dados.obterLote(id);
    // Ao trocar de lote as etapas voltam sempre recolhidas (nenhuma aberta)
    atualizar({ loteId: id, detalhe, etapaSel: null });
    if (!estado.desktop && gaveta.pos === 'recolhida') gaveta.abrir('meio');
    // No celular a gaveta cobre parte do mapa: sempre recentraliza o lote na área visível
    if (focar || !estado.desktop) requestAnimationFrame(() => mapa.focar(id));
  }

  async function recarregar() {
    const lotes = await dados.listarLotes();
    atualizar({ lotes });
    if (estado.loteId != null) {
      const etapaAntes = estado.etapaSel;
      const detalhe = await dados.obterLote(estado.loteId);
      atualizar({ detalhe });
      // Depois de um OK, se havia etapa aberta, abre a próxima; se estava tudo recolhido, continua recolhido
      atualizar({ etapaSel: etapaAntes === null ? null : etapaPadrao() });
    }
  }
  configurarAcoes(recarregar);
  await recarregar();

  if (import.meta.env.DEV) window.__gt = { mapa, estado }; // apoio a testes automatizados locais

  // Só mostra a página com o mapa desenhado e as fontes (texto e ícones) carregadas — no máximo ~4 s
  const fontes = Promise.all([
    document.fonts.load('24px "Material Symbols Rounded"', 'check'),
    document.fonts.load('600 16px Outfit'),
  ]).catch(() => {});
  await Promise.race([Promise.all([mapa.pronto, fontes]), new Promise((r) => setTimeout(r, 4000))]);
  mostrarPagina();

  if (fonte !== 'mock') toast('Fonte de dados ainda não implementada; exibindo a demonstração.', 'erro');
}

/** Remove a tela de carregamento (com um pequeno esmaecimento) e exibe a página já montada. */
function mostrarPagina() {
  const html = document.documentElement;
  html.classList.remove('carregando');
  html.classList.add('pronto');
  setTimeout(() => document.querySelector('.abertura')?.remove(), 400);
}

iniciar().catch((e) => {
  mostrarPagina();
  console.error(e);
  toast(e.message || 'Erro ao iniciar o portal.', 'erro');
});
