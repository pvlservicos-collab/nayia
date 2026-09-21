/**
 * Trinks MCP — HTTP Client
 *
 * Variáveis de ambiente:
 *   TRINKS_API_KEY          — X-Api-Key (obrigatório)
 *   TRINKS_ESTABELECIMENTO_ID — ID do estabelecimento padrão (obrigatório)
 */

const BASE_URL = 'https://api.trinks.com';
const API_KEY = process.env.TRINKS_API_KEY || '';
const DEFAULT_ESTABELECIMENTO_ID = process.env.TRINKS_ESTABELECIMENTO_ID || '';

interface RequestOptions {
    method: 'GET' | 'POST' | 'PUT' | 'PATCH' | 'DELETE';
    path: string;
    body?: Record<string, unknown>;
    queryParams?: Record<string, string | number | boolean | undefined>;
    estabelecimentoId?: string;
}

interface ApiResponse<T = unknown> {
    ok: boolean;
    status: number;
    data: T;
}

function buildUrl(path: string, queryParams?: Record<string, string | number | boolean | undefined>): string {
    const cleanPath = path.startsWith('/') ? path : `/${path}`;
    const url = new URL(`${BASE_URL}${cleanPath}`);

    if (queryParams) {
        for (const [key, value] of Object.entries(queryParams)) {
            if (value === undefined || value === null) continue;
            url.searchParams.set(key, String(value));
        }
    }

    return url.toString();
}

function getHeaders(estabelecimentoId?: string): Record<string, string> {
    const id = estabelecimentoId || DEFAULT_ESTABELECIMENTO_ID;
    return {
        'Content-Type': 'application/json',
        'X-Api-Key': API_KEY,
        ...(id ? { estabelecimentoId: id } : {}),
    };
}

export async function apiRequest<T = unknown>(options: RequestOptions): Promise<ApiResponse<T>> {
    const { method, path, body, queryParams, estabelecimentoId } = options;
    const url = buildUrl(path, queryParams);

    const fetchOptions: RequestInit = {
        method,
        headers: getHeaders(estabelecimentoId),
    };

    if (body && method !== 'GET' && method !== 'DELETE') {
        fetchOptions.body = JSON.stringify(body);
    }

    const response = await fetch(url, fetchOptions);

    if (response.status === 204) {
        return { ok: true, status: 204, data: null as T };
    }

    let data: T;
    try {
        data = await response.json() as T;
    } catch {
        data = null as T;
    }

    if (!response.ok) {
        const errorMsg = (data as any)?.message || (data as any)?.title || `Erro da API Trinks: ${response.status}`;
        throw new Error(errorMsg);
    }

    return { ok: true, status: response.status, data };
}

export const api = {
    get: <T = unknown>(path: string, queryParams?: Record<string, string | number | boolean | undefined>, estabelecimentoId?: string) =>
        apiRequest<T>({ method: 'GET', path, queryParams, estabelecimentoId }),

    post: <T = unknown>(path: string, body: Record<string, unknown>, estabelecimentoId?: string) =>
        apiRequest<T>({ method: 'POST', path, body, estabelecimentoId }),

    put: <T = unknown>(path: string, body: Record<string, unknown>, estabelecimentoId?: string) =>
        apiRequest<T>({ method: 'PUT', path, body, estabelecimentoId }),

    patch: <T = unknown>(path: string, body: Record<string, unknown>, estabelecimentoId?: string) =>
        apiRequest<T>({ method: 'PATCH', path, body, estabelecimentoId }),

    delete: <T = unknown>(path: string, estabelecimentoId?: string) =>
        apiRequest<T>({ method: 'DELETE', path, estabelecimentoId }),
};
