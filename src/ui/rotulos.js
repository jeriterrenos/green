// Rótulos de listas fixas e ícones usados no painel e no formulário de cadastro

export const ESTADOS_CIVIS = {
  solteiro: 'Solteiro(a)',
  casado: 'Casado(a)',
  uniao_estavel: 'União estável',
  divorciado: 'Divorciado(a)',
  separado: 'Separado(a) judicialmente',
  viuvo: 'Viúvo(a)',
};

export const REGIMES_BENS = {
  comunhao_parcial: 'Comunhão parcial de bens',
  comunhao_universal: 'Comunhão universal de bens',
  separacao_total: 'Separação total de bens',
  separacao_obrigatoria: 'Separação obrigatória de bens',
  participacao_final: 'Participação final nos aquestos',
};

/** Símbolo do WhatsApp (balão verde com fone), em SVG para não depender de fonte de ícones. */
export function iconeWhatsapp() {
  return `<svg class="icone-zap" viewBox="0 0 24 24" width="22" height="22" aria-hidden="true">
    <path fill="#25D366" d="M12 2a10 10 0 0 0-8.6 15.1L2 22l5-1.3A10 10 0 1 0 12 2z"/>
    <path fill="#fff" d="M9.1 7.2c-.2-.5-.5-.5-.7-.5h-.6c-.2 0-.6.1-.9.4-.3.3-1.2 1.1-1.2 2.8s1.2 3.2 1.4 3.5c.2.2 2.3 3.6 5.6 4.9 2.8 1.1 3.3.9 3.9.8.6-.1 1.9-.8 2.2-1.5.3-.8.3-1.4.2-1.5-.1-.1-.3-.2-.7-.4l-2.2-1.1c-.3-.1-.5-.2-.7.2l-1 1.2c-.2.2-.4.2-.7.1-.3-.2-1.4-.5-2.6-1.6-1-.9-1.6-1.9-1.8-2.2-.2-.3 0-.5.1-.7l.5-.6c.2-.2.2-.4.3-.6.1-.2 0-.4 0-.6l-1-2.6z"/>
  </svg>`;
}
