// Painel do lote: cabeçalho, dados e histórico — PLANO § 8.5
import { FAIXAS } from '../config.js';
import { ehAdmin, estado, ouvir } from '../estado.js';
import { percentual, TOTAL_ETAPAS } from '../regras.js';
import { esc, icone } from '../util/html.js';
import { data, dataHora, m2, metros, telefoneLink, whatsapp } from '../util/formatos.js';
import { ESTADOS_CIVIS, iconeWhatsapp, REGIMES_BENS } from './rotulos.js';
import { editar, iniciarProcesso } from './acoes.js';

const ROTULOS_CAMPOS = {
  adquirentes: 'Adquirente(s)',
  bci_inscricao: 'BCI',
  data_ultimo_contato: 'Último contato',
  observacoes: 'Observações',
};

function selo(faixa) {
  const f = FAIXAS[faixa];
  return `<span class="selo selo-${faixa}" style="--cor:${f.cor}">${esc(f.rotulo)}</span>`;
}

function linha(rotulo, valor, html = false) {
  return `<div class="linha"><dt>${esc(rotulo)}</dt><dd>${html ? valor : esc(valor ?? '—')}</dd></div>`;
}

function progresso(lote) {
  const p = percentual(lote.ultima_etapa);
  return `<div class="progresso" role="progressbar" aria-valuenow="${p}" aria-valuemin="0" aria-valuemax="100"
            aria-label="Progresso da transferência"><span style="width:${p}%"></span></div>`;
}

function nomeEtapa(id) {
  return estado.etapas.find((e) => e.id === id)?.nome ?? '';
}

function cabeca(lote) {
  if (!lote) {
    return `<div class="painel-vazio">${icone('touch_app')}<p>Toque ou clique em um lote no mapa para ver os dados do imóvel.</p></div>`;
  }
  const etapaTxt = lote.tem_processo
    ? `Etapa ${lote.ultima_etapa}/${TOTAL_ETAPAS}`
    : lote.faixa === 'disponivel'
      ? 'Sem adquirente'
      : 'Processo não iniciado';
  return `
    <div class="cabeca-topo">
      <div>
        <h2 class="cabeca-titulo">Lote ${esc(lote.codigo)}</h2>
        <p class="cabeca-sub">Matrícula ${esc(lote.matricula ?? '—')} · ${esc(lote.adquirente_nome ?? 'Disponível')}</p>
      </div>
      ${selo(lote.faixa)}
    </div>
    <div class="cabeca-progresso">${progresso(lote)}<span>${esc(etapaTxt)}</span></div>`;
}

function telefoneHtml(tel) {
  if (!tel) return '—';
  const zap = whatsapp(tel);
  return `<a href="${esc(telefoneLink(tel))}">${esc(tel)}</a>${
    zap ? ` <a class="link-zap" href="${esc(zap)}" target="_blank" rel="noopener" aria-label="Conversar no WhatsApp" title="WhatsApp">${iconeWhatsapp()}</a>` : ''
  }`;
}

function secaoAdquirente(a, ordem, total) {
  const civil = ESTADOS_CIVIS[a.estado_civil];
  const pj = a.tipo_pessoa === 'PJ';
  const conjuge = a.conjuge_nome
    ? `${esc(a.conjuge_nome)}${a.conjuge_cpf ? `<br><small>CPF ${esc(a.conjuge_cpf)}</small>` : ''}`
    : null;
  return `
    <section class="secao">
      <h3>${icone(pj ? 'apartment' : 'person')}Adquirente${total > 1 ? ` ${ordem}` : ''}</h3>
      <dl>
        ${linha('Nome', a.nome)}
        ${linha(pj ? 'CNPJ' : 'CPF', a.documento)}
        ${pj ? '' : linha('RG', [a.rg, a.rg_orgao].filter(Boolean).join(' · ') || null)}
        ${pj ? '' : linha('Estado civil', civil ? `${civil}${a.regime_bens ? ` — ${REGIMES_BENS[a.regime_bens] ?? a.regime_bens}` : ''}` : null)}
        ${conjuge ? linha('Cônjuge', conjuge, true) : ''}
        ${a.profissao ? linha('Profissão', a.profissao) : ''}
        ${a.nacionalidade ? linha('Nacionalidade', a.nacionalidade) : ''}
        ${linha('Telefone', telefoneHtml(a.telefone), true)}
        ${a.email ? linha('E-mail', `<a href="mailto:${esc(a.email)}">${esc(a.email)}</a>`, true) : ''}
        ${a.endereco ? linha('Endereço', a.endereco) : ''}
      </dl>
    </section>`;
}

