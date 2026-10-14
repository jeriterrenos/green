// Faz o botão "voltar" do celular fechar modais e a gaveta antes de sair da página.
const pilha = [];
let ignorar = 0;

window.addEventListener('popstate', () => {
  if (ignorar > 0) {
    ignorar--;
    return;
  }
  const fechar = pilha.pop();
  if (fechar) fechar();
});

/** Registra uma camada aberta; `fechar` é chamado se o usuário apertar "voltar". */
export function empilhar(fechar) {
  pilha.push(fechar);
  history.pushState({ camada: pilha.length }, '');
  return fechar;
}

/** Remove a camada quando ela é fechada pela própria interface. */
export function desempilhar(fechar) {
  const i = pilha.lastIndexOf(fechar);
  if (i === -1) return;
  pilha.splice(i, 1);
  ignorar++;
  history.back();
}
