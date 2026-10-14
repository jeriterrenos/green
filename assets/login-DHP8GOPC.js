import{d as s}from"./index-BDifNr0v.js";import"./maplibre-wqmL2Hxp.js";function p({aoLogar:t}){if(document.querySelector(".tela-login"))return;const e=document.createElement("div");e.className="tela-login",e.innerHTML=`
    <div class="card-login" role="dialog" aria-modal="true" aria-labelledby="login-titulo">
      <img src="/green/img/logo-green-terrenos.png" alt="Green Terrenos" class="login-logo" />
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
  `,document.body.appendChild(e);const a=e.querySelector("#form-login"),n=e.querySelector("#btn-entrar"),i=e.querySelector("#login-erro"),c=e.querySelector("#btn-esqueci");a.email.focus(),a.addEventListener("submit",async r=>{r.preventDefault(),i.hidden=!0,n.disabled=!0,n.innerHTML="<span>Entrando…</span>";const o=a.email.value.trim(),d=a.password.value;try{await s.login(o,d),e.remove(),t&&t()}catch(l){i.textContent=l.message==="Invalid login credentials"?"E-mail ou senha incorretos.":l.message||"Erro ao realizar login.",i.hidden=!1,n.disabled=!1,n.innerHTML="<span>Entrar</span>"}}),c.addEventListener("click",async()=>{const r=a.email.value.trim()||prompt("Digite seu e-mail para receber o link de recuperação de senha:");if(r)try{await s.recuperarSenha(r),alert("Link de recuperação enviado para "+r+". Verifique sua caixa de entrada.")}catch(o){alert("Erro: "+(o.message||"Não foi possível enviar o e-mail de recuperação."))}})}export{p as exibirTelaLogin};
