# ⚠️ MIGRATIONS PERIGOSAS — NÃO APLICAR

Arquivadas em 2026-04-13 após auditoria.

| Arquivo | Problema |
|---|---|
| `018_test_bypass_rls.sql` | Policy com `USING (true)` — **abre o banco inteiro** |
| `022_disable_rls_temp.sql` | `ALTER TABLE ... DISABLE ROW LEVEL SECURITY` em massa |

Mantidos como **evidência histórica** do debugging da cadeia RLS 015→021. A versão production-safe está em `database/023_rls_production_safe.sql` (+ partes 2 e 3).

**Nunca incluir estes arquivos em deploy automático.**
