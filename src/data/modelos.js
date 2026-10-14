// Textos-padrão para colar no portal de Tributos da Prefeitura de Cruz (requisições eletrônicas).
// Baseados nas requisições já enviadas pela RR Terrenos (#2063–#2070 para BCI, #1698/#2340 para ITBI).
// O requerente é sempre a RR Terrenos; mudam apenas a matrícula e os dados do imóvel.

/** Nova requisição no portal de serviços (Tributos) da Prefeitura de Cruz. */
export const PORTAL_TRIBUTOS = 'https://servicos2.speedgov.com.br/cruz/requisicoes/new';

export const REQUERENTE = {
  nome: 'RR TERRENOS E INCORPORAÇÃO LTDA',
  cnpj: '22.834.252/0001-59',
};

export const IMOVEL_PADRAO = {
  logradouro: 'Rua Sem Denominação Oficial, S/N.º, Córrego dos Anas',
  municipio: 'Cruz-CE',
  cartorio: 'Cartório Mozart Sales, de Cruz (01.971-1)',
};

const numero = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
const medida = (v, unidade) => (v == null || v === '' ? `[informar] ${unidade}` : `${numero.format(Number(v))} ${unidade}`);

/** Etapa 1 — Requerimento de Inscrição no Cadastro Imobiliário. */
export function textoCadastroImobiliario(lote) {
  return [
    'Requerimento de Inscrição no Cadastro Imobiliário',
    '',
    'Venho, por meio deste, solicitar a inscrição do imóvel abaixo descrito no Cadastro Imobiliário deste Município, conforme levantamento topográfico realizado.',
    '',
    `Matrícula: ${lote.matricula ?? '[informar]'}`,
    `Proprietário: ${REQUERENTE.nome}`,
    `CPF/CNPJ: ${REQUERENTE.cnpj}`,
    `Logradouro: ${IMOVEL_PADRAO.logradouro}`,
    `Município: ${IMOVEL_PADRAO.municipio}`,
    `Cartório (CNS): ${IMOVEL_PADRAO.cartorio}`,
    `Área: ${medida(lote.area_m2, 'm²')}`,
    `Perímetro: ${medida(lote.perimetro_m, 'm')}`,
    '',
    'Declaro que todas as informações aqui prestadas são verdadeiras e que os documentos anexos comprovam a veracidade dos dados apresentados, estando o imóvel georreferenciado conforme normas técnicas vigentes.',
    '',
    'Solicito, portanto, a devida análise e a efetivação do cadastro.',
    '',
    'Atenciosamente,',
  ].join('\n');
}

/** Etapa 2 — Solicitação de emissão do ITBI (usa o código do imóvel gerado no BCI). */
export function textoSolicitacaoItbi(lote) {
  const codigo = lote.bci_inscricao || '[informar o código do imóvel no BCI]';
  return [
    'Solicito à Secretaria de Infraestrutura a emissão do Imposto de Transmissão de Bens Imóveis (ITBI), com a finalidade de viabilizar a transferência de propriedade do imóvel descrito neste processo.',
    '',
    `Imóvel de Código: ${codigo}`,
    `Matrícula: ${lote.matricula ?? '[informar]'}`,
    '',
    'Atenciosamente,',
  ].join('\n');
}

const CASADOS = ['casado', 'uniao_estavel'];
const vazio = (v) => v == null || String(v).trim() === '';

/**
 * Dados mínimos para pedir o ITBI: código do imóvel no BCI, matrícula e, de cada adquirente,
 * nome, CPF/CNPJ, telefone e endereço; pessoa física também RG e estado civil; casado(a) ou em
 * união estável, nome e CPF do(a) cônjuge.
 */
export function faltandoParaItbi(lote) {
  const falta = [];
  if (vazio(lote.bci_inscricao)) falta.push('código do imóvel no BCI');
  if (vazio(lote.matricula)) falta.push('matrícula');
  const adqs = lote.adquirentes ?? [];
  if (!adqs.length) falta.push('adquirente');
  adqs.forEach((a, i) => {
    const quem = adqs.length > 1 ? ` (adquirente ${i + 1})` : '';
    const pj = a.tipo_pessoa === 'PJ';
    const campos = [
      ['nome', pj ? 'razão social' : 'nome'],
      ['documento', pj ? 'CNPJ' : 'CPF'],
      ...(pj ? [] : [['rg', 'RG'], ['estado_civil', 'estado civil']]),
      ['telefone', 'telefone'],
      ['endereco', 'endereço'],
    ];
    for (const [c, rotulo] of campos) if (vazio(a[c])) falta.push(rotulo + quem);
    if (!pj && CASADOS.includes(a.estado_civil)) {
      if (vazio(a.conjuge_nome)) falta.push('nome do(a) cônjuge' + quem);
      if (vazio(a.conjuge_cpf)) falta.push('CPF do(a) cônjuge' + quem);
    }
  });
  return falta;
}

export const MODELOS = {
  bci: {
    titulo: 'Texto para o portal de Tributos — inscrição no Cadastro Imobiliário',
    gerar: textoCadastroImobiliario,
    // Faltas apenas avisam; o texto sai com [informar …]
    pendencias: (l) => [l.area_m2 == null && 'área', l.perimetro_m == null && 'perímetro'].filter(Boolean),
    bloqueiaSemDados: false,
  },
  itbi: {
    titulo: 'Texto para o portal de Tributos — solicitação de ITBI',
    gerar: textoSolicitacaoItbi,
    // Texto só é liberado com todos os dados mínimos preenchidos
    pendencias: faltandoParaItbi,
    bloqueiaSemDados: true,
  },
};
