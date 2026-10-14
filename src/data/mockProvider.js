// Provedor de demonstração: lê public/mock/lotes.geojson e guarda as alterações no localStorage.
// Aplica as mesmas regras das funções SQL (PLANO § 6.3) por meio de src/regras.js.
import { ETAPAS } from './etapas.js';
import {
  calcularFaixa,
  cargaInicial,
  hojeISO,
  temTexto,
  validarConclusao,
  validarData,
  validarInicio,
} from '../regras.js';

const CHAVE = 'green-terrenos-base-v3'; // v3: base do lotes_green_terrenos_atualizado.gpkg
const USUARIO = 'Administrador';
// Dados de cada adquirente (até 2 por lote) — baseados nos campos do cadastro em lotes.gpkg
export const CAMPOS_ADQUIRENTE = [
  'nome',
  'tipo_pessoa', // 'PF' | 'PJ'
  'documento', // CPF ou CNPJ
  'rg',
  'rg_orgao',
  'nacionalidade',
  'profissao',
  'estado_civil',
  'regime_bens',
  'conjuge_nome',
  'conjuge_cpf',
  'conjuge_rg',
  'telefone',
  'email',
  'endereco',
];
export const ESTADOS_COM_CONJUGE = ['casado', 'uniao_estavel'];
export const MAX_ADQUIRENTES = 2;
const CAMPOS_LOTE = ['bci_inscricao', 'data_ultimo_contato', 'observacoes', 'numero_requisicao', 'protocolo_prefeitura', 'atendente_prefeitura'];

export const exigeLogin = false;

let base = null; // GeoJSON original
let db = null; // { edicoes, processos, etapas, historico } indexados pelo id do lote

// Dados reais ficam em public/dados-locais/ (fora do git) e só existem na máquina local;
// sem eles (ex.: GitHub Pages) usa a versão fictícia de public/mock/.
const FONTES = ['dados-locais/lotes.geojson', 'mock/lotes.geojson'];

async function carregarBase() {
  if (base) return;
  for (const caminho of FONTES) {
    try {
      const resp = await fetch(`${import.meta.env.BASE_URL}${caminho}`, { cache: 'no-cache' });
      if (!resp.ok || !resp.headers.get('content-type')?.includes('json')) continue;
      base = await resp.json();
      return;
    } catch {
      /* tenta a próxima fonte */
    }
  }
  throw new Error('Não foi possível carregar os lotes.');
}

function estadoInicial() {
  const novo = { edicoes: {}, processos: {}, etapas: {}, historico: {} };
  const agora = new Date().toISOString();
  for (const f of base.features) {
    const p = f.properties;
    const carga = cargaInicial({
      etapa: p.etapa,
      temAdquirente: temTexto(p.adquirente_nome),
      naoAplica: p.nao_aplica,
    });
    if (carga.erro || !carga.processo) continue;
    const solicitacao = p.data_compra ?? hojeISO();
    novo.processos[p.id] = { data_solicitacao: solicitacao, iniciado_em: agora };
    // Etapas importadas não têm data, autor nem observação: aparecem apenas como "Concluída"
    novo.etapas[p.id] = carga.etapas.map((e) => ({
      ...e,
      data_evento: null,
      observacao: null,
      concluido_por: null,
      concluido_em: agora,
    }));
    // O histórico registra só o início do processo (sem mencionar a carga)
    novo.historico[p.id] = [
      { acao: 'iniciar_processo', etapa_id: null, detalhes: { data_solicitacao: solicitacao }, usuario: null, criado_em: solicitacao },
    ];
  }
  return novo;
}

function lerArmazenado() {
  try {
    const bruto = localStorage.getItem(CHAVE);
    return bruto ? JSON.parse(bruto) : null;
  } catch {
    return null;
  }
}

function salvar() {
  try {
    localStorage.setItem(CHAVE, JSON.stringify(db));
  } catch {
    /* navegação privada ou armazenamento bloqueado: a demo segue só em memória */
  }
}

async function garantir() {
  await carregarBase();
  if (!db) db = lerArmazenado() ?? estadoInicial();
}

function featureBase(id) {
  const f = base.features.find((x) => x.id === id);
  if (!f) throw new Error('Lote não encontrado.');
  return f;
}

/** Adquirente vindo do arquivo de lotes (só nome e telefone na demonstração). */
function adquirentesBase(p) {
  if (!temTexto(p.adquirente_nome)) return [];
  return [
    normalizarAdquirente({
      nome: p.adquirente_nome,
      telefone: p.adquirente_telefone,
      email: p.adquirente_email,
      endereco: p.adquirente_endereco,
      tipo_pessoa: 'PF',
    }),
  ];
}

