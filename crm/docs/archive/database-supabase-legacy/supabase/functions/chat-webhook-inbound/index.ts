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
        const body = await req.json()
        const url = new URL(req.url)
        console.log('Received Inbound Webhook:', JSON.stringify(body))

        const supabaseUrl = Deno.env.get('SUPABASE_URL')
        const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')
        const loggingClient = createClient(supabaseUrl!, supabaseServiceKey!)

        try {
            await loggingClient.from('webhook_logs').insert({ payload: body })
        } catch (e) {
            console.error('failed logging webhook', e)
        }

        // Core data extraction
        let phone = '';
        let content = '';
        let leadGivenName = 'Desconhecido';
        let senderName = 'Desconhecido';
        let direction = 'inbound';
        let status = 'delivered';
        let isGroup = false;
        let skipActivitySync = false;

        let message_id = '';
        let is_reaction = false;
        let target_message_id = '';

        let media_url = '';
        let media_type = '';
        let media_mimetype = '';
        let media_filename = '';

        // Quoted message fields
        let quoted_text = '';
        let quoted_sender = '';
        let quoted_media_type = '';
        let quoted_stanza_id = '';
        let quoted_media_url = '';

        // 1. Parse Uazapi's actual JSON signature
        if (body.EventType === 'messages' && body.message) {
            const chatObj = body.chat || {};
            const msgObj = body.message || {};

            message_id = msgObj.messageid || msgObj.id || '';
            if (msgObj.messageType === 'ReactionMessage' || msgObj.type === 'reaction') {
                is_reaction = true;
                target_message_id = msgObj.reaction || msgObj.content?.key?.ID || '';
            }

            isGroup = !!(msgObj.isGroup || msgObj.chatid?.endsWith('@g.us') || chatObj.wa_isGroup || chatObj.id?.endsWith('@g.us'));

            if (isGroup) {
                // For groups, the "Lead" is the Group itself. Default phone to the group's chatid.
                const rawPhone = chatObj.wa_chatid || msgObj.chatid || chatObj.id || '';
                phone = rawPhone.replace(/[^0-9]/g, '');
                leadGivenName = msgObj.groupName || chatObj.name || chatObj.wa_name || 'Grupo (Desconhecido)';
                senderName = msgObj.senderName || msgObj.pushName || msgObj.sender_pn?.replace(/[^0-9]/g, '') || 'Membro do Grupo';
            } else {
                // Extract phone, prioritizing the pure digits
                const rawPhone = chatObj.phone || msgObj.sender_pn || '';
                phone = rawPhone.replace(/[^0-9]/g, '');

                // Lead name: prefer the CONTACT's name from the chat object
                // Guard against empty strings ('' is truthy in JS comparisons like ||)
                const candidateNames = [
                    chatObj.wa_name,
                    chatObj.name,
                    msgObj.pushName,
                    msgObj.senderName
                ];
                leadGivenName = candidateNames.find(n => n && typeof n === 'string' && n.trim() !== '') || 'Desconhecido';
                senderName = [msgObj.senderName, msgObj.pushName, leadGivenName].find(n => n && typeof n === 'string' && n.trim() !== '') || leadGivenName;
            }

            // Content & Media Handling
            const isMedia = msgObj.messageType && ['ImageMessage', 'VideoMessage', 'AudioMessage', 'DocumentMessage', 'StickerMessage'].includes(msgObj.messageType);

            if (isMedia) {
                media_type = msgObj.messageType.replace('Message', '').toLowerCase();
                media_mimetype = msgObj.content?.mimetype || msgObj.mediaType || 'application/octet-stream';
                media_filename = msgObj.content?.fileName || msgObj.content?.title || '';

                // Fallback content in case frontend can't render
                if (media_type === 'image' && msgObj.content?.caption) {
                    content = msgObj.content.caption;
                } else if (media_type === 'video' && msgObj.content?.caption) {
                    content = msgObj.content.caption;
                } else {
                    const typeTranslations: Record<string, string> = {
                        'image': '📷 Imagem',
                        'video': '🎥 Vídeo',
                        'audio': '🎵 Áudio',
                        'document': '📄 Documento',
                        'sticker': '✨ Figurinha'
                    }
                    content = typeTranslations[media_type] || `[Mídia: ${media_type}]`;
                }
            } else if (typeof msgObj.content === 'string') {
                content = msgObj.content;
            } else if (msgObj.content && msgObj.content.text) {
                content = msgObj.content.text;
            } else if (msgObj.text) {
                content = msgObj.text;
            } else {
                content = '';
            }

            // ── Extract Quoted / Reply Context ──
            const contextInfo = msgObj.contextInfo || msgObj.content?.contextInfo || null;
            if (contextInfo) {
                quoted_stanza_id = contextInfo.stanzaId || contextInfo.quotedMessageId || '';
                quoted_sender = contextInfo.participant || contextInfo.remoteJid || '';
                // Clean the sender to just the phone number
                quoted_sender = quoted_sender.replace(/@s\.whatsapp\.net$/, '').replace(/[^0-9]/g, '');

                const quotedMsg = contextInfo.quotedMessage || contextInfo.message || null;
                if (quotedMsg) {
                    // Extract quoted text
                    if (typeof quotedMsg === 'string') {
                        quoted_text = quotedMsg;
                    } else if (quotedMsg.conversation) {
                        quoted_text = quotedMsg.conversation;
                    } else if (quotedMsg.extendedTextMessage?.text) {
                        quoted_text = quotedMsg.extendedTextMessage.text;
                    } else if (quotedMsg.imageMessage?.caption) {
                        quoted_text = quotedMsg.imageMessage.caption;
                        quoted_media_type = 'image';
                    } else if (quotedMsg.videoMessage?.caption) {
                        quoted_text = quotedMsg.videoMessage.caption;
                        quoted_media_type = 'video';
                    } else if (quotedMsg.imageMessage) {
                        quoted_text = '📷 Imagem';
                        quoted_media_type = 'image';
                    } else if (quotedMsg.videoMessage) {
                        quoted_text = '🎥 Vídeo';
                        quoted_media_type = 'video';
                    } else if (quotedMsg.audioMessage) {
                        quoted_text = '🎵 Áudio';
                        quoted_media_type = 'audio';
                    } else if (quotedMsg.documentMessage) {
                        quoted_text = `📄 ${quotedMsg.documentMessage.fileName || 'Documento'}`;
                        quoted_media_type = 'document';
                    } else if (quotedMsg.stickerMessage) {
                        quoted_text = '✨ Figurinha';
                        quoted_media_type = 'sticker';
                    }
                }

                // If we have a text from contextInfo directly
                if (!quoted_text && contextInfo.quotedMessageText) {
                    quoted_text = contextInfo.quotedMessageText;
                }
            }

            // Direction handling
            if (msgObj.fromMe) {
                direction = 'outbound';
                status = msgObj.status || 'sent';

                // If the message was sent via our own API (e.g. from the FrontEnd React app),
                // we probably already optimistically saved it in the database.
                // We avoid duplicating by checking `track_source`.
                if (msgObj.track_source === 'crm_front') {
                    console.log('Skipping sync: message originated from CRM Frontend');
                    skipActivitySync = true;
                }
            } else {
                direction = 'inbound';
            }
        }
        // 2. Fallback for older formatting occasionally seen
        else if (body.event === 'messages.upsert' && body.data) {
            const msgData = body.data;
            message_id = msgData.key?.id || '';
            const remoteJid = msgData.key?.remoteJid || '';
            isGroup = remoteJid.endsWith('@g.us');

            if (isGroup) {
                phone = remoteJid.replace('@g.us', '').replace(/[^0-9]/g, '');
                leadGivenName = msgData.pushName || 'Grupo (Desconhecido)';
                senderName = msgData.participant?.replace('@s.whatsapp.net', '') || 'Membro do Grupo';
            } else {
                phone = remoteJid.replace('@s.whatsapp.net', '').replace(/[^0-9]/g, '');
                leadGivenName = msgData.pushName || 'Desconhecido';
                senderName = leadGivenName;
            }

            direction = msgData.key?.fromMe ? 'outbound' : 'inbound';

            const messageObj = msgData.message;
            if (messageObj) {
                content = messageObj.conversation ||
                    messageObj.extendedTextMessage?.text ||
                    '[Mensagem não suportada/Mídia]';
            }
        }

        const organizationId = new URL(req.url).searchParams.get('org_id')

        if (!phone || !content || !organizationId) {
            console.warn('Payload ignorado - dados faltando ou evento não suportado', { body })
            return new Response(JSON.stringify({ message: 'Payload ignorado' }), { status: 200 })
        }

        const supabase = createClient(supabaseUrl!, supabaseServiceKey!)

        // Prevent processing group messages if listenGroups is disabled
        if (isGroup) {
            const { data: integ } = await supabase
                .from('integrations')
                .select('config')
                .eq('organization_id', organizationId)
                .eq('name', 'WhatsApp Lite')
                .single();

            // Explicitly require true. If undefined or false, drop it.
            if (integ?.config?.listenGroups !== true) {
                console.log(`[Webhook] Dropping group message. listenGroups is disabled or undefined for org ${organizationId}`);
                return new Response(JSON.stringify({ message: 'Mensagem de grupo ignorada (config desativada)' }), { status: 200 });
            }
        }

        // Fetch WhatsApp Lite integration ID for this org (used to tag leads)
        const { data: wlIntegration } = await supabase
            .from('integrations')
            .select('id')
            .eq('organization_id', organizationId)
            .eq('name', 'WhatsApp Lite')
            .single();
        const whatsappLiteIntegrationId = wlIntegration?.id || null;

        // 1. Find matching lead by phone and organization manually (if multiple exist we take latest)
        let leadId = null
        let currentAvatarUrl = null
        const { data: existingLeads } = await supabase
            .from('leads')
            .select('id, avatar_url, integration_id')
            .eq('organization_id', organizationId)
            .like('phone', `%${phone.replace(/[^0-9]/g, '')}%`) // simple sanitize
            .order('created_at', { ascending: false })
            .limit(1)

        if (existingLeads && existingLeads.length > 0) {
            leadId = existingLeads[0].id
            currentAvatarUrl = existingLeads[0].avatar_url

            // Backfill integration_id if missing on existing lead
            if (!existingLeads[0].integration_id && whatsappLiteIntegrationId) {
                await supabase.from('leads').update({ integration_id: whatsappLiteIntegrationId }).eq('id', leadId);
            }
        } else {
            // 2. Auto-create lead if not exists. Find default pipeline first.
            let targetStageId = null;

            // Try to get the integration config
            const { data: integ } = await supabase
                .from('integrations')
                .select('config')
                .eq('organization_id', organizationId)
                .eq('name', 'WhatsApp Lite')
                .single();

            let targetPipelineId = integ?.config?.defaultPipelineId;

            if (!targetPipelineId) {
                // Fallback to oldest pipeline
                const { data: oldestPipe } = await supabase
                    .from('pipelines')
                    .select('id')
                    .eq('organization_id', organizationId)
                    .is('deleted_at', null)
                    .order('created_at', { ascending: true })
                    .limit(1)
                    .single();
                if (oldestPipe) targetPipelineId = oldestPipe.id;
            }

            if (targetPipelineId) {
                // Get the first stage of this pipeline
                const { data: firstStage } = await supabase
                    .from('pipeline_stages')
                    .select('id')
                    .eq('pipeline_id', targetPipelineId)
                    .order('rank', { ascending: true })
                    .limit(1)
                    .single();
                if (firstStage) targetStageId = firstStage.id;
            }

            const { data: newLead, error: createError } = await supabase
                .from('leads')
                .insert({
                    organization_id: organizationId,
                    title: leadGivenName,
                    phone: phone,
                    stage_id: targetStageId,
                    is_group: isGroup,
                    integration_id: whatsappLiteIntegrationId
                })
                .select('id')
                .single()

            if (createError) throw createError
            leadId = newLead.id

            // Auto-tag group leads with "Grupo" tag
            if (isGroup) {
                // Find or create the "Grupo" tag for this organization
                let { data: grupoTag } = await supabase
                    .from('tags')
                    .select('id')
                    .eq('organization_id', organizationId)
                    .eq('name', 'Grupo')
                    .single()

                if (!grupoTag) {
                    const { data: newTag } = await supabase
                        .from('tags')
                        .insert({ organization_id: organizationId, name: 'Grupo', color: '#6366f1' })
                        .select('id')
                        .single()
                    grupoTag = newTag
                }

                if (grupoTag) {
                    await supabase.from('lead_tags').upsert({
                        lead_id: newLead.id,
                        tag_id: grupoTag.id,
                        organization_id: organizationId
                    }, { onConflict: 'lead_id,tag_id', ignoreDuplicates: true })
                }
            }
        }

        // 2b. Optional: Fetch and store WhatsApp Avatar if missing
        if (!currentAvatarUrl) {
            try {
                // Determine if we have imagePreview shortcut directly in the body
                let avatarUrlToDownload = null;
                const chatObj = body.chat || {};
                if (chatObj.imagePreview && typeof chatObj.imagePreview === 'string' && chatObj.imagePreview.trim() !== '') {
                    avatarUrlToDownload = chatObj.imagePreview;
                }

                if (!avatarUrlToDownload) {
                    // Try to fetch via API if we couldn't find a direct link
                    const { data: integ } = await supabase
                        .from('integrations')
                        .select('config')
                        .eq('organization_id', organizationId)
                        .eq('name', 'WhatsApp Lite')
                        .single();

                    const apikey = integ?.config?.instanceToken;

                    if (apikey) {
                        const targetId = isGroup ? (chatObj.id || chatObj.wa_chatid || phone) : phone;
                        const uazapiRes = await fetch(`https://atlas-solutions.uazapi.com/chat/details`, {
                            method: 'POST',
                            headers: {
                                'Content-Type': 'application/json',
                                'token': apikey
                            },
                            body: JSON.stringify({ number: targetId, preview: true })
                        });

                        if (uazapiRes.ok) {
                            const uazapiData = await uazapiRes.json();
                            if (uazapiData?.imagePreview && typeof uazapiData.imagePreview === 'string') {
                                avatarUrlToDownload = uazapiData.imagePreview;
                            }
                        }
                    }
                }

                if (avatarUrlToDownload) {
                    // Download the image
                    const imgRes = await fetch(avatarUrlToDownload);
                    if (imgRes.ok) {
                        const imgBuffer = await imgRes.arrayBuffer();
                        const fileExt = 'jpg'; // Usually jpegs from WhatsApp
                        const fileName = `${organizationId}/${leadId}-${Date.now()}.${fileExt}`;

                        // Upload to Storage
                        const { data: uploadData, error: uploadError } = await supabase.storage
                            .from('avatars')
                            .upload(fileName, imgBuffer, {
                                contentType: 'image/jpeg',
                                upsert: true
                            });

                        if (!uploadError && uploadData) {
                            const publicUrl = supabase.storage.from('avatars').getPublicUrl(fileName).data.publicUrl;

                            // Update lead with new avatar url
                            await supabase.from('leads').update({ avatar_url: publicUrl }).eq('id', leadId);
                            currentAvatarUrl = publicUrl;
                            console.log(`Successfully updated avatar for lead/group ${leadId}`);
                        } else {
                            console.warn(`Storage upload error:`, uploadError);
                        }
                    }
                }
            } catch (err) {
                console.warn('Silent fail fetching avatar:', err);
            }
        }

        // 2c. Optional: Download Media if present in message
        if (media_type && message_id) {
            try {
                const { data: integ } = await supabase
                    .from('integrations')
                    .select('config')
                    .eq('organization_id', organizationId)
                    .eq('name', 'WhatsApp Lite')
                    .single();

                const apikey = integ?.config?.instanceToken;

                if (apikey) {
                    console.log(`Downloading media for message ${message_id}`);
                    const downloadRes = await fetch(`https://atlas-solutions.uazapi.com/message/download`, {
                        method: 'POST',
                        headers: {
                            'Content-Type': 'application/json',
                            'token': apikey
                        },
                        body: JSON.stringify({
                            id: message_id,
                            return_base64: false,
                            generate_mp3: false,
                            return_link: false,
                            transcribe: false,
                            download_quoted: !!quoted_stanza_id
                        })
                    });

                    if (downloadRes.ok) {
                        const downloadData = await downloadRes.json();
                        if (downloadData && downloadData.fileURL) {
                            // Actual media download
                            const actualFileRes = await fetch(downloadData.fileURL);
                            if (actualFileRes.ok) {
                                const buffer = await actualFileRes.arrayBuffer();
                                // Fallback extensions based on mimetype
                                let ext = media_mimetype.split('/')[1]?.split(';')[0];
                                if (!ext || ext === 'octet-stream') ext = 'bin';
                                if (media_type === 'sticker' && !ext) ext = 'webp';

                                const filePath = `${organizationId}/${leadId}/${message_id}.${ext}`;

                                const { data: uploadData, error: uploadErr } = await supabase.storage
                                    .from('chat_media')
                                    .upload(filePath, buffer, {
                                        contentType: media_mimetype,
                                        upsert: true
                                    });

                                if (!uploadErr && uploadData) {
                                    media_url = supabase.storage.from('chat_media').getPublicUrl(filePath).data.publicUrl;
                                    console.log(`Media saved successfully: ${media_url}`);
                                } else {
                                    console.warn('Failed to upload media to storage:', uploadErr);
                                }
                            } else {
                                console.warn(`Failed to fetch actual file buffer from fileURL: ${actualFileRes.status}`);
                            }
                        } else if (downloadData && downloadData.base64) {
                            // In case it returns base64
                            const buffer = Buffer.from(downloadData.base64, 'base64');
                            let ext = media_mimetype.split('/')[1]?.split(';')[0];
                            if (!ext || ext === 'octet-stream') ext = 'bin';
                            if (media_type === 'sticker' && !ext) ext = 'webp';
                            const filePath = `${organizationId}/${leadId}/${message_id}.${ext}`;
                            const { data: uploadData, error: uploadErr } = await supabase.storage
                                .from('chat_media')
                                .upload(filePath, buffer, {
                                    contentType: media_mimetype,
                                    upsert: true
                                });
                            if (!uploadErr && uploadData) {
                                media_url = supabase.storage.from('chat_media').getPublicUrl(filePath).data.publicUrl;
                            }
                        } else {
                            console.warn('Uazapi download did not return a valid fileURL or base64', downloadData);
                        }
                    } else {
                        console.warn(`Uazapi media download failed with status ${downloadRes.status}`);
                    }
                }
            } catch (err) {
                console.warn('Error downloading media:', err);
            }
        }

        // 3. Register Activity (This triggers Realtime updates on the frontend natively!)
        if (!skipActivitySync) {
            const metadataPayload: any = {
                direction: direction,
                sender_name: direction === 'inbound' ? senderName : 'Atendente (WhatsApp)',
                status: status,
                source: direction === 'inbound' ? 'lead' : 'human',
                is_group: isGroup,
                message_id: message_id,
                is_reaction: is_reaction,
                target_message_id: target_message_id
            };

            // Inject media details if successfully downloaded
            if (media_url) {
                metadataPayload.media_url = media_url;
                metadataPayload.media_type = media_type;
                metadataPayload.media_mimetype = media_mimetype;
                if (media_filename) metadataPayload.media_filename = media_filename;
            }

            // Inject quoted message details
            if (quoted_text || quoted_media_type) {
                metadataPayload.quoted_text = quoted_text;
                if (quoted_sender) metadataPayload.quoted_sender = quoted_sender;
                if (quoted_media_type) metadataPayload.quoted_media_type = quoted_media_type;
                if (quoted_stanza_id) metadataPayload.quoted_stanza_id = quoted_stanza_id;
                if (quoted_media_url) metadataPayload.quoted_media_url = quoted_media_url;
            }

            const { error: insertError } = await supabase
                .from('lead_activities')
                .insert({
                    organization_id: organizationId,
                    lead_id: leadId,
                    type: 'whatsapp',
                    content: content,
                    metadata: metadataPayload
                })

            if (insertError) throw insertError

            // 4. Update the lead's last_activity timestamp (This also triggers the UI ordering, though pg triggers handle this as well)
            await supabase.from('leads').update({
                updated_at: new Date().toISOString()
            }).eq('id', leadId)
        } else {
            console.log('Skipped saving activity due to skipActivitySync flag.');
        }


        // 5. [Optional] Trigger AI Autoresponder if Automation setting is ON
        // This could call "generate-ai-insights" or another edge function.

        return new Response(JSON.stringify({ success: true, leadId }), {
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })

    } catch (error) {
        console.error('Error processing inbound webhook:', error)
        return new Response(JSON.stringify({ error: error.message }), {
            status: 500,
            headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        })
    }
})
