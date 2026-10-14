// Mapa MapLibre preso ao loteamento — PLANO § 7
import maplibregl from 'maplibre-gl';
import 'maplibre-gl/dist/maplibre-gl.css';
import { FAIXAS, MAPA } from '../config.js';

const FONTE = 'lotes';
const TOLERANCIA_TOQUE = 8; // px — lotes ficam pequenos na tela do celular

function corPorFaixa() {
  const exp = ['match', ['get', 'faixa']];
  for (const [k, f] of Object.entries(FAIXAS)) exp.push(k, f.cor);
  exp.push('#9CA3AF');
  return exp;
}

function opacidade(filtro) {
  const hover = ['boolean', ['feature-state', 'hover'], false];
  // Disponível fica com opacidade quase zero (só contorno), mas continua clicável
  const normal = ['case', ['==', ['get', 'faixa'], 'disponivel'], ['case', hover, 0.25, 0.02], ['case', hover, 0.82, 0.58]];
  if (!filtro) return normal;
  return ['case', ['==', ['get', 'faixa'], filtro], normal, 0.08];
}

function limitesDe(geometria) {
  const b = new maplibregl.LngLatBounds();
  const aneis = geometria.type === 'MultiPolygon' ? geometria.coordinates.flat(1) : geometria.coordinates;
  for (const anel of aneis) for (const c of anel) b.extend(c);
  return b;
}

/**
 * @param {HTMLElement} container
 * @param {{ aoSelecionar: (id: number|null) => void, paddingInferior: () => number }} opcoes
 */