function secaoDados(lote) {
  if (!lote) return '';
  const disponivel = lote.faixa === 'disponivel';
  const etapaAtual = lote.tem_processo
    ? `${lote.ultima_etapa} de ${TOTAL_ETAPAS}${lote.ultima_etapa ? ` — ${esc(nomeEtapa(lote.ultima_etapa))}` : ' — aguardando etapa 1'}`
    : '—';

  const acoes = ehAdmin()
    ? `<div class="painel-acoes">
         <button type="button" class="btn btn-secundario" data-acao="editar">${icone('edit')}Editar cadastro</button>
         ${lote.faixa === 'sem_processo' ? `<button type="button" class="btn btn-primario" data-acao="iniciar">${icone('play_arrow')}Iniciar processo</button>` : ''}
       </div>`
    : '';

  const bciBadge = lote.bci_inscricao
    ? `<span class="selo-sucesso">${esc(lote.bci_inscricao)}</span>`
    : '<span class="selo-pendente">Ainda não cadastrado</span>';

  const itbiStatusBadge = lote.status_itbi
    ? (lote.status_itbi.toLowerCase().includes('quitado') || lote.status_itbi.toLowerCase().includes('pago')
        ? `<span class="selo-sucesso">${esc(lote.status_itbi)}</span>`
        : `<span class="selo-pendente">${esc(lote.status_itbi)}</span>`)
    : '';

  return `
    ${acoes}
    <section class="secao">
      <h3>${icone('badge')}Identificação do Imóvel</h3>
      <dl>
        ${linha('Lote', lote.codigo)}
        ${lote.quadra ? linha('Quadra', lote.quadra) : ''}
        ${linha('Matrícula individual', lote.matricula)}
        ${lote.matricula_mae ? linha('Matrícula-mãe', lote.matricula_mae) : ''}
        ${lote.gleba ? linha('Gleba de origem', lote.gleba) : ''}
        ${lote.cartorio ? linha('Cartório competente', lote.cartorio) : ''}
        ${linha('Área calculada (GIS)', m2(lote.area_m2))}
        ${linha('Perímetro', metros(lote.perimetro_m))}
        ${lote.area_projeto_m2 ? linha('Área de projeto', m2(lote.area_projeto_m2)) : ''}
        ${lote.dif_area_m2 && Math.abs(lote.dif_area_m2) > 0.1 ? linha('Divergência de área', m2(lote.dif_area_m2)) : ''}
      </dl>
    </section>
    ${
      disponivel
        ? `<section class="secao"><h3>${icone('person')}Adquirente</h3>
             <p class="selo-info">${icone('sell')} Lote disponível para venda — sem adquirente.</p></section>`
        : lote.adquirentes.map((a, i) => secaoAdquirente(a, i + 1, lote.adquirentes.length)).join('')
    }
    ${
      disponivel
        ? ''
        : `<section class="secao">
            <h3>${icone('account_balance')}Trâmite Municipal (SEFIN Cruz)</h3>
            <dl>
              ${linha('Inscrição / BCI', bciBadge, true)}
              ${lote.numero_requisicao || lote.protocolo_prefeitura ? linha('Requisição / Protocolo', lote.numero_requisicao || lote.protocolo_prefeitura) : ''}
              ${lote.atendente_prefeitura ? linha('Atendente', lote.atendente_prefeitura) : ''}
              ${itbiStatusBadge ? linha('Situação do ITBI', itbiStatusBadge, true) : ''}
              ${lote.data_itbi ? linha('Data do ITBI', data(lote.data_itbi)) : ''}
            </dl>
          </section>
          <section class="secao">
            <h3>${icone('timeline')}Acompanhamento do Processo</h3>
            <dl>
              ${linha('Situação atual', selo(lote.faixa), true)}
              ${linha('Etapa atual', etapaAtual, true)}
              ${linha('Progresso', `${progresso(lote)} <span class="pct">${percentual(lote.ultima_etapa)}%</span>`, true)}
              ${linha('Data da solicitação', data(lote.data_solicitacao ?? lote.data_compra))}
              ${lote.data_ultimo_contato ? linha('Último contato', data(lote.data_ultimo_contato)) : ''}
              ${lote.observacoes && String(lote.observacoes).trim() !== '' ? linha('Observações', lote.observacoes) : ''}
            </dl>
          </section>`
    }`;
}

