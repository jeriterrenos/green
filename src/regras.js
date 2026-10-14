// Regras de negócio puras — espelham as funções SQL do PLANO § 6.3 e são testadas em tests/regras.test.js

export const TOTAL_ETAPAS = 9;
export const ETAPA_FIM_PREFEITURA = 4; // ITBI pago → lote passa para o cartório

export function temTexto(valor) {
  return typeof valor === 'string' ? valor.trim() !== '' : valor != null;
}

export function calcularFaixa({ temAdquirente, temProcesso, ultimaEtapa }) {
  if (!temProcesso) return temAdquirente ? 'sem_processo' : 'disponivel';
  if (ultimaEtapa >= TOTAL_ETAPAS) return 'concluido';
  if (ultimaEtapa >= ETAPA_FIM_PREFEITURA) return 'cartorio';
  return 'prefeitura';
}

export function percentual(ultimaEtapa) {
  return Math.round((ultimaEtapa / TOTAL_ETAPAS) * 100);
}

/** Próxima etapa a concluir, ou null se não há processo ou se já concluiu tudo. */
export function proximaEtapa({ temProcesso, ultimaEtapa }) {
  if (!temProcesso || ultimaEtapa >= TOTAL_ETAPAS) return null;
  return ultimaEtapa + 1;
}

/** Data local de hoje em ISO (AAAA-MM-DD), sem deslocamento de fuso. */
export function hojeISO(agora = new Date()) {
  const z = (n) => String(n).padStart(2, '0');
  return `${agora.getFullYear()}-${z(agora.getMonth() + 1)}-${z(agora.getDate())}`;
}

/** Retorna mensagem de erro ou null. Datas em ISO comparam corretamente como texto. */
export function validarData(iso, hoje = hojeISO()) {
  if (!iso || !/^\d{4}-\d{2}-\d{2}$/.test(iso)) return 'Informe a data.';
  if (iso > hoje) return 'A data não pode ser futura.';
  return null;
}

/** Valida um ok (ou "não se aplica") numa etapa. Retorna mensagem de erro ou null. */
export function validarConclusao({ temProcesso, ultimaEtapa, etapa, dispensavel, naoSeAplica, dataEvento, observacao, hoje }) {
  if (!temProcesso) return 'Processo não iniciado para este lote.';
  const erroData = validarData(dataEvento, hoje);
  if (erroData) return erroData;
  if (etapa !== ultimaEtapa + 1) return `A próxima etapa a concluir é a ${ultimaEtapa + 1}.`;
  if (naoSeAplica && !dispensavel) return 'Esta etapa não pode ser marcada como "não se aplica".';
  if (naoSeAplica && !temTexto(observacao)) return 'Explique por que a etapa não se aplica.';
  return null;
}

/** Valida o início do processo. Retorna mensagem de erro ou null. */
export function validarInicio({ temAdquirente, temProcesso, dataSolicitacao, hoje }) {
  if (temProcesso) return 'Este lote já tem processo iniciado.';
  if (!temAdquirente) return 'Lote disponível: informe o adquirente antes de iniciar o processo.';
  return validarData(dataSolicitacao, hoje);
}

/** Converte o campo `etapa` (0–9) do arquivo de lotes no estado inicial do processo — PLANO § 12.2. */
export function cargaInicial({ etapa, temAdquirente, naoAplica = [] }) {
  const n = Number(etapa) || 0;
  if (n < 0 || n > TOTAL_ETAPAS || !Number.isInteger(n)) {
    return { erro: `Valor de etapa inválido: ${etapa}` };
  }
  if (n > 0 && !temAdquirente) return { erro: 'Etapa preenchida em lote sem adquirente.' };
  if (n === 0) return { processo: false, etapas: [] };
  const etapas = [];
  for (let id = 1; id <= n; id++) {
    etapas.push({ etapa_id: id, status: naoAplica.includes(id) ? 'nao_aplica' : 'concluida' });
  }
  return { processo: true, etapas };
}
