import { Pool } from 'pg'
import { drizzle } from 'drizzle-orm/node-postgres'
import * as schema from './schema'

let _db: ReturnType<typeof drizzle<typeof schema>> | null = null

function getDb() {
  if (!_db) {
    const url = process.env.DATABASE_URL
    if (!url) throw new Error('DATABASE_URL não definida nas variáveis de ambiente')
    const pool = new Pool({ connectionString: url })
    _db = drizzle(pool, { schema })
  }
  return _db
}

export const db = new Proxy({} as ReturnType<typeof drizzle<typeof schema>>, {
  get(_, prop) {
    const instance = getDb() as any
    const value = instance[prop]
    return typeof value === 'function' ? value.bind(instance) : value
  },
})

export type DB = typeof db
