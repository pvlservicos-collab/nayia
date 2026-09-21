/**
 * Trinks MCP — Clientes Tools (11 tools)
 *
 * listar_clientes, buscar_cliente, criar_cliente, atualizar_cliente, deletar_cliente,
 * adicionar_credito_cliente, criar_vale_presente,
 * listar_etiquetas_cliente, adicionar_etiqueta_cliente, remover_etiqueta_cliente,
 * listar_telefones_cliente
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { api } from '../http-client.js';

export function registerClientesTools(server: McpServer): void {

    // ── listar_clientes ──
    server.tool(
        'listar_clientes',
        'Lista clientes do estabelecimento com filtros por nome, CPF, email, telefone e datas.',
        {
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            nome: z.string().optional().describe('Filtrar por nome'),
            cpf: z.string().optional().describe('Filtrar por CPF'),
            email: z.string().optional().describe('Filtrar por e-mail'),
            telefone: z.string().optional().describe('Filtrar por telefone'),
            dataCadastroInicio: z.string().optional().describe('Data de cadastro início (YYYY-MM-DD)'),
            dataCadastroFim: z.string().optional().describe('Data de cadastro fim (YYYY-MM-DD)'),
            page: z.number().int().min(1).optional().describe('Página'),
            pageSize: z.number().int().min(1).max(100).optional().describe('Itens por página (max: 100)'),
        },
        async (params) => {
            const { estabelecimentoId, ...filters } = params;
            const q: Record<string, string | number | boolean | undefined> = {};
            if (filters.nome) q.nome = filters.nome;
            if (filters.cpf) q.cpf = filters.cpf;
            if (filters.email) q.email = filters.email;
            if (filters.telefone) q.telefone = filters.telefone;
            if (filters.dataCadastroInicio) q.dataCadastroInicio = filters.dataCadastroInicio;
            if (filters.dataCadastroFim) q.dataCadastroFim = filters.dataCadastroFim;
            if (filters.page) q.page = filters.page;
            if (filters.pageSize) q.pageSize = filters.pageSize;

            const result = await api.get('/v1/clientes', q, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── buscar_cliente ──
    server.tool(
        'buscar_cliente',
        'Retorna os dados completos de um cliente pelo ID.',
        {
            id: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.get(`/v1/clientes/${params.id}`, undefined, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── criar_cliente ──
    server.tool(
        'criar_cliente',
        'Cria um novo cliente no Trinks. Nome é obrigatório.',
        {
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            nome: z.string().describe('Nome do cliente (obrigatório)'),
            email: z.string().email().optional().describe('E-mail'),
            cpf: z.string().optional().describe('CPF (apenas dígitos)'),
            dataNascimento: z.string().optional().describe('Data de nascimento (YYYY-MM-DD)'),
            sexo: z.enum(['M', 'F', 'O']).optional().describe('Sexo: M (masculino), F (feminino), O (outro)'),
            telefone: z.string().optional().describe('Telefone principal'),
            observacao: z.string().optional().describe('Observação sobre o cliente'),
        },
        async (params) => {
            const { estabelecimentoId, ...body } = params;
            const result = await api.post('/v1/clientes', body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── atualizar_cliente ──
    server.tool(
        'atualizar_cliente',
        'Atualiza dados de um cliente existente. Envie apenas os campos a alterar.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            nome: z.string().optional().describe('Novo nome'),
            email: z.string().email().optional().describe('Novo e-mail'),
            cpf: z.string().optional().describe('Novo CPF'),
            dataNascimento: z.string().optional().describe('Nova data de nascimento (YYYY-MM-DD)'),
            sexo: z.enum(['M', 'F', 'O']).optional().describe('Sexo'),
            observacao: z.string().optional().describe('Nova observação'),
        },
        async (params) => {
            const { clienteId, estabelecimentoId, ...body } = params;
            const result = await api.put(`/v1/clientes/${clienteId}`, body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── deletar_cliente ──
    server.tool(
        'deletar_cliente',
        'Remove um cliente do estabelecimento. ATENÇÃO: ação irreversível.',
        {
            clienteId: z.number().int().describe('ID do cliente a deletar'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            await api.delete(`/v1/clientes/${params.clienteId}`, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: 'Cliente removido com sucesso.' }] };
        }
    );

    // ── adicionar_credito_cliente ──
    server.tool(
        'adicionar_credito_cliente',
        'Adiciona crédito (saldo) à conta de um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            valor: z.number().positive().describe('Valor do crédito a adicionar (em reais)'),
            descricao: z.string().optional().describe('Descrição/motivo do crédito'),
        },
        async (params) => {
            const { clienteId, estabelecimentoId, ...body } = params;
            const result = await api.post(`/v1/clientes/${clienteId}/creditos`, body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── criar_vale_presente ──
    server.tool(
        'criar_vale_presente',
        'Cria um vale-presente para um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            valor: z.number().positive().describe('Valor do vale-presente (em reais)'),
            descricao: z.string().optional().describe('Descrição do vale-presente'),
        },
        async (params) => {
            const { clienteId, estabelecimentoId, ...body } = params;
            const result = await api.post(`/v1/clientes/${clienteId}/valespresentes`, body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── listar_etiquetas_cliente ──
    server.tool(
        'listar_etiquetas_cliente',
        'Lista as etiquetas (tags) associadas a um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.get(`/v1/clientes/${params.clienteId}/etiquetas`, undefined, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── adicionar_etiqueta_cliente ──
    server.tool(
        'adicionar_etiqueta_cliente',
        'Associa uma etiqueta a um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            etiquetaId: z.number().int().describe('ID da etiqueta a adicionar'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.post(`/v1/clientes/${params.clienteId}/etiquetas`, { etiquetaId: params.etiquetaId }, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── remover_etiqueta_cliente ──
    server.tool(
        'remover_etiqueta_cliente',
        'Remove uma etiqueta de um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            etiquetaId: z.number().int().describe('ID da etiqueta a remover'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            await api.delete(`/v1/clientes/${params.clienteId}/etiquetas/${params.etiquetaId}`, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: 'Etiqueta removida com sucesso.' }] };
        }
    );

    // ── listar_telefones_cliente ──
    server.tool(
        'listar_telefones_cliente',
        'Lista os telefones cadastrados de um cliente.',
        {
            clienteId: z.number().int().describe('ID do cliente'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.get(`/v1/clientes/${params.clienteId}/telefones`, undefined, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );
}
