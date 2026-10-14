// Ações do admin: iniciar processo, dar ok, não se aplica, desfazer, editar cadastro — PLANO § 8.5–8.8
import { dados } from '../data/index.js';
import { estado } from '../estado.js';
import { CAMPOS_ADQUIRENTE, ESTADOS_COM_CONJUGE } from '../data/mockProvider.js';
import { hojeISO } from '../regras.js';
import { esc, icone } from '../util/html.js';
import { ESTADOS_CIVIS, REGIMES_BENS } from './rotulos.js';
import { abrirModal } from './modal.js';
import { toast } from './toast.js';

let recarregar = async () => {};

export function configurarAcoes(fn) {
  recarregar = fn;
}

const nomeEtapa = (id) => estado.etapas.find((e) => e.id === id)?.nome ?? `Etapa ${id}`;

function campoData(nome, rotulo, valor = hojeISO(), obrigatorio = true) {
  return `
    <label class="campo">
      <span>${esc(rotulo)}${obrigatorio ? ' *' : ''}</span>
      <input type="date" name="${nome}" value="${esc(valor ?? '')}" max="${hojeISO()}" ${obrigatorio ? 'required' : ''}>
    </label>`;
}

function campoTexto(nome, rotulo, valor = '', { area = false, obrigatorio = false, tipo = 'text', modo = '' } = {}) {
  const attrs = `name="${nome}" ${obrigatorio ? 'required' : ''} ${modo ? `inputmode="${modo}"` : ''}`;
  return `
    <label class="campo">
      <span>${esc(rotulo)}${obrigatorio ? ' *' : ''}</span>
      ${area ? `<textarea ${attrs} rows="3">${esc(valor ?? '')}</textarea>` : `<input type="${tipo}" ${attrs} value="${esc(valor ?? '')}">`}
    </label>`;
}

async function executar(promessa, sucesso) {
  await promessa; // erros sobem para o modal, que mostra a mensagem
  await recarregar();
  toast(sucesso);
}

export function iniciarProcesso(lote) {
  abrirModal({
    titulo: `Iniciar processo — Lote ${lote.codigo}`,
    corpo: `
      <p class="modal-texto">O adquirente <b>${esc(lote.adquirente_nome)}</b> solicitou a transferência da matrícula
      <b>${esc(lote.matricula ?? '—')}</b>. Ao iniciar, a etapa 1 (Cadastro imobiliário) fica liberada.</p>
      ${campoData('data', 'Data da solicitação')}`,
    acoes: [
      { rotulo: 'Cancelar' },
      {
        rotulo: 'Iniciar processo',
        tipo: 'primario',
        icone: 'play_arrow',
        aoClicar: (m) => executar(dados.iniciarProcesso(lote.id, m.valor('data')), 'Processo iniciado.'),
      },
    ],
  });
}

export function darOk(lote, etapa, { naoSeAplica = false } = {}) {
  abrirModal({
    titulo: naoSeAplica ? `Não se aplica — Etapa ${etapa.id}` : `Concluir etapa ${etapa.id}`,
    corpo: `
      <p class="modal-texto"><b>${esc(etapa.nome)}</b><br>Lote ${esc(lote.codigo)} · Matrícula ${esc(lote.matricula ?? '—')}</p>
      ${campoData('data', naoSeAplica ? 'Data da decisão' : 'Data do evento')}
      ${campoTexto('obs', naoSeAplica ? 'Motivo (por que não se aplica)' : 'Observação', '', { area: true, obrigatorio: naoSeAplica })}`,
    acoes: [
      { rotulo: 'Cancelar' },
      {
        rotulo: naoSeAplica ? 'Marcar "não se aplica"' : 'Confirmar OK',
        tipo: 'primario',
        icone: naoSeAplica ? 'block' : 'check',
        aoClicar: (m) =>
          executar(
            dados.concluirEtapa(lote.id, etapa.id, { dataEvento: m.valor('data'), observacao: m.valor('obs'), naoSeAplica }),
            naoSeAplica ? `Etapa ${etapa.id} marcada como "não se aplica".` : `Etapa ${etapa.id} concluída.`,
          ),
      },
    ],
  });
}

