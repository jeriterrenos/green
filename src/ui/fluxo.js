// Fluxo das 9 etapas + documentos — PLANO § 4.2, 8.6, 8.7
// Desktop: barra horizontal e documentos num card abaixo. Celular: lista vertical com documentos em acordeão.
import { atualizar, ehAdmin, estado, ouvir } from '../estado.js';
import { proximaEtapa } from '../regras.js';
import { esc, icone } from '../util/html.js';
import { data } from '../util/formatos.js';
import { darOk, desfazer, editar } from './acoes.js';
import { MODELOS, PORTAL_TRIBUTOS } from '../data/modelos.js';
import { toast } from './toast.js';

function situacaoEtapas() {
  const lote = estado.detalhe?.lote;
  const feitas = new Map((estado.detalhe?.etapas_lote ?? []).map((e) => [e.etapa_id, e]));
  const prox = lote ? proximaEtapa({ temProcesso: lote.tem_processo, ultimaEtapa: lote.ultima_etapa }) : null;
  return { lote, feitas, prox };
}

function estadoDe(id, { feitas, prox }) {
  const f = feitas.get(id);
  if (f) return f.status === 'nao_aplica' ? 'nao-aplica' : 'concluida';
  return id === prox ? 'proxima' : 'pendente';
}

const ROTULO_ESTADO = {
  concluida: 'Concluída',
  'nao-aplica': 'Não se aplica',
  proxima: 'Próxima etapa',
  pendente: 'Pendente',
};

function htmlDocumentos(etapa, sit) {
  const { lote, feitas, prox } = sit;
  const feita = feitas.get(etapa.id);
  const ultima = lote?.ultima_etapa ?? 0;
  const admin = ehAdmin();

  let status = '';
  if (feita) {
    const quando = feita.data_evento ? ` em ${data(feita.data_evento)}` : '';
    const rotulo = feita.status === 'nao_aplica' ? 'Não se aplica' : 'Concluída';
    status = `<p class="doc-status doc-status-ok">${icone(feita.status === 'nao_aplica' ? 'block' : 'check_circle')}
      ${rotulo}${esc(quando)}</p>`;
  } else if (lote && !lote.tem_processo) {
    status = `<p class="doc-status">${icone('info')} ${
      lote.faixa === 'disponivel' ? 'Lote disponível: informe o adquirente para iniciar o processo.' : 'Processo ainda não iniciado para este lote.'
    }</p>`;
  } else if (lote && etapa.id > (prox ?? 0)) {
    status = `<p class="doc-status">${icone('lock')} Conclua a etapa ${prox} antes desta.</p>`;
  }

  let botoes = '';
  if (admin && lote) {
    if (etapa.id === prox) {
      botoes += `<button type="button" class="btn btn-primario" data-ok="${etapa.id}" aria-label="Dar OK na etapa ${etapa.id}">${icone('check')}OK</button>`;
      if (etapa.dispensavel) {
        botoes += `<button type="button" class="btn btn-secundario" data-na="${etapa.id}">${icone('block')}Não se aplica</button>`;
      }
    }
    if (feita && etapa.id === ultima) {
      botoes += `<button type="button" class="btn btn-perigo-leve" data-desfazer="${etapa.id}">${icone('undo')}Desfazer</button>`;
    }
  }

  const modelo = etapa.modelo && lote && lote.faixa !== 'disponivel' ? MODELOS[etapa.modelo] : null;
  const pend = modelo ? modelo.pendencias(lote) : [];
  const bloqueado = Boolean(modelo?.bloqueiaSemDados && pend.length);
  const portal = `<a class="btn btn-primario" href="${PORTAL_TRIBUTOS}" target="_blank" rel="noopener"
       title="Abre a página de nova requisição no portal da Prefeitura de Cruz">${icone('open_in_new')}Abrir portal de Tributos</a>`;
  let blocoModelo = '';
  if (modelo && bloqueado) {
    blocoModelo = `<div class="modelo modelo-bloqueado">
        <div class="modelo-cabeca">
          <h4 class="doc-sub">${icone('lock')} ${esc(modelo.titulo)}</h4>
          <div class="modelo-botoes">
            <button type="button" class="btn btn-secundario" disabled aria-disabled="true">${icone('content_copy')}Copiar texto</button>
            ${portal}
          </div>
        </div>
        <p class="modelo-aviso">${icone('warning')} O texto será liberado quando estes dados estiverem preenchidos:</p>
        <ul class="modelo-faltas">${pend.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>
        ${ehAdmin() ? `<button type="button" class="btn btn-secundario" data-editar-cadastro>${icone('edit')}Completar cadastro</button>` : ''}
      </div>`;
  } else if (modelo) {
    blocoModelo = `<div class="modelo">
        <div class="modelo-cabeca">
          <h4 class="doc-sub">${icone('content_paste')} ${esc(modelo.titulo)}</h4>
          <div class="modelo-botoes">
            <button type="button" class="btn btn-secundario" data-copiar="${etapa.id}">${icone('content_copy')}Copiar texto</button>
            ${portal}
          </div>
        </div>
        ${pend.length ? `<p class="modelo-aviso">${icone('warning')} Falta: ${esc(pend.join(', '))}. Complete no texto antes de enviar.</p>` : ''}
        <details class="modelo-previa">
          <summary>Ver texto</summary>
          <pre>${esc(modelo.gerar(lote))}</pre>
        </details>
      </div>`;
  }

  return `
    <div class="doc">
      <h3 class="doc-titulo">${icone(etapa.icone)} Etapa ${etapa.id} — ${esc(etapa.nome)}</h3>
      <p class="doc-desc">${esc(etapa.descricao)}</p>
      <h4 class="doc-sub">Documentos e conferências</h4>
      <ul class="doc-lista">${etapa.documentos.map((d) => `<li>${icone('description')}<span>${esc(d)}</span></li>`).join('')}</ul>
      ${blocoModelo}
      ${status}
      ${botoes ? `<div class="doc-acoes">${botoes}</div>` : ''}
    </div>`;
}

