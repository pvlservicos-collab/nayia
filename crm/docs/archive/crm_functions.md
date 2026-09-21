# Funções do CRM - Baseado no Schema Atual

Status: **API Ready** - As funções abaixo foram validadas para uso via API REST ou chamadas diretas (Supabase Client / Edge Functions).

## Legenda de Implementação
*   **[Client]**: Operação CRUD simples, pode ser feita direto pelo cliente Supabase com RLS.
*   **[Edge]**: Requer lógica de negócio complexa, validações ou transações atômicas (Edge Function/RPC).

> [!IMPORTANT]
> **Protocolo de Criação de Funções**
> Antes de implementar qualquer nova *Edge Function* ou *Database Function* (RPC), **VERIFIQUE SE ELA JÁ EXISTE**.
> 1.  Liste as funções existentes no banco (`\df` ou via Supabase Dashboard).
> 2.  Verifique a pasta `supabase/functions` do projeto.
> 3.  Evite duplicidade de lógica (ex: não criar `delete_stage_v2` se `delete_stage` já existe e pode ser refatorada).

## 1. Gestão de Pipelines e Estágios (Funil)
O sistema parece utilizar `pipeline_stages` vinculados a `workspaces` para definir o fluxo.

*   **`createPipelineStage(workspaceId, name, statusKey, position, color)`** `POST /stages` **[Client]**
*   **`updatePipelineStage(stageId, data)`** `PATCH /stages/:id` **[Client]**
*   **`deletePipelineStage(stageId, fallbackStageId?)`** `DELETE /stages/:id` **[Edge]**
    *   **Motivo [Edge]:** Precisa realizar a validação de leads existentes e a movimentação atômica (transação) dos leads para o `fallbackStageId` *antes* de deletar o estágio.
    *   **Payload:** `{ fallbackStageId: "uuid" }` (opcional).
*   **`reorderPipelineStages(workspaceId, orderedStageIds)`** `POST /stages/reorder` **[Edge]**
    *   **Motivo [Edge]:** Atualização em lote (batch update) para garantir integridade da ordem visual.
*   **`listPipelineStages(workspaceId)`** `GET /workspaces/:id/stages` **[Client]**

## 2. Gestão de Leads (Oportunidades)
O núcleo do CRM. Os leads possuem dados nativos e relacionamentos.

### Criação e Movimentação
*   **`createLead(workspaceId, stageId, title, ownerId, data)`** `POST /leads` **[Client/Edge]**
    *   **Nota:** Pode ser via Client, mas recomenda-se Edge se houver muita validação de dados obrigatórios ou triggers de notificação.
*   **`moveLead(leadId, newStageId)`** `PATCH /leads/:id/move` **[Client]**
    *   **Validação:** RLS garante que o usuário tem acesso ao lead e ao estágio.
*   **`updateLeadStatus(leadId, status)`** `PATCH /leads/:id` **[Client]**
*   **`assignLead(leadId, userId)`** `PATCH /leads/:id/assign` **[Client]**

### Edição de Dados Nativos (Campos Core)
*   **`updateLeadContact(leadId, email, phone)`** `PATCH /leads/:id` **[Client]**
    *   **Payload:** `{ email, phone }`

### Edição de Atributos (Dados Flexíveis)
*   **`updateLeadAttributes(leadId, attributes)`** `PATCH /leads/:id` **[Client]**
    *   **Payload:** `{ custom_attributes: { priority, value, linkedin_url } }`
    *   **Nota:** `value` e outros campos não-core são armazenados no JSONB.

## 3. Campos Customizados (Custom Fields)
Para dados que não têm coluna própria na tabela `leads`.

*   **`createCustomField(workspaceId, name, fieldType, icon)`** `POST /custom-fields` **[Client]**
*   **`editCustomField(fieldId, data)`** `PATCH /custom-fields/:id` **[Client]**
*   **`deleteCustomField(fieldId)`** `DELETE /custom-fields/:id` **[Edge]**
    *   **Motivo [Edge]:** Para garantir limpeza correta de `custom_field_values` órfãos (embora `ON DELETE CASCADE` no banco possa resolver, uma Edge Function permite logar a perda de dados ou fazer backup preventivo).
*   **`setCustomFieldValue(leadId, fieldId, value)`** `POST /leads/:id/custom-fields` **[Client]**
    *   Upsert (Insert ou Update) na tabela `custom_field_values`.
*   **`getLeadCustomValues(leadId)`** `GET /leads/:id/custom-fields` **[Client]**

## 4. Gestão de Tags (Etiquetas)
Sistema de categorização flexível.

*   **`createTag(workspaceId, name, color)`** `POST /tags` **[Client]**
*   **`updateTag(tagId, name, color)`** `PATCH /tags/:id` **[Client]**
*   **`deleteTag(tagId)`** `DELETE /tags/:id` **[Client]**
    *   O banco já deve ter `ON DELETE CASCADE` na tabela de junção `lead_tags`.
*   **`addTagToLead(leadId, tagId)`** `POST /leads/:id/tags` **[Client]**
*   **`removeTagFromLead(leadId, tagId)`** `DELETE /leads/:id/tags/:tagId` **[Client]**

## 5. Mensagens e Histórico
*   **`addLeadMessage(leadId, userId, content, isInternal)`** `POST /leads/:id/messages` **[Client]**
*   **`listLeadTimeline(leadId)`** `GET /leads/:id/timeline` **[Client]**

## 6. Gestão de Membros e Permissões
*   **`inviteMemberToWorkspace(workspaceId, email, role)`** `POST /workspaces/:id/invite` **[Edge]**
    *   **Motivo [Edge]:** Envolve envio de e-mail (Resend/SendGrid) e criação de registro de convite, não apenas banco de dados.
*   **`updateMemberRole(workspaceId, userId, newRole)`** `PATCH /members/:id/role` **[Client]**
*   **`removeMember(workspaceId, userId, transferLeadsToUserId?)`** `DELETE /members/:id` **[Edge]**
    *   **Motivo [Edge]:** Lógica complexa de transferência de responsabilidade de leads (update em massa na tabela leads onde `owner_id = userRemovido`).
