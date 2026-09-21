/**
 * Fix leads with wrong names by fetching real WhatsApp names from Uazapi.
 * Usage: npx tsx scripts/fix-lead-names.ts
 */

import { createClient } from '@supabase/supabase-js'
import * as fs from 'fs'
import * as path from 'path'

// Load .env.local
const envPath = path.resolve(__dirname, '../atlas-eye/.env.local')
if (fs.existsSync(envPath)) {
    const envContent = fs.readFileSync(envPath, 'utf-8')
    for (const line of envContent.split('\n')) {
        const trimmed = line.trim()
        if (trimmed && !trimmed.startsWith('#')) {
            const eqIndex = trimmed.indexOf('=')
            if (eqIndex > 0) {
                const key = trimmed.substring(0, eqIndex).trim()
                const val = trimmed.substring(eqIndex + 1).trim()
                if (!process.env[key]) process.env[key] = val
            }
        }
    }
}

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || ''
const SUPABASE_SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY || ''
const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

async function fixLeadNames() {
    // Get the leads to fix
    const leads = [
        { id: 'd61f7191-4dfe-49a6-a38b-0fe802970fa1', phone: '559236430001' },
        { id: '008cdf15-1cb5-4d5b-9eb2-db5c350c38fd', phone: '559294612173' },
        { id: '9aa07320-4830-4cdf-8576-254c5d6f00f9', phone: '559284700485' },
        { id: 'c34d128b-d69d-4e57-9572-37d7d6016e38', phone: '559291329575' },
        { id: '5276369f-7ff5-4eb6-b112-843a35aacb4a', phone: '5511941516030' },
        { id: 'ca6ef89f-c165-4ccf-b898-5844c046b3eb', phone: '559282717586' },
        { id: '066e0bf3-b9d8-4f44-849b-f49fe7fa2149', phone: '5512991306161' },
    ]

    // Get org token
    const { data: integ } = await supabase
        .from('integrations')
        .select('config')
        .eq('organization_id', 'd17ec329-e074-46a0-b5a4-f3617e161cca')
        .eq('name', 'WhatsApp Lite')
        .single()

    const token = (integ?.config as any)?.instanceToken
    if (!token) { console.error('No token found!'); return }

    for (const lead of leads) {
        try {
            console.log(`🔍 Looking up real name for ${lead.phone}...`)

            const res = await fetch('https://atlas-solutions.uazapi.com/chat/details', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', 'token': token },
                body: JSON.stringify({ number: lead.phone, preview: true }),
            })

            if (!res.ok) {
                console.warn(`   ⚠️  Uazapi returned ${res.status}`)
                continue
            }

            const data = await res.json()
            const realName = data?.wa_name || data?.name || data?.pushName || null

            if (realName && realName.trim() !== '') {
                await supabase.from('leads').update({ title: realName }).eq('id', lead.id)
                console.log(`   ✅ Renamed to "${realName}"`)
            } else {
                console.log(`   ⏭️  No name found, keeping as is`)
            }

            await new Promise(r => setTimeout(r, 500))
        } catch (err: any) {
            console.warn(`   ❌ Error:`, err.message)
        }
    }

    console.log('\n✅ Done!')
}

fixLeadNames().catch(console.error)
