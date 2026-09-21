import type { NextConfig } from 'next'

const config: NextConfig = {
  reactStrictMode: true,
  eslint: { ignoreDuringBuilds: true },
  typescript: { ignoreBuildErrors: true },
  images: {
    remotePatterns: [
      // Vercel Blob URLs
      { protocol: 'https', hostname: '*.public.blob.vercel-storage.com' },
      // Avatares do WhatsApp vindos do Uazapi
      { protocol: 'https', hostname: '*.uazapi.com' },
    ],
  },
  // Variáveis de ambiente que precisam ser acessíveis no cliente
  env: {
    NEXT_PUBLIC_PUSHER_KEY: process.env.NEXT_PUBLIC_PUSHER_KEY!,
    NEXT_PUBLIC_PUSHER_CLUSTER: process.env.NEXT_PUBLIC_PUSHER_CLUSTER!,
    NEXT_PUBLIC_VAPID_PUBLIC_KEY: process.env.NEXT_PUBLIC_VAPID_PUBLIC_KEY!,
  },
  // O binário do ffmpeg-static (usado pra converter áudio pro formato que a Meta
  // aceita, ver src/lib/audioConvert.ts) é referenciado em runtime via path calculado
  // — sem isso o file tracing da Vercel pode não empacotar o binário na function e
  // funcionar só localmente.
  outputFileTracingIncludes: {
    '/api/leads/[id]/messages': ['./node_modules/ffmpeg-static/**'],
  },
  // ffmpeg-static calcula o path do binário com `path.join(__dirname, 'ffmpeg')`
  // (ver node_modules/ffmpeg-static/index.js). Se o webpack empacotar esse módulo
  // dentro do chunk da function, __dirname aponta pra .next/server/chunks em vez de
  // node_modules/ffmpeg-static — daí o ENOENT em produção mesmo com o binário
  // presente (bug real observado: "spawn /var/task/.next/server/chunks/ffmpeg
  // ENOENT" nos envios de áudio via API Oficial/Instagram). serverExternalPackages
  // exclui o pacote do bundling, mantendo o require() nativo do node_modules real.
  serverExternalPackages: ['ffmpeg-static'],
}

export default config
