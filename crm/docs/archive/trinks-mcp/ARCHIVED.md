# trinks-mcp — ARQUIVADO

**Data:** 2026-04-13
**Motivo:** projeto incompleto (falta `src/index.ts`) e fora do escopo atual do Atlas Eye (domínio de salão de beleza via Trinks API, IDs int incompatíveis com UUIDs do Atlas Eye).

## O que havia

- **21 tools planejadas**:
  - Agendamentos (10): listar, buscar, criar, atualizar, confirmar, cancelar, finalizar, marcar faltou, em atendimento, listar agendas de profissionais.
  - Clientes (11): CRUD, crédito, vale-presente, etiquetas (listar/adicionar/remover), telefones.
- Schemas Zod completos em `src/tools/agendamentos.ts` e `src/tools/clientes.ts`.
- HTTP client em `src/http-client.ts`.
- **Faltando:** `src/index.ts` de registro do servidor MCP.

## Para reativar no futuro

1. Mover de volta para a raiz: `mv docs/archive/trinks-mcp ./trinks-mcp`
2. Criar `src/index.ts` copiando o padrão de `atlas-eye-mcp/src/index.ts`:
   - Registrar `AgendamentosTools` e `ClientesTools`
   - Suportar stdio + HTTP (flag `--http`)
3. Criar `.env.example` com `TRINKS_API_KEY` e `TRINKS_ESTABELECIMENTO_ID`
4. Se for integrar com Atlas Eye, adicionar camada de tradução int ↔ UUID.

Ver `docs/audit-2026-04-13/PROJECT_STATUS.md` seção "trinks-mcp" para detalhes.