export function desfazer(lote, etapaId) {
  abrirModal({
    titulo: `Desfazer etapa ${etapaId}`,
    corpo: `
      <p class="modal-texto">A etapa <b>${esc(nomeEtapa(etapaId))}</b> do lote <b>${esc(lote.codigo)}</b> voltará a ficar pendente.
      A ação fica registrada no histórico.</p>
      ${campoTexto('motivo', 'Motivo', '', { area: true, obrigatorio: true })}`,
    acoes: [
      { rotulo: 'Cancelar' },
      {
        rotulo: 'Desfazer',
        tipo: 'perigo',
        icone: 'undo',
        aoClicar: (m) => executar(dados.desfazerUltimaEtapa(lote.id, m.valor('motivo')), `Etapa ${etapaId} desfeita.`),
      },
    ],
  });
}

function opcoes(mapa, valor, vazio = 'Selecione…') {
  return `<option value="">${esc(vazio)}</option>${Object.entries(mapa)
    .map(([k, v]) => `<option value="${k}" ${k === valor ? 'selected' : ''}>${esc(v)}</option>`)
    .join('')}`;
}

function campoSelect(nome, rotulo, mapa, valor) {
  return `
    <label class="campo">
      <span>${esc(rotulo)}</span>
      <select name="${nome}">${opcoes(mapa, valor)}</select>
    </label>`;
}

/** Bloco de campos de um adquirente; prefixo 'a1' ou 'a2'. */
function blocoAdquirente(prefixo, ordem, a = {}) {
  const n = (c) => `${prefixo}_${c}`;
  const pj = a.tipo_pessoa === 'PJ';
  return `
    <fieldset class="grupo grupo-adquirente" data-prefixo="${prefixo}">
      <legend>Adquirente ${ordem}</legend>
      <div class="campo-tipo" role="radiogroup" aria-label="Tipo de pessoa">
        <label><input type="radio" name="${n('tipo_pessoa')}" value="PF" ${pj ? '' : 'checked'}> Pessoa física</label>
        <label><input type="radio" name="${n('tipo_pessoa')}" value="PJ" ${pj ? 'checked' : ''}> Pessoa jurídica</label>
      </div>
      <div class="grade-campos">
        ${campoTexto(n('nome'), pj ? 'Razão social' : 'Nome completo', a.nome, { obrigatorio: true })}
        ${campoTexto(n('documento'), pj ? 'CNPJ' : 'CPF', a.documento, { modo: 'numeric' })}
        <div class="so-pf grade-campos sub">
          ${campoTexto(n('rg'), 'RG', a.rg)}
          ${campoTexto(n('rg_orgao'), 'Órgão emissor / UF', a.rg_orgao)}
          ${campoTexto(n('nacionalidade'), 'Nacionalidade', a.nacionalidade ?? 'Brasileira')}
          ${campoTexto(n('profissao'), 'Profissão', a.profissao)}
          ${campoSelect(n('estado_civil'), 'Estado civil', ESTADOS_CIVIS, a.estado_civil)}
          <div class="so-conjuge grade-campos sub">
            ${campoSelect(n('regime_bens'), 'Regime de bens', REGIMES_BENS, a.regime_bens)}
            ${campoTexto(n('conjuge_nome'), 'Nome do(a) cônjuge', a.conjuge_nome)}
            ${campoTexto(n('conjuge_cpf'), 'CPF do(a) cônjuge', a.conjuge_cpf, { modo: 'numeric' })}
            ${campoTexto(n('conjuge_rg'), 'RG do(a) cônjuge', a.conjuge_rg)}
          </div>
        </div>
        ${campoTexto(n('telefone'), 'Telefone / WhatsApp', a.telefone, { tipo: 'tel' })}
        ${campoTexto(n('email'), 'E-mail', a.email, { tipo: 'email' })}
        <div class="campo-largo">${campoTexto(n('endereco'), 'Endereço completo', a.endereco)}</div>
      </div>
      ${ordem > 1 ? `<button type="button" class="btn btn-perigo-leve" data-remover="${prefixo}">${icone('person_remove')}Remover adquirente ${ordem}</button>` : ''}
    </fieldset>`;
}

function lerAdquirente(m, prefixo) {
  const a = {};
  for (const c of CAMPOS_ADQUIRENTE) {
    a[c] =
      c === 'tipo_pessoa'
        ? (m.dlg.querySelector(`[name="${prefixo}_tipo_pessoa"]:checked`)?.value ?? 'PF')
        : m.valor(`${prefixo}_${c}`);
  }
  if (a.tipo_pessoa === 'PJ') {
    for (const c of ['rg', 'rg_orgao', 'nacionalidade', 'profissao', 'estado_civil']) a[c] = null;
  }
  return a;
}

