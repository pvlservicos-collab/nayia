# Atlas Eye - Guia de Desenvolvimento

## Pre-requisitos

- **Node.js** v18+ (recomendado v20 LTS)
- **npm** v9+

cd C:\Users\venan\.gemini\antigravity\scratch\atlasEye\atlas-eye
npm run dev


## Como rodar o projeto

### 1. Entrar no diretorio correto

```bash
cd atlas-eye
```

> **IMPORTANTE:** O projeto Next.js fica dentro da pasta `atlas-eye/`, NAO na raiz do repositorio.
> Rodar `npm run dev` na raiz vai abrir uma pagina em branco porque nao existe codigo fonte la.

### 2. Instalar dependencias

```bash
npm install
```

### 3. Configurar variaveis de ambiente

Crie um arquivo `.env.local` na pasta `atlas-eye/` com:

```
NEXT_PUBLIC_SUPABASE_URL=sua_url_aqui
NEXT_PUBLIC_SUPABASE_ANON_KEY=sua_chave_aqui
```

### 4. Iniciar o servidor de desenvolvimento

```bash
npm run dev
```

### 5. Acessar no navegador

Abra [http://localhost:3000](http://localhost:3000)

## Comandos disponiveis

| Comando | Descricao |
| --- | --- |
| `npm run dev` | Servidor de desenvolvimento |
| `npm run build` | Build de producao |
| `npm run start` | Rodar build de producao |
| `npm run lint` | Verificar erros de lint |
| `npm run type-check` | Verificar tipos TypeScript |

## Estrutura de pastas

```
atlas-eye/
  src/
    app/           -> Paginas (App Router do Next.js 15)
      pipeline/    -> Pagina do Pipeline Kanban
      chat/        -> Pagina do Chat com IA
    components/    -> Componentes React
      Pipeline/    -> Componentes do Kanban board
      Chat/        -> Componentes do chat
      Shared/      -> Navbar, FilterBar, etc.
    hooks/         -> Custom hooks (useAuth, usePipeline, useLeads)
    lib/           -> Utilitarios, tipos, cliente Supabase
  public/
    fonts/         -> Fonte Neue Haas Grotesk Display Pro
```

## Problemas comuns

**Pagina em branco:**
Verifique se voce esta rodando `npm run dev` dentro da pasta `atlas-eye/` e NAO na raiz do repositorio.

**Estilos nao aparecem:**
Rode `rm -rf .next && npm run dev` para limpar o cache do Next.js e recompilar o Tailwind CSS.
