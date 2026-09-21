
// Define the OpenAPI Specification for TitaCRM API
const SOURCE_FIELD = {
    type: 'string',
    description: 'Fonte da requisição (Obrigatório). Identifica quem está realizando a ação. Ex: "system", "ai_agent", "human".',
    enum: ['system', 'ai_agent', 'human']
}

const spec = {
    openapi: '3.1.0',
    info: {
        title: 'TitaCRM API',
        version: '1.0.0',
        description: 'Documentação oficial da API do TitaCRM. Utilize esta API para integrar serviços externos, gerenciar leads, organizações e pipelines.\n\n## Autenticação e Segurança\n\nToda requisição deve incluir um Bearer Token (JWT do Supabase Auth) no header `Authorization`. O sistema extrai o `user_id` do JWT e consulta a tabela `organization_members` para identificar a **organização** à qual o usuário pertence. Dessa forma, **todos os dados retornados e todas as operações de escrita são automaticamente limitados (scoped) à organização do token fornecido**, impedindo acesso a dados de outras organizações.\n\nFluxo interno:\n1. `Authorization: Bearer <JWT>` → Supabase decodifica → `user_id`\n2. `user_id` → consulta `organization_members` → obtém `organization_id` + `member_id`\n3. Todas as queries usam `organization_id` como filtro obrigatório\n\n**Importante:** Todos os endpoints de escrita (POST, PATCH, DELETE) exigem o campo `source` no body da requisição para rastreabilidade de quem/o quê realizou a ação (valores: `system`, `ai_agent`, `human`).',
        contact: {
            name: 'Suporte TitaCRM',
            url: 'https://atlaseye.com/support',
        }
    },
    servers: [
        {
            url: 'http://localhost:3000/api',
            description: 'Local Development Server'
        },
        {
            url: 'https://api.atlaseye.com/v1',
            description: 'Production Server'
        }
    ],
    components: {
        securitySchemes: {
            BearerAuth: {
                type: 'http',
                scheme: 'bearer',
                bearerFormat: 'JWT',
                description: 'Autenticação via JWT (Supabase Auth)'
            },
            ApiKeyAuth: {
                type: 'apiKey',
                in: 'header',
                name: 'x-api-key',
                description: 'Chave de API para integrações servidor-servidor'
            }
        }
    },
    security: [
        {
            BearerAuth: [],
            ApiKeyAuth: []
        }
    ],
    paths: {
        // =================== LEADS ===================
        '/leads': {
            get: {
                tags: ['Leads'],
                summary: 'Listar Leads',
                description: 'Retorna uma lista paginada de todos os leads associados à sua organização.',
                parameters: [
                    { name: 'q', in: 'query', description: 'Busca textual geral (pesquisa pelo nome, email, empresa ou outros campos preenchidos do lead).', required: false, schema: { type: 'string' } },
                    { name: 'tags', in: 'query', description: 'Filtra resultados pelas tags associadas ao lead. Aceita uma string ou array de IDs/nomes de tags.', required: false, schema: { type: 'array', items: { type: 'string' } } },
                    { name: 'phone', in: 'query', description: 'Filtra leads pelo número de telefone (correspondência exata ou parcial).', required: false, schema: { type: 'string' } },
                    { name: 'assigned_to', in: 'query', description: 'Filtra leads pelo ID do usuário responsável (UUID).', required: false, schema: { type: 'string', format: 'uuid' } },
                    { name: 'pipeline_id', in: 'query', description: 'Filtra leads que pertencem a um funil de vendas (pipeline) específico pelo seu UUID.', required: false, schema: { type: 'string', format: 'uuid' } },
                    { name: 'status', in: 'query', description: 'Filtra leads pelo status atual (ex: open, won, lost).', required: false, schema: { type: 'string' } },
                    { name: 'page', in: 'query', description: 'Número da página para paginação.', required: false, schema: { type: 'integer', default: 1 } },
                    { name: 'limit', in: 'query', description: 'Quantidade de registros por página.', required: false, schema: { type: 'integer', default: 20 } }
                ],
                responses: {
                    '200': {
                        description: 'Lista de leads retornada com sucesso.',
                        content: {
                            'application/json': {
                                schema: {
                                    type: 'object',
                                    properties: {
                                        data: { type: 'array', items: { type: 'object', properties: { id: { type: 'string', format: 'uuid' }, name: { type: 'string' }, email: { type: 'string' }, phone: { type: 'string' }, status: { type: 'string' }, created_at: { type: 'string', format: 'date-time' } } } },
                                        meta: { type: 'object', properties: { totalCount: { type: 'integer' }, page: { type: 'integer' } } }
                                    }
                                }
                            }
                        }
                    },
                    '401': { description: 'Não autorizado.' }
                }
            },
            post: {
                tags: ['Leads'],
                summary: 'Adicionando Leads',
                description: 'Cria um novo lead na sua organização.',
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['name', 'source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    name: { type: 'string', description: 'Nome do lead (Obrigatório)' },
                                    email: { type: 'string', description: 'E-mail do lead' },
                                    phone: { type: 'string', description: 'Telefone de contato' },
                                    status: { type: 'string', description: 'Status inicial (ex: open)' },
                                    assigned_to: { type: 'string', format: 'uuid', description: 'ID do usuário responsável' },
                                    pipeline_id: { type: 'string', format: 'uuid', description: 'ID do funil de vendas' },
                                    tags: { type: 'array', items: { type: 'string' }, description: 'Lista de IDs de tags para associar' }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '201': { description: 'Lead criado com sucesso.', content: { 'application/json': { schema: { type: 'object', properties: { id: { type: 'string', format: 'uuid' }, name: { type: 'string' } } } } } },
                    '400': { description: 'Dados inválidos fornecidos.' },
                    '401': { description: 'Não autorizado.' }
                }
            }
        },
        '/leads/{id}': {
            patch: {
                tags: ['Leads'],
                summary: 'Atualizando Leads',
                description: 'Atualiza os dados de um lead existente. Envie apenas os campos que deseja alterar. Também permite atualizar tags e campos personalizados.',
                parameters: [{ name: 'id', in: 'path', description: 'UUID do lead que será atualizado.', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    name: { type: 'string', description: 'Nome do lead' },
                                    email: { type: 'string', description: 'E-mail do lead' },
                                    phone: { type: 'string', description: 'Telefone de contato' },
                                    status: { type: 'string', description: 'Status do lead' },
                                    assigned_to: { type: 'string', format: 'uuid', description: 'ID do usuário responsável' },
                                    pipeline_id: { type: 'string', format: 'uuid', description: 'ID do funil de vendas' },
                                    tags: {
                                        type: 'array',
                                        items: { type: 'string' },
                                        description: 'Lista de IDs de tags. Substitui todas as tags atuais do lead por esta lista.'
                                    },
                                    custom_fields: {
                                        type: 'object',
                                        description: 'Objeto de campos personalizados para atualizar. Chave = field_id, valor = novo valor. Ex: { "field-uuid-1": "Texto novo", "field-uuid-2": 42 }',
                                        additionalProperties: true
                                    }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '200': { description: 'Lead atualizado com sucesso.', content: { 'application/json': { schema: { type: 'object', properties: { id: { type: 'string', format: 'uuid' }, name: { type: 'string' } } } } } },
                    '400': { description: 'Dados inválidos.' },
                    '401': { description: 'Não autorizado.' },
                    '404': { description: 'Lead não encontrado.' }
                }
            }
        },

        // =================== CHAT / MENSAGENS ===================
        '/leads/{id}/messages': {
            post: {
                tags: ['Chat'],
                summary: 'Enviar mensagem no chat do lead',
                description: 'Envia uma mensagem no chat do lead. Pode ser usada por agentes IA, automações ou humanos para inserir mensagens na conversa. A mensagem é registrada como atividade do lead e, se for do tipo "whatsapp", será enviada diretamente via integração ativa.',
                parameters: [{ name: 'id', in: 'path', description: 'UUID do lead destinatário.', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['content', 'type', 'source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    content: { type: 'string', description: 'Conteúdo da mensagem a ser enviada.' },
                                    type: {
                                        type: 'string',
                                        enum: ['whatsapp', 'note', 'email', 'system'],
                                        description: 'Tipo da mensagem. "whatsapp" envia via integração ativa, "note" é apenas uma anotação interna, "email" e "system" são para uso interno.'
                                    },
                                    direction: {
                                        type: 'string',
                                        enum: ['inbound', 'outbound'],
                                        default: 'outbound',
                                        description: 'Direção da mensagem. "outbound" = enviada para o lead. "inbound" = recebida do lead.'
                                    },
                                    sender_name: { type: 'string', description: 'Nome do remetente exibido na interface. Ex: "Agente IA", "João (Vendas)"' },
                                    reply_to_message_id: { type: 'string', description: 'ID da mensagem original para respostas (reply/quote).' },
                                    media_url: { type: 'string', description: 'URL do arquivo de mídia anexado (imagem, documento, áudio).' },
                                    media_type: { type: 'string', enum: ['image', 'video', 'audio', 'document', 'sticker'], description: 'Tipo do arquivo de mídia anexado.' }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '201': { description: 'Mensagem enviada com sucesso.', content: { 'application/json': { schema: { type: 'object', properties: { id: { type: 'string', format: 'uuid' }, content: { type: 'string' }, created_at: { type: 'string', format: 'date-time' } } } } } },
                    '400': { description: 'Dados inválidos (ex: conteúdo vazio).' },
                    '401': { description: 'Não autorizado.' },
                    '404': { description: 'Lead não encontrado.' }
                }
            }
        },

        // =================== HISTÓRICO DE LEADS ===================
        '/leads/{id}/history': {
            post: {
                tags: ['Histórico de Leads'],
                summary: 'Adicionando ao histórico',
                description: 'Adiciona um evento ao histórico do lead. Pode ser uma nota, registro de ligação, ação de automação ou qualquer outro tipo de atividade.',
                parameters: [{ name: 'id', in: 'path', description: 'UUID do lead.', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['content', 'type', 'source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    type: { type: 'string', enum: ['note', 'call', 'email', 'system', 'whatsapp'], description: 'Tipo do evento de histórico.' },
                                    content: { type: 'string', description: 'Descrição ou conteúdo do evento.' },
                                    metadata: { type: 'object', description: 'Metadados adicionais do evento (JSON livre).', additionalProperties: true }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '201': { description: 'Evento de histórico criado com sucesso.' },
                    '401': { description: 'Não autorizado.' }
                }
            }
        },
        '/leads/history/{event_id}': {
            patch: {
                tags: ['Histórico de Leads'],
                summary: 'Editando evento do histórico',
                description: 'Edita o conteúdo ou metadados de um evento existente no histórico do lead.',
                parameters: [{ name: 'event_id', in: 'path', description: 'UUID do evento de histórico.', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    content: { type: 'string', description: 'Novo conteúdo do evento.' },
                                    metadata: { type: 'object', description: 'Novos metadados do evento.', additionalProperties: true }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '200': { description: 'Evento atualizado com sucesso.' },
                    '401': { description: 'Não autorizado.' },
                    '404': { description: 'Evento não encontrado.' }
                }
            },
            delete: {
                tags: ['Histórico de Leads'],
                summary: 'Excluindo evento do histórico',
                description: 'Remove permanentemente um evento do histórico do lead.',
                parameters: [
                    { name: 'event_id', in: 'path', description: 'UUID do evento de histórico.', required: true, schema: { type: 'string', format: 'uuid' } },
                    { name: 'source', in: 'query', description: 'Fonte da requisição (Obrigatório). Identifica quem está realizando a ação.', required: true, schema: SOURCE_FIELD }
                ],
                responses: {
                    '204': { description: 'Evento deletado com sucesso.' },
                    '401': { description: 'Não autorizado.' },
                    '404': { description: 'Evento não encontrado.' }
                }
            }
        },

        // =================== PIPELINES E ESTÁGIOS DE LEADS ===================
        '/pipelines': {
            get: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Lista de pipelines',
                description: 'Retorna a lista de funis de vendas da organização ativa.',
                responses: { '200': { description: 'Sucesso.', content: { 'application/json': { schema: { type: 'array', items: { type: 'object' } } } } } }
            },
            post: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Adicionando pipelines',
                description: 'Cria um novo funil de vendas (pipeline).',
                requestBody: {
                    required: true,
                    content: { 'application/json': { schema: { type: 'object', required: ['name', 'source'], properties: { source: SOURCE_FIELD, name: { type: 'string', description: 'Nome do pipeline' } } } } }
                },
                responses: { '201': { description: 'Criado com sucesso.' } }
            }
        },
        '/pipelines/{id}': {
            get: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Obtendo um pipeline pelo seu ID',
                description: 'Recupera os detalhes de um pipeline específico.',
                parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } }],
                responses: { '200': { description: 'Sucesso.' }, '404': { description: 'Não encontrado.' } }
            },
            patch: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Editar um pipeline',
                description: 'Atualiza o nome ou configurações do pipeline pelo ID.',
                parameters: [{ name: 'id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: { content: { 'application/json': { schema: { type: 'object', required: ['source'], properties: { source: SOURCE_FIELD, name: { type: 'string' } } } } } },
                responses: { '200': { description: 'Atualizado com sucesso.' } }
            },
            delete: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Excluindo um pipeline',
                description: 'Deleta um pipeline permanentemente.',
                parameters: [
                    { name: 'id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } },
                    { name: 'source', in: 'query', description: 'Fonte da requisição (Obrigatório).', required: true, schema: SOURCE_FIELD }
                ],
                responses: { '204': { description: 'Deletado com sucesso.' } }
            }
        },
        '/pipelines/{id}/stages': {
            get: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Lista de etapas do Pipeline',
                description: 'Retorna todas as etapas associadas a um pipeline específico.',
                parameters: [{ name: 'id', in: 'path', description: 'ID do Pipeline', required: true, schema: { type: 'string', format: 'uuid' } }],
                responses: { '200': { description: 'Sucesso.' } }
            },
            post: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Adicionando Etapas no Pipeline',
                description: 'Cria uma nova etapa dentro de um pipeline específico.',
                parameters: [{ name: 'id', in: 'path', description: 'ID do Pipeline', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: {
                    required: true,
                    content: { 'application/json': { schema: { type: 'object', required: ['name', 'source'], properties: { source: SOURCE_FIELD, name: { type: 'string' }, color: { type: 'string' }, order: { type: 'integer' } } } } }
                },
                responses: { '201': { description: 'Criado com sucesso.' } }
            }
        },
        '/pipelines/stages/{stage_id}': {
            get: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Obtendo dados de uma etapa do pipeline pelo seu ID',
                description: 'Recupera detalhes de uma etapa específica.',
                parameters: [{ name: 'stage_id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } }],
                responses: { '200': { description: 'Sucesso.' } }
            },
            patch: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Edição de Etapa do Pipeline',
                description: 'Atualiza os dados de uma etapa (nome, cor, ordem).',
                parameters: [{ name: 'stage_id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } }],
                requestBody: { content: { 'application/json': { schema: { type: 'object', required: ['source'], properties: { source: SOURCE_FIELD, name: { type: 'string' }, color: { type: 'string' }, order: { type: 'integer' } } } } } },
                responses: { '200': { description: 'Atualizado com sucesso.' } }
            },
            delete: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Exclusão de Etapa do Pipeline',
                description: 'Deleta uma etapa de pipeline permanentemente.',
                parameters: [
                    { name: 'stage_id', in: 'path', required: true, schema: { type: 'string', format: 'uuid' } },
                    { name: 'source', in: 'query', description: 'Fonte da requisição (Obrigatório).', required: true, schema: SOURCE_FIELD }
                ],
                responses: { '204': { description: 'Deletado com sucesso.' } }
            }
        },
        '/pipelines/stage-colors': {
            get: {
                tags: ['Pipelines e estágios de leads'],
                summary: 'Cores de Etapa disponíveis',
                description: 'Lista as cores pré-definidas disponíveis para uso nas etapas dos pipelines.',
                responses: { '200': { description: 'Sucesso.' } }
            }
        },

        // =================== NOTIFICAÇÕES ===================
        '/notifications': {
            post: {
                tags: ['Notificações'],
                summary: 'Disparar notificação',
                description: 'Envia uma notificação para todos os membros da organização ou para um membro específico. Se `recipient_member_id` não for informado, a notificação é enviada para TODOS os membros ativos da organização.',
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['title', 'content', 'source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    title: { type: 'string', description: 'Título da notificação.' },
                                    content: { type: 'string', description: 'Corpo/conteúdo da notificação.' },
                                    recipient_member_id: { type: 'string', format: 'uuid', description: 'ID do membro destinatário. Se omitido, a notificação é enviada para TODOS os membros da organização.' },
                                    type: { type: 'string', description: 'Tipo da notificação (ex: "info", "warning", "success", "error").', default: 'info' },
                                    link_url: { type: 'string', description: 'URL de redirecionamento ao clicar na notificação (ex: "/chat/lead-uuid").' }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '201': { description: 'Notificação(ões) enviada(s) com sucesso.', content: { 'application/json': { schema: { type: 'object', properties: { sent_to: { type: 'integer', description: 'Quantidade de membros notificados.' } } } } } },
                    '400': { description: 'Dados inválidos.' },
                    '401': { description: 'Não autorizado.' }
                }
            }
        },

        // =================== USUÁRIOS ===================
        '/users': {
            get: {
                tags: ['Usuários'],
                summary: 'Listar usuários da organização',
                description: 'Retorna a lista de todos os membros ativos da organização vinculada ao token. Inclui ID do membro, nome, avatar e role.',
                responses: {
                    '200': {
                        description: 'Sucesso.',
                        content: {
                            'application/json': {
                                schema: {
                                    type: 'array',
                                    items: {
                                        type: 'object',
                                        properties: {
                                            id: { type: 'string', format: 'uuid', description: 'ID do membro (member_id) — use este ID para atribuir leads, enviar notificações, etc.' },
                                            user_id: { type: 'string', format: 'uuid', description: 'ID do usuário no auth.' },
                                            role_id: { type: 'string', format: 'uuid' },
                                            status: { type: 'string' },
                                            full_name: { type: 'string', description: 'Nome completo do membro.' },
                                            avatar_url: { type: 'string', description: 'URL do avatar.' },
                                            created_at: { type: 'string', format: 'date-time' }
                                        }
                                    }
                                }
                            }
                        }
                    },
                    '401': { description: 'Não autorizado.' }
                }
            },
            post: {
                tags: ['Usuários'],
                summary: 'Adicionar usuário à organização',
                description: 'Convida/adiciona um novo membro à organização atual.',
                requestBody: {
                    required: true,
                    content: {
                        'application/json': {
                            schema: {
                                type: 'object',
                                required: ['email', 'role_id', 'source'],
                                properties: {
                                    source: SOURCE_FIELD,
                                    email: { type: 'string', description: 'E-mail do usuário a ser convidado.' },
                                    role_id: { type: 'string', format: 'uuid', description: 'ID do cargo/role atribuído ao novo membro.' },
                                    full_name: { type: 'string', description: 'Nome completo (opcional, será preenchido pelo próprio user no primeiro login).' }
                                }
                            }
                        }
                    }
                },
                responses: {
                    '201': { description: 'Membro adicionado com sucesso.' },
                    '400': { description: 'Dados inválidos ou e-mail já é membro.' },
                    '401': { description: 'Não autorizado.' }
                }
            }
        },
        '/users/{member_id}': {
            delete: {
                tags: ['Usuários'],
                summary: 'Remover usuário da organização',
                description: 'Remove (desativa) um membro da organização. Não deleta o usuário do sistema, apenas a associação com a organização.',
                parameters: [
                    { name: 'member_id', in: 'path', description: 'ID do membro a ser removido.', required: true, schema: { type: 'string', format: 'uuid' } },
                    { name: 'source', in: 'query', description: 'Fonte da requisição (Obrigatório).', required: true, schema: SOURCE_FIELD }
                ],
                responses: {
                    '204': { description: 'Membro removido com sucesso.' },
                    '401': { description: 'Não autorizado.' },
                    '404': { description: 'Membro não encontrado.' }
                }
            }
        }
    }
}

export function GET() {
    const html = `
<!DOCTYPE html>
<html>
  <head>
    <title>TitaCRM API Reference</title>
    <meta charset="utf-8" />
    <meta
      name="viewport"
      content="width=device-width, initial-scale=1" />
    <style>
      body { margin: 0; padding: 0; background-color: #ffffff; }
    </style>
  </head>
  <body>
    <script id="api-reference" type="application/json" data-configuration='{"theme": "default", "layout": "modern"}'>
      ${JSON.stringify(spec)}
    </script>
    <script src="https://cdn.jsdelivr.net/npm/@scalar/api-reference"></script>
  </body>
</html>
  `;

    return new Response(html, {
        headers: {
            'Content-Type': 'text/html',
        },
    });
}