/** Mostra/oculta campos conforme o tipo de pessoa e o estado civil. */
function ajustarVisibilidade(dlg) {
  dlg.querySelectorAll('.grupo-adquirente').forEach((g) => {
    const pre = g.dataset.prefixo;
    const pj = g.querySelector(`[name="${pre}_tipo_pessoa"]:checked`)?.value === 'PJ';
    const civil = g.querySelector(`[name="${pre}_estado_civil"]`)?.value;
    g.querySelector('.so-pf').hidden = pj;
    g.querySelector('.so-conjuge').hidden = pj || !ESTADOS_COM_CONJUGE.includes(civil);
    g.querySelector(`[name="${pre}_nome"]`).previousElementSibling.textContent = pj ? 'Razão social *' : 'Nome completo *';
    g.querySelector(`[name="${pre}_documento"]`).previousElementSibling.textContent = pj ? 'CNPJ' : 'CPF';
  });
}

export function editar(lote) {
  const disponivel = lote.faixa === 'disponivel';
  const [a1, a2] = lote.adquirentes;
  const m = abrirModal({
    titulo: `Editar cadastro — Lote ${lote.codigo}`,
    classe: 'modal-largo',
    corpo: `
      ${disponivel ? '<p class="modal-texto aviso">Lote disponível: ao informar o adquirente, ele passa para <b>Sem processo</b>.</p>' : ''}
      <p class="modal-texto">Matrícula <b>${esc(lote.matricula ?? '—')}</b> · campos com * são obrigatórios.</p>
      ${blocoAdquirente('a1', 1, a1)}
      <div id="slot-a2">${a2 ? blocoAdquirente('a2', 2, a2) : ''}</div>
      <button type="button" class="btn btn-secundario" id="add-a2" ${a2 ? 'hidden' : ''}>${icone('person_add')}Adicionar segundo adquirente</button>
      <fieldset class="grupo"><legend>Prefeitura e acompanhamento</legend>
        <div class="grade-campos">
          ${campoTexto('bci_inscricao', 'BCI / inscrição imobiliária', lote.bci_inscricao)}
          ${campoData('data_ultimo_contato', 'Data do último contato', lote.data_ultimo_contato, false)}
          <div class="campo-largo">${campoTexto('observacoes', 'Observações', lote.observacoes, { area: true })}</div>
        </div>
      </fieldset>`,
    acoes: [
      { rotulo: 'Cancelar' },
      {
        rotulo: 'Salvar',
        tipo: 'primario',
        icone: 'save',
        aoClicar: (ctx) => {
          const adquirentes = [lerAdquirente(ctx, 'a1')];
          if (ctx.dlg.querySelector('[data-prefixo="a2"]')) adquirentes.push(lerAdquirente(ctx, 'a2'));
          return executar(
            dados.atualizarLote(lote.id, {
              adquirentes,
              bci_inscricao: ctx.valor('bci_inscricao'),
              data_ultimo_contato: ctx.valor('data_ultimo_contato'),
              observacoes: ctx.valor('observacoes'),
            }),
            'Cadastro atualizado.',
          );
        },
      },
    ],
  });

  const { dlg } = m;
  const slot = dlg.querySelector('#slot-a2');
  const add = dlg.querySelector('#add-a2');
  dlg.addEventListener('change', () => ajustarVisibilidade(dlg));
  add.addEventListener('click', () => {
    slot.innerHTML = blocoAdquirente('a2', 2);
    add.hidden = true;
    ajustarVisibilidade(dlg);
    slot.querySelector('input[type="text"]')?.focus();
  });
  slot.addEventListener('click', (e) => {
    if (!e.target.closest('[data-remover]')) return;
    slot.innerHTML = '';
    add.hidden = false;
  });
  ajustarVisibilidade(dlg);
}

export function restaurarDemo() {
  abrirModal({
    titulo: 'Restaurar dados de demonstração',
    corpo: '<p class="modal-texto">Todas as alterações feitas nesta demonstração (oks, edições e histórico) serão apagadas deste navegador.</p>',
    acoes: [
      { rotulo: 'Cancelar' },
      {
        rotulo: 'Restaurar',
        tipo: 'perigo',
        icone: 'restart_alt',
        aoClicar: () => executar(dados.restaurarDemonstracao(), 'Dados de demonstração restaurados.'),
      },
    ],
  });
}
