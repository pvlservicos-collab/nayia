/**
 * ARQUIVO LEGADO — substituído por src/lib/db.ts (Neon/Drizzle)
 * Mantido para evitar erros de importação em arquivos ainda não migrados.
 */
export function createSupabaseAdmin() {
  throw new Error(
    '[MIGRADO] createSupabaseAdmin() foi removido. ' +
    'Importe { db } from "@/lib/db" e use Drizzle ORM.'
  )
}
