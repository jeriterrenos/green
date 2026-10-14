// Faixas de situação do lote (cor no mapa, KPIs e legenda) — PLANO § 4.1
export const FAIXAS = {
  disponivel: { rotulo: 'Disponível', curto: 'Disp.', cor: '#FFFFFF', tracejado: true },
  sem_processo: { rotulo: 'Sem processo', curto: 'Sem proc.', cor: '#9CA3AF' },
  prefeitura: { rotulo: 'Prefeitura', curto: 'Pref.', cor: '#F28C28' },
  cartorio: { rotulo: 'Cartório', curto: 'Cart.', cor: '#2F6FB5' },
  concluido: { rotulo: 'Concluído', curto: 'Concl.', cor: '#1F6B2E' },
};

export const ORDEM_FAIXAS = ['disponivel', 'sem_processo', 'prefeitura', 'cartorio', 'concluido'];

// Extensão dos lotes: lon −40.39920 a −40.39557 · lat −2.88520 a −2.88428
export const MAPA = {
  centro: [-40.39739, -2.88474],
  // Folga de ~600 m: o loteamento é largo e baixo, e no celular (tela em pé) uma folga
  // menor obrigaria um zoom em que o loteamento inteiro não cabe na tela.
  limites: [
    [-40.4047, -2.8907],
    [-40.3901, -2.8788],
  ],
  zoomMin: 15,
  zoomMax: 20,
  zoomRotulos: 18,
  satelite: 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
  sateliteZoomMax: 17, // acima disso a Esri não tem imagem nesta região; o mapa amplia o nível 17
  glyphs: 'https://demotiles.maplibre.org/font/{fontstack}/{range}.pbf',
};

export const DESKTOP_MQ = '(min-width: 1024px)';