function montarPropriedades(id) {
  const { properties: p } = featureBase(id);
  const ed = db.edicoes[id] ?? {};
  const lote = { ...p, ...ed };
  const adquirentes = ed.adquirentes ?? adquirentesBase(p);
  const proc = db.processos[id];
  const etapas = db.etapas[id] ?? [];
  const ultimaEtapa = etapas.length ? Math.max(...etapas.map((e) => e.etapa_id)) : 0;
  return {
    id,
    codigo: lote.codigo,
    quadra: lote.quadra || (lote.codigo || '').trim().charAt(0).toUpperCase(),
    gleba: lote.gleba ?? null,
    matricula: lote.matricula,
    matricula_mae: lote.matricula_mae ?? null,
    cartorio: lote.cartorio ?? null,
    area_m2: lote.area_m2,
    perimetro_m: lote.perimetro_m,
    adquirentes,
    adquirente_nome: adquirentes.map((a) => a.nome).join(' e ') || null,
    adquirente_telefone: adquirentes[0]?.telefone ?? null,
    adquirente_email: adquirentes[0]?.email ?? null,
    adquirente_endereco: adquirentes[0]?.endereco ?? null,
    bci_inscricao: lote.bci_inscricao,
    numero_requisicao: lote.numero_requisicao ?? lote.protocolo_prefeitura ?? null,
    protocolo_prefeitura: lote.protocolo_prefeitura ?? lote.numero_requisicao ?? null,
    atendente_prefeitura: lote.atendente_prefeitura ?? null,
    status_geral: lote.status_geral ?? null,
    status_bci: lote.status_bci ?? null,
    status_itbi: lote.status_itbi ?? null,
    data_itbi: lote.data_itbi ?? null,
    data_compra: lote.data_compra ?? null,
    area_projeto_m2: lote.area_projeto_m2 ?? null,
    dif_area_m2: lote.dif_area_m2 ?? null,
    data_ultimo_contato: lote.data_ultimo_contato,
    observacoes: lote.observacoes ?? null,
    data_solicitacao: proc?.data_solicitacao ?? null,
    tem_processo: Boolean(proc),
    ultima_etapa: ultimaEtapa,
    faixa: calcularFaixa({
      temAdquirente: adquirentes.length > 0,
      temProcesso: Boolean(proc),
      ultimaEtapa,
    }),
  };
}

function registrar(id, acao, etapa_id = null, detalhes = null) {
  (db.historico[id] ??= []).push({
    acao,
    etapa_id,
    detalhes,
    usuario: USUARIO,
    criado_em: new Date().toISOString(),
  });
}

// ---------- Interface pública (mesmo contrato do supabaseProvider — PLANO § 5.1) ----------

export async function sessaoAtual() {
  return { usuario: null, perfil: { nome: 'Administrador', papel: 'admin' } };
}

export async function listarEtapas() {
  return ETAPAS;
}

export async function listarLotes() {
  await garantir();
  return {
    type: 'FeatureCollection',
    features: base.features.map((f) => ({
      type: 'Feature',
      id: f.id,
      geometry: f.geometry,
      properties: montarPropriedades(f.id),
    })),
  };
}

export async function obterLote(id) {
  await garantir();
  return {
    lote: montarPropriedades(id),
    etapas_lote: [...(db.etapas[id] ?? [])],
    historico: [...(db.historico[id] ?? [])].reverse(),
  };
}

export async function iniciarProcesso(id, dataSolicitacao) {
  await garantir();
  const lote = montarPropriedades(id);
  const erro = validarInicio({
    temAdquirente: lote.adquirentes.length > 0,
    temProcesso: lote.tem_processo,
    dataSolicitacao,
  });
  if (erro) throw new Error(erro);
  db.processos[id] = { data_solicitacao: dataSolicitacao, iniciado_em: new Date().toISOString() };
  db.etapas[id] = [];
  registrar(id, 'iniciar_processo', null, { data_solicitacao: dataSolicitacao });
  salvar();
}

