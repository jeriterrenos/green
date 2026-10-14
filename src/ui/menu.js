// Menu do usuário (cabeçalho). Na demonstração: perfil fixo admin + restaurar dados.
import { estado } from '../estado.js';
import { esc, icone } from '../util/html.js';
import { restaurarDemo } from './acoes.js';

export function iniciarMenu(raiz, { demo }) {
  const p = estado.perfil;
  raiz.innerHTML = `
    <button type="button" class="icone-btn menu-botao" aria-haspopup="true" aria-expanded="false" aria-label="Menu do usuário">
      ${icone('account_circle')}<span class="menu-nome so-desktop">${esc(p?.nome ?? '')}</span>
    </button>
    <div class="menu-lista" role="menu" hidden>
      <p class="menu-perfil">${icone('person')}<span>${esc(p?.nome)}<small>${p?.papel === 'admin' ? 'Administrador' : 'Leitor'}</small></span></p>
      ${demo ? `<button type="button" role="menuitem" data-acao="restaurar">${icone('restart_alt')}Restaurar dados de demonstração</button>` : `<button type="button" role="menuitem" data-acao="sair">${icone('logout')}Sair da conta</button>`}
      <div class="menu-precision">Um produto <img src="${import.meta.env.BASE_URL}img/precision-plus.png" alt="Precision+"></div>
    </div>`;
  const botao = raiz.querySelector('.menu-botao');
  const lista = raiz.querySelector('.menu-lista');
  const alternar = (abrir = lista.hidden) => {
    lista.hidden = !abrir;
    botao.setAttribute('aria-expanded', String(abrir));
  };
  botao.addEventListener('click', () => alternar());
  document.addEventListener('click', (e) => {
    if (!raiz.contains(e.target)) alternar(false);
  });
  lista.addEventListener('click', async (e) => {
    const b = e.target.closest('[data-acao]');
    if (!b) return;
    alternar(false);
    if (b.dataset.acao === 'restaurar') restaurarDemo();
    if (b.dataset.acao === 'sair') {
      const { dados } = await import('../data/index.js');
      if (dados.logout) await dados.logout();
      window.location.reload();
    }
  });
}