/** Copia para a área de transferência (com alternativa para navegadores sem a API moderna). */
async function copiar(texto) {
  if (navigator.clipboard?.writeText && window.isSecureContext) return navigator.clipboard.writeText(texto);
  const area = document.createElement('textarea');
  area.value = texto;
  area.setAttribute('readonly', '');
  area.style.cssText = 'position:fixed;opacity:0;top:0;left:0';
  document.body.append(area);
  area.select();
  const ok = document.execCommand('copy');
  area.remove();
  if (!ok) throw new Error('cópia indisponível');
}

export function iniciarFluxo(fluxoEl, docsEl) {
  function render() {
    const sit = situacaoEtapas();
    const sel = estado.etapaSel;
    const movel = !estado.desktop;
    const titulo = sit.lote
      ? `Fluxo da transferência · Lote ${esc(sit.lote.codigo)}${sel == null ? ' <small>(clique em uma etapa para ver os documentos)</small>' : ''}`
      : 'Fluxo da transferência <small>(selecione um lote)</small>';

    fluxoEl.innerHTML = `
      <h2 class="fluxo-titulo">${titulo}</h2>
      <ol class="fluxo-lista">
        ${estado.etapas
          .map((e) => {
            const st = estadoDe(e.id, sit);
            const aberta = movel && e.id === sel;
            return `
            <li class="etapa etapa-${st} ${e.id === sel ? 'selecionada' : ''}">
              <button type="button" class="etapa-botao" data-etapa="${e.id}" aria-pressed="${e.id === sel}"
                      ${movel ? `aria-expanded="${aberta}"` : ''} title="${esc(e.nome)} — ${ROTULO_ESTADO[st]}">
                <span class="etapa-icone">${icone(st === 'nao-aplica' ? 'remove' : st === 'concluida' ? 'check' : e.icone)}</span>
                <span class="etapa-nome"><span class="etapa-num">${e.id}</span> <span class="so-desktop">${esc(e.nome_curto)}</span><span class="so-movel">${esc(e.nome)}</span></span>
                <span class="etapa-estado so-movel">${ROTULO_ESTADO[st]}</span>
                <span class="so-movel etapa-seta">${icone(aberta ? 'expand_less' : 'expand_more')}</span>
              </button>
              ${aberta ? `<div class="etapa-docs">${htmlDocumentos(e, sit)}</div>` : ''}
            </li>`;
          })
          .join('')}
      </ol>
      <ul class="fluxo-legenda so-desktop">
        <li><span class="bolinha b-concluida"></span>Concluída</li>
        <li><span class="bolinha b-proxima"></span>Próxima</li>
        <li><span class="bolinha b-pendente"></span>Pendente</li>
      </ul>`;

    const etapa = estado.etapas.find((e) => e.id === sel);
    docsEl.innerHTML = !movel && etapa ? htmlDocumentos(etapa, sit) : '';
    docsEl.hidden = movel || !etapa;
  }

  function aoClicar(e) {
    const lote = estado.detalhe?.lote;
    const t = e.target.closest('[data-etapa],[data-ok],[data-na],[data-desfazer],[data-copiar],[data-editar-cadastro]');
    if (!t) return;
    if (t.dataset.etapa) {
      const id = Number(t.dataset.etapa);
      // Clicar de novo na etapa aberta recolhe os documentos
      atualizar({ etapaSel: estado.etapaSel === id ? null : id });
      return;
    }
    const etapa = (id) => estado.etapas.find((x) => x.id === Number(id));
    if (!lote) return;
    if ('editarCadastro' in t.dataset) return editar(lote);
    if (t.dataset.copiar) {
      const modelo = MODELOS[etapa(t.dataset.copiar).modelo];
      copiar(modelo.gerar(lote)).then(
        () => toast('Texto copiado. Cole no portal de Tributos.'),
        () => toast('Não foi possível copiar automaticamente; selecione o texto em "Ver texto".', 'erro'),
      );
      return;
    }
    if (t.dataset.ok) darOk(lote, etapa(t.dataset.ok));
    if (t.dataset.na) darOk(lote, etapa(t.dataset.na), { naoSeAplica: true });
    if (t.dataset.desfazer) desfazer(lote, Number(t.dataset.desfazer));
  }
  fluxoEl.addEventListener('click', aoClicar);
  docsEl.addEventListener('click', aoClicar);

  ouvir((_, p) => {
    if ('detalhe' in p || 'etapaSel' in p || 'desktop' in p || 'etapas' in p) render();
  });
  render();
}