export async function concluirEtapa(id, etapaId, { dataEvento, observacao = '', naoSeAplica = false }) {
  await garantir();
  const lote = montarPropriedades(id);
  const etapa = ETAPAS.find((e) => e.id === etapaId);
  const erro = validarConclusao({
    temProcesso: lote.tem_processo,
    ultimaEtapa: lote.ultima_etapa,
    etapa: etapaId,
    dispensavel: etapa?.dispensavel,
    naoSeAplica,
    dataEvento,
    observacao,
  });
  if (erro) throw new Error(erro);
  const obs = temTexto(observacao) ? observacao.trim() : null;
  db.etapas[id].push({
    etapa_id: etapaId,
    status: naoSeAplica ? 'nao_aplica' : 'concluida',
    data_evento: dataEvento,
    observacao: obs,
    concluido_por: USUARIO,
    concluido_em: new Date().toISOString(),
  });
  registrar(id, naoSeAplica ? 'nao_aplica_etapa' : 'concluir_etapa', etapaId, { data_evento: dataEvento, observacao: obs });
  salvar();
}

export async function desfazerUltimaEtapa(id, motivo) {
  await garantir();
  if (!temTexto(motivo)) throw new Error('Informe o motivo.');
  const etapas = db.etapas[id] ?? [];
  if (!etapas.length) throw new Error('Nenhuma etapa concluída.');
  const removida = etapas.pop();
  registrar(id, 'desfazer_etapa', removida.etapa_id, { motivo: motivo.trim() });
  salvar();
}

function limpar(v) {
  const t = typeof v === 'string' ? v.trim() : v;
  return t === '' || t === undefined ? null : t;
}

function normalizarAdquirente(a) {
  const n = {};
  for (const c of CAMPOS_ADQUIRENTE) n[c] = limpar(a?.[c]);
  if (!ESTADOS_COM_CONJUGE.includes(n.estado_civil)) {
    n.regime_bens = n.conjuge_nome = n.conjuge_cpf = n.conjuge_rg = null;
  }
  return n;
}

function validarAdquirente(a, ordem) {
  const quem = `Adquirente ${ordem}`;
  if (!temTexto(a.nome)) return `${quem}: informe o nome.`;
  const dig = String(a.documento ?? '').replace(/\D/g, '');
  if (dig && dig.length !== (a.tipo_pessoa === 'PJ' ? 14 : 11)) {
    return `${quem}: ${a.tipo_pessoa === 'PJ' ? 'CNPJ deve ter 14' : 'CPF deve ter 11'} dígitos.`;
  }
  const digConj = String(a.conjuge_cpf ?? '').replace(/\D/g, '');
  if (digConj && digConj.length !== 11) return `${quem}: CPF do cônjuge deve ter 11 dígitos.`;
  if (a.email && !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(a.email)) return `${quem}: e-mail inválido.`;
  return null;
}

/**
 * @param {{ adquirentes?: object[], bci_inscricao?: string, data_ultimo_contato?: string, observacoes?: string }} campos
 */
export async function atualizarLote(id, campos) {
  await garantir();
  const atual = montarPropriedades(id);
  const novos = {};
  for (const c of CAMPOS_LOTE) if (c in campos) novos[c] = limpar(campos[c]);
  if (novos.data_ultimo_contato) {
    const erro = validarData(novos.data_ultimo_contato);
    if (erro) throw new Error(`${erro} (último contato)`);
  }
  if ('adquirentes' in campos) {
    const lista = campos.adquirentes.map(normalizarAdquirente).filter((a) => CAMPOS_ADQUIRENTE.some((c) => a[c] != null && c !== 'tipo_pessoa'));
    if (lista.length > MAX_ADQUIRENTES) throw new Error(`No máximo ${MAX_ADQUIRENTES} adquirentes.`);
    lista.forEach((a, i) => {
      const erro = validarAdquirente(a, i + 1);
      if (erro) throw new Error(erro);
    });
    if (!lista.length && atual.tem_processo) {
      throw new Error('Não é possível remover o adquirente de um lote com processo iniciado.');
    }
    novos.adquirentes = lista;
  }

  const dif = {};
  for (const c of CAMPOS_LOTE) {
    if (c in novos && (atual[c] ?? null) !== novos[c]) dif[c] = { de: atual[c] ?? null, para: novos[c] };
  }
  if (novos.adquirentes) {
    const antes = atual.adquirentes.map((a) => a.nome).join(' e ') || null;
    const depois = novos.adquirentes.map((a) => a.nome).join(' e ') || null;
    if (JSON.stringify(atual.adquirentes.map(normalizarAdquirente)) !== JSON.stringify(novos.adquirentes)) {
      dif.adquirentes = { de: antes, para: depois };
    }
  }
  if (!Object.keys(dif).length) return;
  db.edicoes[id] = { ...(db.edicoes[id] ?? {}), ...novos };
  registrar(id, 'editar_cadastro', null, dif);
  salvar();
}

export async function restaurarDemonstracao() {
  await carregarBase();
  db = estadoInicial();
  salvar();
}
