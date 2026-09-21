import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { phone, leadId, organizationId, isGroup } = await req.json()

        if (!phone || !leadId || !organizationId) {
            return new Response(JSON.stringify({ error: 'Missing required fields: phone, leadId, organizationId' }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const supabaseUrl = Deno.env.get('SUPABASE_URL')!
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // Check if lead already has an avatar
        const { data: lead } = await supabase
            .from('leads')
            .select('avatar_url')
            .eq('id', leadId)
            .single()

        if (lead?.avatar_url) {
            return new Response(JSON.stringify({ message: 'Avatar already exists', avatar_url: lead.avatar_url }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // Get integration token
        const { data: integ } = await supabase
            .from('integrations')
            .select('config')
            .eq('organization_id', organizationId)
            .eq('name', 'WhatsApp Lite')
            .single()

        const apikey = (integ?.config as any)?.instanceToken
        if (!apikey) {
            return new Response(JSON.stringify({ error: 'No Uazapi token found' }), {
                status: 404,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // Call Uazapi to get the profile picture
        const targetId = isGroup ? phone : phone
        const uazapiRes = await fetch('https://atlas-solutions.uazapi.com/chat/details', {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'token': apikey,
            },
            body: JSON.stringify({ number: targetId, preview: true }),
        })

        if (!uazapiRes.ok) {
            console.warn(`Uazapi returned ${uazapiRes.status}`)
            return new Response(JSON.stringify({ error: 'Uazapi API error', status: uazapiRes.status }), {
                status: 502,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const uazapiData = await uazapiRes.json()
        const imageUrl = uazapiData?.imagePreview

        if (!imageUrl || typeof imageUrl !== 'string' || imageUrl.trim() === '') {
            console.warn('No imagePreview returned from Uazapi')
            return new Response(JSON.stringify({ message: 'No profile picture available' }), {
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        // Download the image
        const imgRes = await fetch(imageUrl)
        if (!imgRes.ok) {
            return new Response(JSON.stringify({ error: 'Failed to download image' }), {
                status: 502,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const imgBuffer = await imgRes.arrayBuffer()
        const fileName = `${organizationId}/${leadId}-${Date.now()}.jpg`

        // Upload to Storage
        const { data: uploadData, error: uploadError } = await supabase.storage
            .from('avatars')
            .upload(fileName, imgBuffer, {
                contentType: 'image/jpeg',
                upsert: true,
            })

        if (uploadError) {
            console.error('Storage upload error:', uploadError)
            return new Response(JSON.stringify({ error: 'Storage upload failed', details: uploadError.message }), {
                status: 500,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName).data.publicUrl

        // Update lead
        await supabase.from('leads').update({ avatar_url: publicUrl }).eq('id', leadId)

        console.log(`✅ Avatar saved for lead ${leadId}: ${publicUrl}`)

        return new Response(JSON.stringify({ success: true, avatar_url: publicUrl }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    } catch (error) {
        console.error('Error in fetch-avatar:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
