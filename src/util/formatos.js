const numero = new Intl.NumberFormat('pt-BR', { minimumFractionDigits: 2, maximumFractionDigits: 2 });

/** 'AAAA-MM-DD' → 'DD/MM/AAAA' (sem passar por Date, para não deslocar o fuso). */
export function data(iso) {
  if (!iso) return '—';
  const [a, m, d] = String(iso).slice(0, 10).split('-');
  return `${d}/${m}/${a}`;
}

export function dataHora(iso) {
  if (!iso) return '—';
  return new Date(iso).toLocaleString('pt-BR', { dateStyle: 'short', timeStyle: 'short' });
}

export function m2(v) {
  return v == null ? '—' : `${numero.format(v)} m²`;
}

export function metros(v) {
  return v == null ? '—' : `${numero.format(v)} m`;
}

/** Link do WhatsApp para telefone brasileiro (acrescenta 55 se faltar). */
export function whatsapp(tel) {
  const d = String(tel || '').replace(/\D/g, '');
  if (d.length < 10) return null;
  return `https://wa.me/${d.startsWith('55') ? d : `55${d}`}`;
}

export function telefoneLink(tel) {
  const d = String(tel || '').replace(/\D/g, '');
  return d ? `tel:${d}` : null;
}

/** Normaliza texto para busca: minúsculas e sem acentos. */
export function normalizar(t) {
  return String(t || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .toLowerCase();
}
