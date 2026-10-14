import { esc, icone } from '../util/html.js';

export function toast(mensagem, tipo = 'ok') {
  const raiz = document.getElementById('toasts');
  const t = document.createElement('div');
  t.className = `toast toast-${tipo}`;
  t.setAttribute('role', tipo === 'erro' ? 'alert' : 'status');
  t.innerHTML = `${icone(tipo === 'erro' ? 'error' : 'check_circle')}<span>${esc(mensagem)}</span>`;
  raiz.append(t);
  setTimeout(() => t.classList.add('saindo'), 3200);
  setTimeout(() => t.remove(), 3600);
}
