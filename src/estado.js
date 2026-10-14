// Estado global simples com assinantes. Cada componente re-renderiza ao ser notificado.
const ouvintes = new Set();

export const estado = {
  perfil: null, // { nome, papel }
  etapas: [], // catálogo
  lotes: null, // FeatureCollection
  loteId: null, // lote selecionado
  detalhe: null, // { lote, etapas_lote, historico } do lote selecionado
  etapaSel: null, // etapa aberta no fluxo (null = todas recolhidas)
  filtroFaixa: null, // faixa realçada pelos KPIs
  desktop: true, // layout atual
};

export function atualizar(parcial) {
  Object.assign(estado, parcial);
  for (const f of ouvintes) f(estado, parcial);
}

export function ouvir(f) {
  ouvintes.add(f);
}

export const ehAdmin = () => estado.perfil?.papel === 'admin';
