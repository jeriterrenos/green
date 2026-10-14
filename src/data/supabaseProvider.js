// Provedor de produção: conecta ao Supabase via @supabase/supabase-js (PLANO § 5.1).
import { createClient } from '@supabase/supabase-js';
import { calcularFaixa } from '../regras.js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL;
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY;

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
  },
});

export const exigeLogin = true;

export async function sessaoAtual() {
  const { data: { session } } = await supabase.auth.getSession();
  if (!session?.user) return { usuario: null, perfil: null };

  const { data: perfil } = await supabase
    .from('perfis')
    .select('nome, papel')
    .eq('user_id', session.user.id)
    .single();

  return {
    usuario: session.user,
    perfil: perfil ?? { nome: session.user.email?.split('@')[0] ?? 'Usuário', papel: 'leitor' },
  };
}

export async function login(email, password) {
  const { data, error } = await supabase.auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data;
}

export async function logout() {
  const { error } = await supabase.auth.signOut();
  if (error) throw error;
}

export async function recuperarSenha(email) {
  const { error } = await supabase.auth.resetPasswordForEmail(email, {
    redirectTo: `${window.location.origin}${import.meta.env.BASE_URL}`,
  });
  if (error) throw error;
}

export async function definirNovaSenha(password) {
  const { error } = await supabase.auth.updateUser({ password });
  if (error) throw error;
}

export function onAuthStateChange(callback) {
  return supabase.auth.onAuthStateChange((evento, sessao) => {
    callback(evento, sessao);
  });
}

export async function listarEtapas() {
  const { data, error } = await supabase
    .from('etapas')
    .select('*')
    .order('id');
  if (error) throw error;
  return data;
}

export async function listarLotes() {
  const { data: rows, error } = await supabase
    .from('vw_lotes_mapa')
    .select('*, adquirentes(*)');
  if (error) throw error;

  return {
    type: 'FeatureCollection',
    features: rows.map((r) => {
      const adquirentes = (r.adquirentes ?? []).sort((a, b) => a.ordem - b.ordem);
      const ultEtapa = Number(r.ultima_etapa || 0);
      const temProc = Boolean(r.data_solicitacao);

      const props = {
        id: r.id,
        codigo: r.codigo,
        quadra: r.quadra,
        matricula: r.matricula,
        matricula_mae: r.matricula_mae,
        gleba: r.gleba,
        cartorio: r.cartorio,
        area_m2: Number(r.area_m2 || 0),
        perimetro_m: Number(r.perimetro_m || 0),
        area_projeto_m2: r.area_projeto_m2 ? Number(r.area_projeto_m2) : null,
        dif_area_m2: r.dif_area_m2 ? Number(r.dif_area_m2) : null,
        adquirentes,
        adquirente_nome: adquirentes.map((a) => a.nome).join(' e ') || null,
        adquirente_telefone: adquirentes[0]?.telefone ?? null,
        adquirente_email: adquirentes[0]?.email ?? null,
        adquirente_endereco: adquirentes[0]?.endereco ?? null,
        bci_inscricao: r.bci_inscricao,
        protocolo_prefeitura: r.protocolo_prefeitura,
        atendente_prefeitura: r.atendente_prefeitura,
        status_geral: r.status_geral,
        status_bci: r.status_bci,
        status_itbi: r.status_itbi,
        data_compra: r.data_compra,
        data_itbi: r.data_itbi,
        data_ultimo_contato: r.data_ultimo_contato,
        observacoes: r.observacoes,
        data_solicitacao: r.data_solicitacao,
        tem_processo: temProc,
        ultima_etapa: ultEtapa,
        faixa: calcularFaixa({
          temAdquirente: adquirentes.length > 0,
          temProcesso: temProc,
          ultimaEtapa: ultEtapa,
        }),
      };

      return {
        type: 'Feature',
        id: r.id,
        geometry: r.geometria,
        properties: props,
      };
    }),
  };
}

