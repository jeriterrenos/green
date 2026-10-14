import { describe, expect, it } from 'vitest';
import {
  calcularFaixa,
  cargaInicial,
  hojeISO,
  percentual,
  proximaEtapa,
  validarConclusao,
  validarData,
  validarInicio,
} from '../src/regras.js';

const HOJE = '2026-10-13';

describe('calcularFaixa', () => {
  it('lote sem adquirente e sem processo é disponível', () => {
    expect(calcularFaixa({ temAdquirente: false, temProcesso: false, ultimaEtapa: 0 })).toBe('disponivel');
  });
  it('com adquirente e sem processo é sem_processo', () => {
    expect(calcularFaixa({ temAdquirente: true, temProcesso: false, ultimaEtapa: 0 })).toBe('sem_processo');
  });
  it.each([
    [0, 'prefeitura'],
    [3, 'prefeitura'],
    [4, 'cartorio'],
    [8, 'cartorio'],
    [9, 'concluido'],
  ])('processo na etapa %i → %s', (ultimaEtapa, faixa) => {
    expect(calcularFaixa({ temAdquirente: true, temProcesso: true, ultimaEtapa })).toBe(faixa);
  });
});

describe('progresso', () => {
  it('percentual arredonda sobre 9 etapas', () => {
    expect(percentual(0)).toBe(0);
    expect(percentual(4)).toBe(44);
    expect(percentual(9)).toBe(100);
  });
  it('próxima etapa', () => {
    expect(proximaEtapa({ temProcesso: false, ultimaEtapa: 0 })).toBeNull();
    expect(proximaEtapa({ temProcesso: true, ultimaEtapa: 0 })).toBe(1);
    expect(proximaEtapa({ temProcesso: true, ultimaEtapa: 9 })).toBeNull();
  });
});

describe('validações', () => {
  it('data obrigatória e não futura', () => {
    expect(validarData('', HOJE)).toMatch(/Informe/);
    expect(validarData('2026-10-14', HOJE)).toMatch(/futura/);
    expect(validarData('2026-10-13', HOJE)).toBeNull();
  });
  it('hojeISO usa a data local', () => {
    expect(hojeISO(new Date(2026, 0, 5, 23, 30))).toBe('2026-01-05');
  });

  const base = { temProcesso: true, ultimaEtapa: 3, dispensavel: false, naoSeAplica: false, dataEvento: HOJE, hoje: HOJE };
  it('aceita a próxima etapa', () => {
    expect(validarConclusao({ ...base, etapa: 4 })).toBeNull();
  });
  it('não deixa pular etapa', () => {
    expect(validarConclusao({ ...base, etapa: 5 })).toMatch(/próxima etapa a concluir é a 4/);
  });
  it('exige processo iniciado', () => {
    expect(validarConclusao({ ...base, temProcesso: false, etapa: 1 })).toMatch(/não iniciado/);
  });
  it('"não se aplica" só em etapa dispensável e com motivo', () => {
    const e7 = { ...base, ultimaEtapa: 6, etapa: 7, naoSeAplica: true };
    expect(validarConclusao({ ...e7, dispensavel: false, observacao: 'x' })).toMatch(/não pode/);
    expect(validarConclusao({ ...e7, dispensavel: true, observacao: '' })).toMatch(/Explique/);
    expect(validarConclusao({ ...e7, dispensavel: true, observacao: 'Sem exigências' })).toBeNull();
  });
  it('iniciar processo exige adquirente', () => {
    expect(validarInicio({ temAdquirente: false, temProcesso: false, dataSolicitacao: HOJE, hoje: HOJE })).toMatch(/disponível/);
    expect(validarInicio({ temAdquirente: true, temProcesso: true, dataSolicitacao: HOJE, hoje: HOJE })).toMatch(/já tem/);
    expect(validarInicio({ temAdquirente: true, temProcesso: false, dataSolicitacao: HOJE, hoje: HOJE })).toBeNull();
  });
});

describe('cargaInicial (campo etapa 0–9)', () => {
  it('0 → sem processo', () => {
    expect(cargaInicial({ etapa: 0, temAdquirente: true })).toEqual({ processo: false, etapas: [] });
  });
  it('N → etapas 1..N concluídas, respeitando "não se aplica"', () => {
    const r = cargaInicial({ etapa: 8, temAdquirente: true, naoAplica: [7] });
    expect(r.etapas).toHaveLength(8);
    expect(r.etapas[6]).toEqual({ etapa_id: 7, status: 'nao_aplica' });
  });
  it('etapa em lote sem adquirente é erro', () => {
    expect(cargaInicial({ etapa: 3, temAdquirente: false }).erro).toBeDefined();
  });
  it('valor fora de 0–9 é erro', () => {
    expect(cargaInicial({ etapa: 12, temAdquirente: true }).erro).toBeDefined();
  });
});
