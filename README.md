# Green Terrenos · Transferência de Matrículas

Geoportal para acompanhar a transferência de matrícula dos lotes do loteamento Green Terrenos (Cruz/CE).
Plano completo: [`PLANO_IMPLEMENTACAO.md`](PLANO_IMPLEMENTACAO.md).

## Rodar localmente

Requisitos: Node.js 20+.

```bash
npm install
npm run dev
```

Abre em **http://localhost:5173/green/** (modo demonstração: sem login, perfil admin, dados fictícios).
Publicado em: **https://jeriterrenos.github.io/green/**
Para testar no celular na mesma rede Wi-Fi: `npm run dev -- --host` e abra o endereço “Network” no aparelho.

| Comando | O que faz |
|---|---|
| `npm run dev` | servidor local com recarga automática |
| `npm test` | testes das regras de negócio (Vitest) |
| `npm run build` | gera a versão de produção em `dist/` |
| `npm run preview` | serve a versão de `dist/` localmente |

## Dados dos lotes

O site procura os lotes nesta ordem:

| Arquivo | Conteúdo | Vai para o git? |
|---|---|---|
| `public/dados-locais/lotes.geojson` | **dados reais** (nomes, contatos, protocolos) | **não** (`.gitignore`) |
| `public/mock/lotes.geojson` | mesma geometria e situação, **nomes fictícios** | sim |

Para regerar a partir de `dados antigos/.../lotes_green_terrenos_atualizado.gpkg`:

```bash
python -I scripts/gerar_mock.py          # dados reais  → public/dados-locais/
python -I scripts/gerar_mock.py --mock   # fictícios    → public/mock/
```

As alterações feitas no site (OKs, edições) ficam só no navegador; use
**menu do usuário → Restaurar dados de demonstração** para voltar ao estado do arquivo.

> ⚠️ `npm run build` local copia `public/dados-locais/` para `dist/`. Não publique um `dist/` gerado na sua máquina;
> a publicação deve ser feita pelo GitHub Actions, que não tem acesso aos dados reais.

> A pasta `dados antigos/` (com dados pessoais reais) está no `.gitignore` e nunca deve ser versionada.
