import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req) => {
    // Handle CORS preflight
    if (req.method === 'OPTIONS') {
        return new Response('ok', { headers: corsHeaders })
    }

    try {
        const { leadId, content, organizationId, source = 'human' } = await req.json()

        if (!leadId || !content || !organizationId) {
            return new Response(JSON.stringify({ error: 'Missing required parameters: leadId, content, organizationId' }), {
                status: 400,
                headers: { ...corsHeaders, 'Content-Type': 'application/json' },
            })
        }

        const supabaseUrl = Deno.env.get('SUPABASE_URL')
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')

        if (!supabaseUrl || !supabaseServiceKey) {
            throw new Error('Supabase configuration missing in environment.')
        }

        const supabase = createClient(supabaseUrl, supabaseServiceKey)

        // TODO: Fetch Integration Token from vault if using Z-API or Evolution API
        // 
        // example:
        // const { data: integrationSecret } = await supabase.rpc('get_integration_secret', {
        //   p_integration_id: leadIntegrationId,
        //   p_org_id: organizationId
        // });

        // TODO: Send exact message using External WhatsApp API
        console.log(`Sending WhatsApp message to Lead ${leadId}. Content: ${content}`)

        // On Success, this function itself could log the outbound activity. 
        // However, our UI already optimistically logged the 'human' message. 
        // If it was an 'ai' message, this function WOULD insert the record.

        if (source === 'ai') {
            const { error: insertError } = await supabase
                .from('lead_activities')
                .insert({
                    organization_id: organizationId,
                    lead_id: leadId,
                    type: 'whatsapp',
                    content: content,
                    metadata: {
                        direction: 'outbound',
                        source: 'ai',
                        status: 'sent',
                        sender_name: 'Atlas AI'
                    }
                })

            if (insertError) throw insertError
        }

        return new Response(JSON.stringify({ success: true }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })

    } catch (error) {
        console.error('Error in chat-send-message:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
