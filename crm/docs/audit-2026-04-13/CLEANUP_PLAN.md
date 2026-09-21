# Atlas Eye — Plano de Limpeza

Plano executável para reduzir ruído no repo sem perder histórico. **Leia antes de executar** e adapte conforme revisão.

---

## Estrutura alvo

```
atlasEye/
├── README.md                   ← entry point (pitch + startup)
├── QUICKSTART.md               ← 5-min onboarding
├── DOCUMENTATION_INDEX.md      ← mapa de leitura
├── SECURITY.md                 ← NOVO — copiar de docs/audit-2026-04-13/
├── ROADMAP.md                  ← NOVO
├── CHANGELOG.md                ← NOVO (Keep a Changelog)
│
├── docs/
│   ├── ARCHITECTURE.md         ← renomeado de ARQUITECTURA_TECNICA.md
│   ├── API_REFERENCE.md
│   ├── IMPLEMENTATION_GUIDE.md
│   ├── N8N_NODE.md
│   ├── SETUP.md
│   ├── TESTING_GUIDE.md
│   ├── schema.md
│   │
│   ├── audit-2026-04-13/       ← auditoria atual (esta pasta)
│   │
│   └── archive/                ← snapshots históricos
│       ├── SETUP_PROGRESS.md
│       ├── STATUS.md
│       ├── DELIVERY_SUMMARY.md
│       ├── IMPLEMENTATION_COMPLETE.md
│       ├── STITCH_COMPLETION_REPORT.md
│       ├── findings.md
│       ├── progress.md
│       ├── task_plan.md
│       ├── PORTA_ATUALIZADA.md
│       ├── ACESSO_RAPIDO.md
│       ├── crm_functions.md
│       ├── frontend-mockups/   ← antigo frontend/
│       └── n8n-nodes-1.2.8/    ← antigo temp_old/
│
├── atlas-eye/
├── atlas-eye-mcp/
├── n8n-nodes-atlaseye/
├── trinks-mcp/                 ← decidir: completar ou arquivar
├── supabase/
├── database/
├── scripts/
│   └── archive/                ← one-offs executados
│
├── .env.example                ← template (SEM VALORES)
├── .gitignore                  ← expandido
├── next.config.ts
├── package.json
├── package-lock.json
└── tsconfig.json
```

---

## Fase 1 — Deletar lixo óbvio

```bash
cd C:/Users/venan/.gemini/antigravity/scratch/atlasEye

# Outputs do Stitch MCP (~120KB)
rm stitch_chat1_fixed.json stitch_chat1_result.json
rm stitch_chat2_fixed.json stitch_chat2_result.json
rm stitch_pipeline_fixed.json stitch_pipeline_result.json
rm stitch_tools_full.json
rm stitch_edit_screens_fixed.js stitch_pipeline_edit.js

# Triplicata de debug
rm check_advisors.js check_advisors2.js check_advisors3.js

# Diretórios vazios
rmdir Planning "UI-UX Improvements" 2>/dev/null

# 🔴 Migrations perigosas (bypass RLS) — auditar antes se foram aplicadas
rm database/018_test_bypass_rls.sql
rm database/022_disable_rls_temp.sql
```

---

## Fase 2 — Arquivar históricos

```bash
mkdir -p docs/archive

# Snapshots de status desatualizados
mv SETUP_PROGRESS.md STATUS.md docs/archive/
mv DELIVERY_SUMMARY.md IMPLEMENTATION_COMPLETE.md docs/archive/
mv STITCH_COMPLETION_REPORT.md docs/archive/

# Logs de investigação
mv findings.md progress.md task_plan.md docs/archive/

# Notas que viraram linha no README
mv PORTA_ATUALIZADA.md ACESSO_RAPIDO.md docs/archive/

# Docs redundantes
mv crm_functions.md docs/archive/  # conteúdo já em schema.md

# Mockups Stitch (substituídos pelo app real)
mv frontend docs/archive/frontend-mockups

# Build antigo do n8n node
mv temp_old docs/archive/n8n-nodes-1.2.8
```

---

## Fase 3 — Mover docs técnicas para `docs/`

```bash
mv ARQUITECTURA_TECNICA.md docs/ARCHITECTURE.md
mv API_REFERENCE.md docs/
mv IMPLEMENTATION_GUIDE.md docs/
mv N8N_NODE.md docs/
mv SETUP.md docs/
mv TESTING_GUIDE.md docs/
mv schema.md docs/
```

