// Modal genérico: diálogo centralizado no desktop, tela cheia no celular (PLANO § 3.2).
import { esc, icone } from '../util/html.js';
import { desempilhar, empilhar } from './navegacao.js';

/**
 * @param {{ titulo: string, corpo: string, acoes: {rotulo: string, tipo?: string, icone?: string, aoClicar?: (ctx) => any}[] }} op
 * aoClicar pode lançar Error (mensagem exibida no modal) ou retornar false para manter aberto.
 */
export function abrirModal({ titulo, corpo, acoes, classe = '' }) {
  const dlg = document.createElement('dialog');
  dlg.className = `modal ${classe}`;
  dlg.innerHTML = `
    <form method="dialog" class="modal-caixa" novalidate>
      <header class="modal-cabeca">
        <h2>${esc(titulo)}</h2>
        <button type="button" class="icone-btn" data-fechar aria-label="Fechar">${icone('close')}</button>
      </header>
      <div class="modal-corpo">${corpo}<p class="modal-erro" role="alert" hidden></p></div>
      <footer class="modal-acoes">
        ${acoes
          .map(
            (a, i) =>
              `<button type="button" class="btn btn-${a.tipo ?? 'secundario'}" data-acao="${i}">${a.icone ? icone(a.icone) : ''}${esc(a.rotulo)}</button>`,
          )
          .join('')}
      </footer>
    </form>`;
  document.getElementById('modal-raiz').append(dlg);

  let fechado = false;
  const fecharPorVoltar = () => fechar(true);
  function fechar(porVoltar = false) {
    if (fechado) return;
    fechado = true;
    if (!porVoltar) desempilhar(fecharPorVoltar);
    dlg.close();
    dlg.remove();
  }

  const erro = dlg.querySelector('.modal-erro');
  const ctx = {
    dlg,
    campo: (nome) => dlg.querySelector(`[name="${nome}"]`),
    valor: (nome) => dlg.querySelector(`[name="${nome}"]`)?.value ?? '',
    marcado: (nome) => Boolean(dlg.querySelector(`[name="${nome}"]`)?.checked),
    fechar,
  };

  dlg.querySelector('[data-fechar]').addEventListener('click', () => fechar());
  dlg.addEventListener('cancel', (e) => {
    e.preventDefault();
    fechar();
  });
  dlg.querySelectorAll('[data-acao]').forEach((b) =>
    b.addEventListener('click', async () => {
      const acao = acoes[Number(b.dataset.acao)];
      if (!acao.aoClicar) return fechar();
      erro.hidden = true;
      b.disabled = true;
      try {
        const r = await acao.aoClicar(ctx);
        if (r !== false) fechar();
      } catch (e) {
        erro.textContent = e.message;
        erro.hidden = false;
      } finally {
        b.disabled = false;
      }
    }),
  );

  empilhar(fecharPorVoltar);
  dlg.showModal();
  dlg.querySelector('input:not([type="radio"]), textarea, select')?.focus();
  return ctx;
}
