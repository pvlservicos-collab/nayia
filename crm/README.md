# TitaCRM

CRM multicanal (WhatsApp/Instagram) multi-tenant. Next.js 15 + React 19, Drizzle ORM
sobre Postgres, NextAuth v5, Pusher, Vercel Blob.

## Rodando localmente

```bash
npm install
npm run dev
```

Preencha `.env.local` com as credenciais do seu ambiente (banco, NextAuth, Pusher,
Vercel Blob — ver `CLAUDE.md` pra detalhes de arquitetura específicos deste projeto).

## Build

```bash
npm run type-check
npm run build
```
