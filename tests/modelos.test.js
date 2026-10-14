import { describe, expect, it } from 'vitest';
import { MODELOS, textoCadastroImobiliario, textoSolicitacaoItbi } from '../src/data/modelos.js';

const lote = { matricula: '1835', area_m2: 1190.93, perimetro_m: 139.79, bci_inscricao: '9703' };

describe('texto do Cadastro Imobiliário (etapa 1)', () => {
  const t = textoCadastroImobiliario(lote);
  it('é sempre em nome da RR Terrenos', () => {
    expect(t).toContain('Proprietário: RR TERRENOS E INCORPORAÇÃO LTDA');
    expect(t).toContain('CPF/CNPJ: 22.834.252/0001-59');
  });
  it('troca matrícula, área e perímetro (formato brasileiro)', () => {
    expect(t).toContain('Matrícula: 1835');
    expect(t).toContain('Área: 1.190,93 m²');
    expect(t).toContain('Perímetro: 139,79 m');
  });
  it('sinaliza dados faltantes', () => {
    expect(textoCadastroImobiliario({ matricula: '1' })).toContain('Área: [informar] m²');
    expect(MODELOS.bci.pendencias({ matricula: '1' })).toEqual(['área', 'perímetro']);
  });
});

describe('texto da solicitação de ITBI (etapa 2)', () => {
  it('usa o código do BCI e a matrícula', () => {
    const t = textoSolicitacaoItbi(lote);
    expect(t).toContain('Imóvel de Código: 9703');
    expect(t).toContain('Matrícula: 1835');
  });
  it('avisa quando falta o código do BCI', () => {
    expect(textoSolicitacaoItbi({ matricula: '1' })).toContain('[informar o código do imóvel no BCI]');
    expect(MODELOS.itbi.pendencias({})).toEqual(['código do imóvel no BCI', 'matrícula', 'adquirente']);
    expect(MODELOS.itbi.bloqueiaSemDados).toBe(true);
  });
});

describe('liberação do texto do ITBI', async () => {
  const { faltandoParaItbi } = await import('../src/data/modelos.js');
  const completo = {
    nome: 'Fulano', tipo_pessoa: 'PF', documento: '12345678909', rg: '123', estado_civil: 'solteiro',
    telefone: '(88) 9', endereco: 'Rua A',
  };
  it('libera com todos os dados mínimos', () => {
    expect(faltandoParaItbi({ ...lote, adquirentes: [completo] })).toEqual([]);
  });
  it('bloqueia sem código do BCI e lista o que falta', () => {
    expect(faltandoParaItbi({ matricula: '1', adquirentes: [{ ...completo, rg: null }] })).toEqual(['código do imóvel no BCI', 'RG']);
  });
  it('casado exige nome e CPF do cônjuge', () => {
    const f = faltandoParaItbi({ ...lote, adquirentes: [{ ...completo, estado_civil: 'casado' }] });
    expect(f).toEqual(['nome do(a) cônjuge', 'CPF do(a) cônjuge']);
  });
  it('identifica o segundo adquirente', () => {
    const f = faltandoParaItbi({ ...lote, adquirentes: [completo, { nome: 'Beltrana', tipo_pessoa: 'PJ' }] });
    expect(f).toEqual(['CNPJ (adquirente 2)', 'telefone (adquirente 2)', 'endereço (adquirente 2)']);
  });
});