export function criarMapa(container, { aoSelecionar, paddingInferior }) {
  const map = new maplibregl.Map({
    container,
    style: {
      version: 8,
      glyphs: MAPA.glyphs,
      sources: {
        satelite: {
          type: 'raster',
          tiles: [MAPA.satelite],
          tileSize: 256,
          maxzoom: MAPA.sateliteZoomMax,
          attribution: '© Esri World Imagery',
        },
      },
      layers: [
        { id: 'fundo', type: 'background', paint: { 'background-color': '#1f2a1f' } },
        { id: 'satelite', type: 'raster', source: 'satelite' },
      ],
    },
    center: MAPA.centro,
    zoom: 17,
    minZoom: MAPA.zoomMin,
    maxZoom: MAPA.zoomMax,
    maxBounds: MAPA.limites,
    dragRotate: false,
    pitchWithRotate: false,
    touchPitch: false,
    attributionControl: { compact: true },
  });
  map.touchZoomRotate.disableRotation();
  map.keyboard.disableRotation();

  map.addControl(new maplibregl.NavigationControl({ showCompass: false }), 'top-right');
  map.addControl(new BotaoEnquadrar(() => enquadrar()), 'top-right');
  map.addControl(new maplibregl.ScaleControl({ unit: 'metric' }), 'bottom-right');

  let avisarPronto;
  const primeiroDesenho = new Promise((r) => (avisarPronto = r));
  // Não segura a página se o satélite demorar: no máximo 4 s
  const prontoComLimite = Promise.race([primeiroDesenho, new Promise((r) => setTimeout(r, 4000))]);

  const limites = new Map(); // id → LngLatBounds
  let limitesTotais = null;
  let pronto = false;
  let pendente = null;
  let hoverId = null;
  let selecionado = null;

  map.on('load', () => {
    map.addSource(FONTE, { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
    map.addLayer({
      id: 'lotes-fill',
      type: 'fill',
      source: FONTE,
      paint: { 'fill-color': corPorFaixa(), 'fill-opacity': opacidade(null) },
    });
    map.addLayer({
      id: 'lotes-line',
      type: 'line',
      source: FONTE,
      filter: ['!=', ['get', 'faixa'], 'disponivel'],
      paint: {
        'line-color': '#ffffff',
        'line-width': ['case', ['boolean', ['feature-state', 'hover'], false], 2.5, 1.2],
      },
    });
    map.addLayer({
      id: 'lotes-disponivel-line',
      type: 'line',
      source: FONTE,
      filter: ['==', ['get', 'faixa'], 'disponivel'],
      paint: { 'line-color': '#ffffff', 'line-width': 1.6, 'line-dasharray': [2, 2] },
    });
    map.addLayer({
      id: 'lote-selecionado',
      type: 'line',
      source: FONTE,
      filter: ['==', ['id'], -1],
      paint: { 'line-color': '#A8C83A', 'line-width': 4 },
    });
    map.addLayer({
      id: 'lotes-rotulo',
      type: 'symbol',
      source: FONTE,
      minzoom: MAPA.zoomRotulos,
      layout: {
        'text-field': ['get', 'codigo'],
        'text-font': ['Open Sans Semibold'],
        'text-size': 12,
        'text-max-width': 6,
      },
      paint: { 'text-color': '#ffffff', 'text-halo-color': 'rgba(0,0,0,0.75)', 'text-halo-width': 1.5 },
    });
    pronto = true;
    if (pendente) atualizarDados(pendente, true);
  });

  map.on('mousemove', 'lotes-fill', (e) => {
    map.getCanvas().style.cursor = 'pointer';
    const id = e.features[0]?.id;
    if (id === hoverId) return;
    if (hoverId != null) map.setFeatureState({ source: FONTE, id: hoverId }, { hover: false });
    hoverId = id;
    if (id != null) map.setFeatureState({ source: FONTE, id }, { hover: true });
  });
  map.on('mouseleave', 'lotes-fill', () => {
    map.getCanvas().style.cursor = '';
    if (hoverId != null) map.setFeatureState({ source: FONTE, id: hoverId }, { hover: false });
    hoverId = null;
  });

  map.on('click', (e) => {
    if (!pronto) return;
    const { x, y } = e.point;
    const exato = map.queryRenderedFeatures(e.point, { layers: ['lotes-fill'] });
    const perto = exato.length
      ? exato
      : map.queryRenderedFeatures(
          [
            [x - TOLERANCIA_TOQUE, y - TOLERANCIA_TOQUE],
            [x + TOLERANCIA_TOQUE, y + TOLERANCIA_TOQUE],
          ],
          { layers: ['lotes-fill'] },
        );
    aoSelecionar(perto.length ? perto[0].id : null);
  });

  // Ajusta o mapa quando o contêiner muda de tamanho (girar a tela, abrir a gaveta…)
  new ResizeObserver(() => map.resize()).observe(container);

  function padding() {
    const base = 40;
    return { top: base, left: base, right: base, bottom: base + (paddingInferior?.() ?? 0) };
  }

  function enquadrar() {
    if (limitesTotais) map.fitBounds(limitesTotais, { padding: padding(), duration: 800 });
  }

  function atualizarDados(fc, primeiraVez = false) {
    if (!pronto) {
      pendente = fc;
      return;
    }
    const primeira = primeiraVez || limites.size === 0;
    limites.clear();
    limitesTotais = new maplibregl.LngLatBounds();
    for (const f of fc.features) {
      const b = limitesDe(f.geometry);
      limites.set(f.id, b);
      limitesTotais.extend(b);
    }
    map.getSource(FONTE).setData(fc);
    if (primeira) {
      map.fitBounds(limitesTotais, { padding: padding(), duration: 0 });
      map.once('idle', () => avisarPronto());
    }
  }

  function selecionar(id) {
    selecionado = id;
    if (pronto) map.setFilter('lote-selecionado', ['==', ['id'], id ?? -1]);
  }

  function focar(id) {
    const b = limites.get(id);
    if (b) map.fitBounds(b, { padding: padding(), maxZoom: 18, duration: 700 });
  }

  function filtrarFaixa(faixa) {
    if (pronto) map.setPaintProperty('lotes-fill', 'fill-opacity', opacidade(faixa));
  }

  return { map, pronto: prontoComLimite, atualizarDados, selecionar, focar, enquadrar, filtrarFaixa, get selecionado() { return selecionado; } };
}

class BotaoEnquadrar {
  constructor(acao) {
    this.acao = acao;
  }
  onAdd() {
    this.el = document.createElement('div');
    this.el.className = 'maplibregl-ctrl maplibregl-ctrl-group';
    this.el.innerHTML =
      '<button type="button" title="Enquadrar loteamento" aria-label="Enquadrar loteamento"><span class="material-symbols-rounded" aria-hidden="true">fit_screen</span></button>';
    this.el.querySelector('button').addEventListener('click', this.acao);
    return this.el;
  }
  onRemove() {
    this.el.remove();
  }
}