Depois, atualizar links em `README.md`, `QUICKSTART.md` e `DOCUMENTATION_INDEX.md`.

---

## Fase 4 — Scripts

```bash
cd scripts
mkdir -p archive

# One-offs que já rodaram
mv check-todabella.ts fix-lead-names.ts archive/

# Decidir duplicatas
rm sync-avatars.mjs   # manter .ts
rm sync-groups.mjs    # manter .ts
```

Na raiz, mover para `scripts/`:
```bash
mv apply_006.js deploy_functions.js scripts/archive/
mv download_htmls.sh scripts/archive/
mv setup-project.sh scripts/  # manter se ainda usado
```

---

## Fase 5 — Renumerar migrations

Duplicatas de número (risco de ordem indefinida):

| Atual | Renomear para |
|---|---|
| `004_add_org_profile_fields.sql` | manter |
| `004_security_fixes.sql` | `004b_security_fixes.sql` |
| `005_create_logo_bucket.sql` | `005b_create_logo_bucket.sql` |
| `005_rpc_functions.sql` | manter como `005` |
| `007_custom_fields.sql` | manter |
| `007_vault_secrets.sql` | `007b_vault_secrets.sql` |
| `009_categories_rls_fix.sql` | `009b_categories_rls_fix.sql` |
| `009_rpc_rbac_fix.sql` | manter como `009` |
| `010_add_value_and_goals.sql` | manter |
| `010_definitions_rls_fix.sql` | `010b_definitions_rls_fix.sql` |

**Cadeia de fix RLS (015→022)** — consolidar em um único arquivo `023_rls_final.sql` e arquivar os intermediários em `database/archive/`:

```bash
mkdir -p database/archive
mv database/015_fix_is_org_member.sql database/archive/
mv database/016_fix_search_path_rls.sql database/archive/
mv database/017_fix_is_org_member_plpgsql.sql database/archive/
mv database/019_fix_is_org_member_final.sql database/archive/
mv database/019_fix_rls_definitivo.sql database/archive/
mv database/020_fix_is_org_member_bomba.sql database/archive/
mv database/021_fix_rls_final_version.sql database/archive/
mv database/021_rescue_rls.sql database/archive/
# manter apenas 023/024/025 que são a versão production-safe
```

---

## Fase 6 — Arquivos sensíveis

```bash
# Adicionar ao .gitignore
cat >> .gitignore <<'EOF'

# Secrets
.env
.env.*
!.env.example
.vercel/
**/.vercel/
.npmrc
!.npmrc.example

# Deploy scripts com secrets
atlas-eye-mcp/deploy.mjs
deploy_functions.js
apply_*.js
EOF

# Remover do tracking (mantém localmente)
git rm --cached .env.local 2>/dev/null || true
git rm --cached atlas-eye/.vercel/.env.production.local 2>/dev/null || true
git rm --cached n8n-nodes-atlaseye/.npmrc 2>/dev/null || true

# Criar templates
cat > .env.example <<'EOF'
NEXT_PUBLIC_SUPABASE_URL=
NEXT_PUBLIC_SUPABASE_ANON_KEY=
SUPABASE_SERVICE_ROLE_KEY=
UAZAPI_SERVER_URL=
UAZAPI_ADMIN_TOKEN=
EOF
```

Ver `SECURITY.md` para o processo completo de rotação e limpeza de histórico com `git-filter-repo`.

---

## Fase 7 — trinks-mcp: decisão

**Opção A — Completar:** criar `trinks-mcp/src/index.ts` replicando `atlas-eye-mcp/src/index.ts`, registrando `AgendamentosTools` e `ClientesTools`, compilando, testando. Adicionar `.env.example` e README.

**Opção B — Arquivar:** `mv trinks-mcp docs/archive/trinks-mcp` enquanto prioridade não for salões.

---

## Checklist

- [ ] Fase 1 — lixo deletado
- [ ] Fase 2 — históricos arquivados
- [ ] Fase 3 — docs movidas para `docs/`
- [ ] Fase 4 — scripts organizados
- [ ] Fase 5 — migrations renumeradas
- [ ] Fase 6 — secrets fora do git
- [ ] Fase 7 — decisão sobre trinks-mcp
- [ ] Atualizar `README.md`, `QUICKSTART.md`, `DOCUMENTATION_INDEX.md` com novos paths
- [ ] Commit com mensagem: `chore: cleanup after 2026-04-13 audit`
