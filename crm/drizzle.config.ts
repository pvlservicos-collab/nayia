import type { Config } from 'drizzle-kit'
import { config } from 'dotenv'

// O drizzle-kit carrega .env, mas NÃO .env.local — que é onde este projeto guarda
// a DATABASE_URL (e o único dos dois que o git ignora). Sem isto, `db:push` e
// `db:studio` rodavam contra `undefined` e falhavam sem dizer por quê.
config({ path: '.env.local' })

export default {
  schema: './src/lib/schema.ts',
  out: './drizzle',
  dialect: 'postgresql',
  dbCredentials: {
    url: process.env.DATABASE_URL!,
  },
} satisfies Config
