/**
 * Trinks MCP — Agendamentos Tools (10 tools)
 *
 * listar_agendamentos, buscar_agendamento, criar_agendamento, atualizar_agendamento,
 * confirmar_agendamento, cancelar_agendamento, finalizar_agendamento,
 * marcar_cliente_faltou, marcar_em_atendimento,
 * listar_agendas_profissionais
 */
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from 'zod';
import { api } from '../http-client.js';

export function registerAgendamentosTools(server: McpServer): void {

    // ── listar_agendamentos ──
    server.tool(
        'listar_agendamentos',
        'Lista agendamentos do estabelecimento. Pode filtrar por cliente, data de início/fim e status.',
        {
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento (usa o padrão da env se omitido)'),
            clienteId: z.number().int().optional().describe('Filtrar por ID do cliente'),
            dataInicio: z.string().optional().describe('Data início no formato YYYY-MM-DD'),
            dataFim: z.string().optional().describe('Data fim no formato YYYY-MM-DD'),
            page: z.number().int().min(1).optional().describe('Página (default: 1)'),
            pageSize: z.number().int().min(1).max(100).optional().describe('Itens por página (default: 20, max: 100)'),
        },
        async (params) => {
            const q: Record<string, string | number | boolean | undefined> = {};
            if (params.clienteId) q.clienteId = params.clienteId;
            if (params.dataInicio) q.dataInicio = params.dataInicio;
            if (params.dataFim) q.dataFim = params.dataFim;
            if (params.page) q.page = params.page;
            if (params.pageSize) q.pageSize = params.pageSize;

            const result = await api.get('/v1/agendamentos', q, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── buscar_agendamento ──
    server.tool(
        'buscar_agendamento',
        'Retorna os detalhes completos de um agendamento pelo ID.',
        {
            id: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.get(`/v1/agendamentos/${params.id}`, undefined, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── criar_agendamento ──
    server.tool(
        'criar_agendamento',
        'Cria um novo agendamento no Trinks.',
        {
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            clienteId: z.number().int().describe('ID do cliente'),
            profissionalId: z.number().int().describe('ID do profissional'),
            servicoId: z.number().int().describe('ID do serviço'),
            dataHora: z.string().describe('Data e hora do agendamento (ISO 8601, ex: 2024-03-15T10:00:00)'),
            observacao: z.string().optional().describe('Observação sobre o agendamento'),
        },
        async (params) => {
            const { estabelecimentoId, ...body } = params;
            const result = await api.post('/v1/agendamentos', body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── atualizar_agendamento ──
    server.tool(
        'atualizar_agendamento',
        'Atualiza dados de um agendamento existente (data, profissional, serviço, observação).',
        {
            agendamentoId: z.number().int().describe('ID do agendamento a atualizar'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
            profissionalId: z.number().int().optional().describe('Novo ID do profissional'),
            servicoId: z.number().int().optional().describe('Novo ID do serviço'),
            dataHora: z.string().optional().describe('Nova data e hora (ISO 8601)'),
            observacao: z.string().optional().describe('Nova observação'),
        },
        async (params) => {
            const { agendamentoId, estabelecimentoId, ...body } = params;
            const result = await api.put(`/v1/agendamentos/${agendamentoId}`, body as Record<string, unknown>, estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── confirmar_agendamento ──
    server.tool(
        'confirmar_agendamento',
        'Confirma um agendamento (muda o status para "confirmado").',
        {
            agendamentoId: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.patch(`/v1/agendamentos/${params.agendamentoId}/status/confirmado`, {}, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── cancelar_agendamento ──
    server.tool(
        'cancelar_agendamento',
        'Cancela um agendamento.',
        {
            agendamentoId: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.patch(`/v1/agendamentos/${params.agendamentoId}/status/cancelado`, {}, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── finalizar_agendamento ──
    server.tool(
        'finalizar_agendamento',
        'Marca um agendamento como finalizado (atendimento concluído).',
        {
            agendamentoId: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.patch(`/v1/agendamentos/${params.agendamentoId}/status/finalizado`, {}, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── marcar_cliente_faltou ──
    server.tool(
        'marcar_cliente_faltou',
        'Registra que o cliente não compareceu ao agendamento (no-show).',
        {
            agendamentoId: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.patch(`/v1/agendamentos/${params.agendamentoId}/status/clientefaltou`, {}, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── marcar_em_atendimento ──
    server.tool(
        'marcar_em_atendimento',
        'Marca que o cliente está em atendimento no momento.',
        {
            agendamentoId: z.number().int().describe('ID do agendamento'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.patch(`/v1/agendamentos/${params.agendamentoId}/status/ematendimento`, {}, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );

    // ── listar_agendas_profissionais ──
    server.tool(
        'listar_agendas_profissionais',
        'Lista a agenda de todos os profissionais em uma data específica.',
        {
            data: z.string().describe('Data no formato YYYY-MM-DD'),
            estabelecimentoId: z.string().optional().describe('ID do estabelecimento'),
        },
        async (params) => {
            const result = await api.get(`/v1/agendamentos/profissionais/${params.data}`, undefined, params.estabelecimentoId);
            return { content: [{ type: 'text' as const, text: JSON.stringify(result.data, null, 2) }] };
        }
    );
}