export async function obterLote(id) {
  const { data: r, error } = await supabase
    .from('vw_lotes_mapa')
    .select('*, adquirentes(*)')
    .eq('id', id)
    .single();
  if (error) throw error;

  const [etapasRes, histRes] = await Promise.all([
    supabase.from('etapas_lote').select('*').eq('lote_id', id).order('etapa_id'),
    supabase.from('historico').select('*').eq('lote_id', id).order('criado_em', { ascending: false }),
  ]);

  const adquirentes = (r.adquirentes ?? []).sort((a, b) => a.ordem - b.ordem);
  const ultEtapa = Number(r.ultima_etapa || 0);
  const temProc = Boolean(r.data_solicitacao);

  const lote = {
    id: r.id,
    codigo: r.codigo,
    quadra: r.quadra,
    matricula: r.matricula,
    matricula_mae: r.matricula_mae,
    gleba: r.gleba,
    cartorio: r.cartorio,
    area_m2: Number(r.area_m2 || 0),
    perimetro_m: Number(r.perimetro_m || 0),
    area_projeto_m2: r.area_projeto_m2 ? Number(r.area_projeto_m2) : null,
    dif_area_m2: r.dif_area_m2 ? Number(r.dif_area_m2) : null,
    adquirentes,
    adquirente_nome: adquirentes.map((a) => a.nome).join(' e ') || null,
    adquirente_telefone: adquirentes[0]?.telefone ?? null,
    adquirente_email: adquirentes[0]?.email ?? null,
    adquirente_endereco: adquirentes[0]?.endereco ?? null,
    bci_inscricao: r.bci_inscricao,
    protocolo_prefeitura: r.protocolo_prefeitura,
    atendente_prefeitura: r.atendente_prefeitura,
    status_geral: r.status_geral,
    status_bci: r.status_bci,
    status_itbi: r.status_itbi,
    data_compra: r.data_compra,
    data_itbi: r.data_itbi,
    data_ultimo_contato: r.data_ultimo_contato,
    observacoes: r.observacoes,
    data_solicitacao: r.data_solicitacao,
    tem_processo: temProc,
    ultima_etapa: ultEtapa,
    faixa: calcularFaixa({
      temAdquirente: adquirentes.length > 0,
      temProcesso: temProc,
      ultimaEtapa: ultEtapa,
    }),
  };

  return {
    lote,
    etapas_lote: etapasRes.data ?? [],
    historico: histRes.data ?? [],
  };
}

export async function iniciarProcesso(id, dataSolicitacao) {
  const { error } = await supabase.rpc('iniciar_processo', {
    p_lote: id,
    p_data: dataSolicitacao,
  });
  if (error) throw error;
}

export async function concluirEtapa(id, etapaId, { dataEvento, observacao = '', naoSeAplica = false }) {
  const { error } = await supabase.rpc('concluir_etapa', {
    p_lote: id,
    p_etapa: etapaId,
    p_data_evento: dataEvento,
    p_observacao: observacao || null,
    p_nao_aplica: naoSeAplica,
  });
  if (error) throw error;
}

export async function desfazerUltimaEtapa(id, motivo) {
  const { error } = await supabase.rpc('desfazer_ultima_etapa', {
    p_lote: id,
    p_motivo: motivo,
  });
  if (error) throw error;
}

export async function atualizarLote(id, { adquirentes, bci_inscricao, data_ultimo_contato, observacoes, protocolo_prefeitura, atendente_prefeitura }) {
  // 1. Atualizar campos do lote
  const campos = {};
  if (bci_inscricao !== undefined) campos.bci_inscricao = bci_inscricao || null;
  if (data_ultimo_contato !== undefined) campos.data_ultimo_contato = data_ultimo_contato || null;
  if (observacoes !== undefined) campos.observacoes = observacoes || null;
  if (protocolo_prefeitura !== undefined) campos.protocolo_prefeitura = protocolo_prefeitura || null;
  if (atendente_prefeitura !== undefined) campos.atendente_prefeitura = atendente_prefeitura || null;

  if (Object.keys(campos).length > 0) {
    const { error: errLote } = await supabase.from('lotes').update(campos).eq('id', id);
    if (errLote) throw errLote;
  }

  // 2. Atualizar adquirentes
  if (Array.isArray(adquirentes)) {
    // Deleta os adquirentes atuais e insere os novos
    await supabase.from('adquirentes').delete().eq('lote_id', id);
    if (adquirentes.length > 0) {
      const inserts = adquirentes.map((a, i) => ({
        lote_id: id,
        ordem: i + 1,
        tipo_pessoa: a.tipo_pessoa || 'PF',
        nome: a.nome,
        documento: a.documento || null,
        rg: a.rg || null,
        rg_orgao: a.rg_orgao || null,
        nacionalidade: a.nacionalidade || null,
        profissao: a.profissao || null,
        estado_civil: a.estado_civil || null,
        regime_bens: a.regime_bens || null,
        conjuge_nome: a.conjuge_nome || null,
        conjuge_cpf: a.conjuge_cpf || null,
        conjuge_rg: a.conjuge_rg || null,
        telefone: a.telefone || null,
        email: a.email || null,
        endereco: a.endereco || null,
      }));
      const { error: errAdq } = await supabase.from('adquirentes').insert(inserts);
      if (errAdq) throw errAdq;
    }
  }
}
