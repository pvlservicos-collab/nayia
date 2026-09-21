'use server';

// Ações Seguras de Servidor (Server Actions) para Uazapi
// Garante que o Admin Token não vaze para o client-side

const UAZAPI_SERVER = process.env.UAZAPI_SERVER_URL;
const UAZAPI_ADMIN_TOKEN = process.env.UAZAPI_ADMIN_TOKEN;

// Helper paramétrico para as requisições API
const apiFetch = async (endpoint: string, options: RequestInit = {}) => {
    if (!UAZAPI_SERVER || !UAZAPI_ADMIN_TOKEN) {
        throw new Error('As credentials da Uazapi não estão configuradas.');
    }

    const headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        'admintoken': UAZAPI_ADMIN_TOKEN, // Uazapi format for admin token
        ...options.headers,
    };

    const res = await fetch(`${UAZAPI_SERVER}${endpoint}`, {
        ...options,
        headers,
    });

    const data = await res.json().catch(() => ({}));
    return { ok: res.ok, status: res.status, data };
};

/**
 * Retorna o estado atual de uma instância usando o token dela
 */
export async function getInstanceStatus(token: string) {
    try {
        if (!UAZAPI_SERVER) throw new Error('O servidor Uazapi não está configurado.');

        const res = await fetch(`${UAZAPI_SERVER}/instance/status`, {
            method: 'GET',
            headers: {
                'Accept': 'application/json',
                'token': token
            }
        });

        const data = await res.json().catch(() => ({}));

        if (res.ok || res.status === 200) {
            return {
                success: true,
                state: data.instance?.status || data.state || 'disconnected',
                statusData: data
            };
        }

        return { success: true, state: 'not_created' };


    } catch (error: any) {
        console.error('Error on Uazapi getInstance:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Cria a instância na Uazapi
 */
export async function createInstance(instanceName: string) {
    try {
        console.log(`[Uazapi] Creating instance: ${instanceName} at ${UAZAPI_SERVER}`);
        const createRes = await apiFetch(`/instance/init`, {
            method: 'POST',
            body: JSON.stringify({
                name: instanceName,
                systemName: "TitaCRM",
                fingerprintProfile: "chrome",
                browser: "chrome"
            })
        });

        console.log('[Uazapi] Create Res:', createRes);

        if (createRes.ok || createRes.status === 200 || createRes.status === 201) {
            return { success: true, state: 'created', instance: createRes.data };
        }

        return { success: false, error: `Falha ao criar instância: ${JSON.stringify(createRes.data)}` };
    } catch (error: any) {
        console.error('Error on Uazapi createInstance:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Conecta a instância e retorna o Base64 do QR Code, usando o token da instância 
 */
export async function connectInstanceWithToken(token: string) {
    try {
        if (!UAZAPI_SERVER) {
            throw new Error('O servidor Uazapi não está configurado.');
        }

        const res = await fetch(`${UAZAPI_SERVER}/instance/connect`, {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'token': token
            }
        });

        const data = await res.json().catch(() => ({}));

        if (res.ok || res.status === 200 || res.status === 201) {
            // O Uazapi/Evolution retorna o QR Code dentro de data.instance.qrcode
            const qrCode = data.instance?.qrcode || data.qrcode || data.base64;

            if (qrCode) {
                return { success: true, base64Url: qrCode };
            } else {
                return { success: false, error: `Aguardando QR Code... Resposta: ${JSON.stringify(data)}` };
            }
        }

        return { success: false, error: data.message || `Falha ao buscar QR Code. Status: ${res.status}. Resposta: ${JSON.stringify(data)}` };
    } catch (error: any) {
        console.error('Error on Uazapi connectInstanceWithToken:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Desconecta (Logout) o aparelho de uma instância usando o token, preservando a instância
 */
export async function disconnectInstance(token: string) {
    try {
        if (!UAZAPI_SERVER) throw new Error('O servidor Uazapi não está configurado.');

        const res = await fetch(`${UAZAPI_SERVER}/instance/disconnect`, {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'token': token
            }
        });

        if (res.ok) {
            return { success: true };
        }
        return { success: false, error: 'Não foi possível desconectar a instância' };
    } catch (error: any) {
        console.error('Error on Uazapi disconnectInstance:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Registra o Webhook na Uazapi para a instância conectada
 */
export async function setWebhook(token: string, webhookUrl: string) {
    try {
        if (!UAZAPI_SERVER) throw new Error('O servidor Uazapi não está configurado.');

        console.log(`[Uazapi] Setting webhook ${webhookUrl} for token ${token}`);

        const res = await fetch(`${UAZAPI_SERVER}/webhook`, {
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'token': token
            },
            body: JSON.stringify({
                enabled: true,
                url: webhookUrl,
                events: [
                    "messages",
                    "connection"
                ],
                excludeMessages: [
                    "wasSentByApi"
                ]
            })
        });

        const data = await res.json().catch(() => ({}));

        if (res.ok || res.status === 200) {
            return { success: true, data };
        }

        return { success: false, error: `Falha ao registrar Webhook. Status: ${res.status}. Resposta: ${JSON.stringify(data)}` };
    } catch (error: any) {
        console.error('Error on Uazapi setWebhook:', error);
        return { success: false, error: error.message };
    }
}

/**
 * Remove (deleta) a instância da Uazapi completamente usando seu token
 */
export async function deleteInstance(token: string) {
    try {
        if (!UAZAPI_SERVER) {
            throw new Error('O servidor Uazapi não está configurado.');
        }

        const res = await fetch(`${UAZAPI_SERVER}/instance`, {
            method: 'DELETE',
            headers: {
                'Accept': 'application/json',
                'token': token
            }
        });

        const data = await res.json().catch(() => ({}));

        if (res.ok || res.status === 200 || res.status === 201) {
            return { success: true, data };
        }
        return { success: false, error: data.message || 'Falha ao deletar instância' };
    } catch (error: any) {
        console.error('Error on Uazapi deleteInstance:', error);
        return { success: false, error: error.message };
    }
}
