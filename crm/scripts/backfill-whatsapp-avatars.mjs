// Backfill de fotos de perfil pra leads do WhatsApp Nº2 (Evolution) criados antes da
// busca de avatar existir (ver src/app/api/webhooks/evolution/route.ts). Duplica a
// lógica de fetchEvolutionProfilePicture (src/lib/evolution.ts) porque scripts/ roda
// fora do Next.js e não resolve o alias @/.
// Uso: node scripts/backfill-whatsapp-avatars.mjs
import { config } from 'dotenv'
import { neon } from '@neondatabase/serverless'
import { put } from '@vercel/blob'

config({ path: new URL('../.env.local', import.meta.url).pathname })

const url = process.env.DATABASE_URL || process.env.whatsappnaturabelas_DATABASE_URL
if (!url) {
  console.error('DATABASE_URL não encontrada em .env.local')
  process.exit(1)
}
if (!process.env.EVOLUTION_API_URL) {
  console.error('EVOLUTION_API_URL não encontrada em .env.local')
  process.exit(1)
}

const sql = neon(url)

async function fetchProfilePicture(server, instanceName, apiKey, phone) {
  try {
    const res = await fetch(`${server}/chat/fetchProfilePictureUrl/${instanceName}`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', apikey: apiKey },
      body: JSON.stringify({ number: phone }),
    })
    if (!res.ok) return null

    const data = await res.json().catch(() => null)
    const pictureUrl = data?.profilePictureUrl
    if (!pictureUrl || typeof pictureUrl !== 'string') return null

    const imgRes = await fetch(pictureUrl)
    if (!imgRes.ok) return null

    const mimetype = imgRes.headers.get('content-type') || 'image/jpeg'
    const buffer = Buffer.from(await imgRes.arrayBuffer())
    const ext = mimetype.split('/')[1]?.split(';')[0] || 'jpg'

    const blob = await put(`evolution-avatars/backfill-${Date.now()}-${phone}.${ext}`, buffer, {
      access: 'public',
      contentType: mimetype,
    })
    return blob.url
  } catch (err) {
    console.warn(`   ❌ Erro buscando foto de ${phone}:`, err.message)
    return null
  }
}

async function main() {
  const integrationRows = await sql`
    select i.id, i.organization_id, i.config, s.secret
    from integrations i
    left join integration_secrets s on s.integration_id = i.id
    where i.type = 'whatsapp_evolution' and i.deleted_at is null
  `

  if (integrationRows.length === 0) {
    console.log('Nenhuma integração whatsapp_evolution encontrada.')
    return
  }

  let totalSuccess = 0
  let totalSkipped = 0

  for (const integ of integrationRows) {
    const instanceName = integ.config?.instanceName
    const apiKey = integ.secret?.api_key || process.env.EVOLUTION_API_KEY
    const server = process.env.EVOLUTION_API_URL

    if (!instanceName || !apiKey) {
      console.warn(`⚠️  Integração ${integ.id} sem instanceName/apiKey configurado, pulando.`)
      continue
    }

    const leadsRows = await sql`
      select id, title, phone
      from leads
      where integration_id = ${integ.id}
        and avatar_url is null
        and phone is not null
        and is_group is not true
        and deleted_at is null
    `

    console.log(`\n📋 Org ${integ.organization_id}: ${leadsRows.length} leads sem avatar.`)

    for (const lead of leadsRows) {
      process.stdout.write(`   ${lead.title} (${lead.phone})... `)
      const avatarUrl = await fetchProfilePicture(server, instanceName, apiKey, lead.phone)

      if (avatarUrl) {
        await sql`update leads set avatar_url = ${avatarUrl} where id = ${lead.id}`
        console.log('✅')
        totalSuccess++
      } else {
        console.log('⏭️  sem foto disponível')
        totalSkipped++
      }

      // Rate limit pra não sobrecarregar a instância Evolution.
      await new Promise((r) => setTimeout(r, 500))
    }
  }

  console.log(`\n========================================`)
  console.log(`  ✅ Avatares salvos: ${totalSuccess}`)
  console.log(`  ⏭️  Sem foto/erro/pulados: ${totalSkipped}`)
  console.log(`========================================`)
}

main().catch((err) => {
  console.error('Erro fatal:', err)
  process.exit(1)
})
