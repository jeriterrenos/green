// Tela de login e recuperação de senha — PLANO § 8.1
import { dados } from '../data/index.js';

export function exibirTelaLogin({ aoLogar }) {
  // Evita duplicar se já existir
  if (document.querySelector('.tela-login')) return;

  const container = document.createElement('div');
  container.className = 'tela-login';
  container.innerHTML = `
    <div class="card-login" role="dialog" aria-modal="true" aria-labelledby="login-titulo">
      <img src="${import.meta.env.BASE_URL}img/logo-green-terrenos.png" alt="Green Terrenos" class="login-logo" />
      <h2 id="login-titulo">Transferência de Matrículas</h2>
      <p class="login-sub">Acesse com suas credenciais do loteamento</p>
      
      <form class="form-login" id="form-login">
        <label class="campo">
          <span>E-mail</span>
          <input type="email" name="email" required autocomplete="email" placeholder="seu@email.com" />
        </label>
        <label class="campo">
          <span>Senha</span>
          <input type="password" name="password" required autocomplete="current-password" placeholder="••••••••" />
        </label>
        
        <div class="login-erro" id="login-erro" hidden></div>
        
        <button type="submit" class="btn btn-primario btn-entrar" id="btn-entrar">
          <span>Entrar</span>
        </button>
        
        <button type="button" class="btn-link" id="btn-esqueci">Esqueci minha senha</button>
      </form>
    </div>
  `;

  document.body.appendChild(container);

  const form = container.querySelector('#form-login');
  const btnEntrar = container.querySelector('#btn-entrar');
  const divErro = container.querySelector('#login-erro');
  const btnEsqueci = container.querySelector('#btn-esqueci');

  form.email.focus();

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    divErro.hidden = true;
    btnEntrar.disabled = true;
    btnEntrar.innerHTML = `<span>Entrando…</span>`;

    const email = form.email.value.trim();
    const password = form.password.value;

    try {
      await dados.login(email, password);
      container.remove();
      if (aoLogar) aoLogar();
    } catch (err) {
      divErro.textContent =
        err.message === 'Invalid login credentials'
          ? 'E-mail ou senha incorretos.'
          : err.message || 'Erro ao realizar login.';
      divErro.hidden = false;
      btnEntrar.disabled = false;
      btnEntrar.innerHTML = `<span>Entrar</span>`;
    }
  });

  btnEsqueci.addEventListener('click', async () => {
    const email = form.email.value.trim() || prompt('Digite seu e-mail para receber o link de recuperação de senha:');
    if (!email) return;
    try {
      await dados.recuperarSenha(email);
      alert('Link de recuperação enviado para ' + email + '. Verifique sua caixa de entrada.');
    } catch (err) {
      alert('Erro: ' + (err.message || 'Não foi possível enviar o e-mail de recuperação.'));
    }
  });
}
