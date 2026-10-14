// Todo texto vindo dos dados passa por esc() antes de ir ao DOM (evita XSS) — PLANO § 11.
const MAPA = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };

export function esc(valor) {
  return valor == null ? '' : String(valor).replace(/[&<>"']/g, (c) => MAPA[c]);
}

export function el(html) {
  const t = document.createElement('template');
  t.innerHTML = html.trim();
  return t.content.firstElementChild;
}

export function icone(nome, classe = '') {
  return `<span class="material-symbols-rounded ${classe}" aria-hidden="true">${nome}</span>`;
}