function textoHistorico(h) {
  const n = h.etapa_id;
  switch (h.acao) {
    case 'iniciar_processo':
      return 'Processo iniciado';
    case 'concluir_etapa':
      return `Etapa ${n} concluída — ${nomeEtapa(n)}`;
    case 'nao_aplica_etapa':
      return `Etapa ${n} marcada como "não se aplica"`;
    case 'desfazer_etapa':
      return `Etapa ${n} desfeita`;
    case 'editar_cadastro':
      return 'Cadastro editado';
    default:
      return h.acao;
  }
}

function detalhesHistorico(h) {
  const d = h.detalhes;
  if (!d) return '';
  const partes = [];
  if (d.data_evento) partes.push(`Data do evento: ${data(d.data_evento)}`);
  if (d.data_solicitacao) partes.push(`Solicitado em ${data(d.data_solicitacao)}`);
  if (d.observacao) partes.push(d.observacao);
  if (d.motivo) partes.push(`Motivo: ${d.motivo}`);
  if (h.acao === 'editar_cadastro') {
    for (const [c, v] of Object.entries(d)) {
      const fmt = (x) => (x == null ? '—' : c.startsWith('data_') ? data(x) : x);
      partes.push(`${ROTULOS_CAMPOS[c] ?? c}: ${fmt(v.de)} → ${fmt(v.para)}`);
    }
  }
  return partes.map((p) => `<span>${esc(p)}</span>`).join('');
}

function secaoHistorico(det) {
  if (!det) return '';
  const itens = det.historico;
  return `
    <section class="secao">
      <h3>${icone('history')}Histórico</h3>
      ${
        itens.length
          ? `<ol class="linha-tempo">
              ${itens
                .map(
                  (h) => `
                <li class="lt-${esc(h.acao)}">
                  <p class="lt-titulo">${esc(textoHistorico(h))}</p>
                  <p class="lt-detalhes">${detalhesHistorico(h)}</p>
                  <p class="lt-meta">${h.usuario ? `${esc(h.usuario)} · ${esc(dataHora(h.criado_em))}` : esc(data(h.criado_em))}</p>
                </li>`,
                )
                .join('')}
            </ol>`
          : '<p class="vazio">Nenhum registro ainda.</p>'
      }
    </section>`;
}

export function iniciarPainel({ cabecaEl, dadosEl, historicoEl }) {
  function render() {
    const lote = estado.detalhe?.lote ?? null;
    cabecaEl.innerHTML = cabeca(lote);
    dadosEl.innerHTML = secaoDados(lote);
    historicoEl.innerHTML = secaoHistorico(estado.detalhe);
  }

  dadosEl.addEventListener('click', (e) => {
    const b = e.target.closest('[data-acao]');
    const lote = estado.detalhe?.lote;
    if (!b || !lote) return;
    if (b.dataset.acao === 'editar') editar(lote);
    if (b.dataset.acao === 'iniciar') iniciarProcesso(lote);
  });

  ouvir((_, p) => {
    if ('detalhe' in p || 'etapas' in p) render();
  });
  render();
}
