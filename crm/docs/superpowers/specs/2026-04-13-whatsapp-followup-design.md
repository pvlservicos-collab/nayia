# WhatsApp Cloud — Follow-up Worker

**Status:** Design aprovado pelo usuário em 2026-04-13. Pendente de 6 pré-requisitos técnicos antes de virar plano de implementação.
**Org piloto:** Todabella (`d17ec329-e074-46a0-b5a4-f3617e161cca`).

## 1. Objetivo

Automatizar dois tipos de follow-up via WhatsApp Cloud API oficial:

1. **Template HSM de 24h** — dispara 24h após o lead entrar nos stages `Follow-up` ou `Pronto para pagar`, se ele não respondeu nesse período.
2. **Nudge de 4h** — texto livre `"Oi, podemos continuar?"`, dispara 4h após nossa última mensagem outbound sem reply do lead.

Tudo respeitando janela comercial 08:00–18:00 `America/Manaus` e excluindo leads de origem UAZAPI.

## 2. Non-goals (explícitos)

- **Modelo de consentimento / opt-in / opt-out.** Decisão consciente do usuário em 2026-04-13: não implementar. Não reabrir.
- **Rotação do system token do WhatsApp.** Repo privado, decisão consciente (vide `security_decisions.md`).
- **Múltiplos follow-ups por stage.** Apenas 1 template de 24h por entrada no stage + 1 nudge por fase de silêncio.
- **Suporte a outros canais** (SMS, email). Só WhatsApp.
- **UI de edição de templates.** Templates são aprovados no gerenciador da Meta; o sistema só referencia por nome.

## 3. Contexto técnico

| Item | Valor |
|---|---|
| WABA ID | `876161085193833` |
| Stage `Follow-up` | `d3d3031f-bc4b-44df-bd83-b1f07d7fbf85` |
| Stage `Pronto para pagar` | `0a58795e-31c1-4cdd-9cfa-408412d5ce7a` |
| Template 24h (`Follow-up`) | `follow_up_avaliacao` (pt_BR, POSITIONAL, zero params, APPROVED) |
| Template 24h (`Pronto para pagar`) | `followup_comprovante` (pt_BR, POSITIONAL, zero params, APPROVED) |
| Graph API version | `v21.0` |
| Integração UAZAPI existente | `45ad01da-e241-467c-9336-8bbd09af8c7d` (`type='whatsapp_lite'`) |

## 4. Arquitetura

**Scheduler:** Supabase Scheduled Edge Function a cada 5 minutos.
**Execução:** Edge Function `follow-up-worker` em `supabase/functions/follow-up-worker/`.
**Fila:** nenhuma fila externa. A Edge Function **faz polling direto** em `leads` + `lead_activities` + `lead_stage_history` a cada tick.
**Idempotência:** tabela `follow_up_dispatches(lead_id, stage_entry_id, kind)` com UNIQUE. Insert antes do envio (`ON CONFLICT DO NOTHING`); se conflito → outro tick já pegou, skip.
**Credenciais:** `integrations.config` + Supabase Vault via nova RPC `get_integration_secret_service`.
**Auth do endpoint:** header `x-cron-secret` validado contra env var.

### Fluxo de um tick

```
Para cada integration com type='whatsapp_cloud_official' AND status='active':
  Carrega config + token do Vault
  Se hora atual America/Manaus ∉ [start_hour, end_hour] da org → skip org

  # Bloco 1: template 24h
  SELECT leads elegíveis (ver query §6)
  Para cada lead:
    INSERT INTO follow_up_dispatches (lead_id, stage_entry_id, kind='template_24h')
      ON CONFLICT DO NOTHING RETURNING id
    Se inserido:
      POST Graph API → template
      INSERT lead_activities (source='automation', kind='template_24h', stage_entry_id, wamid)

  # Bloco 2: nudge 4h
  SELECT leads elegíveis (ver query §7)
  Para cada lead:
    INSERT INTO follow_up_dispatches (lead_id, stage_entry_id, kind='nudge_4h')
      ON CONFLICT DO NOTHING RETURNING id
    Se inserido:
      Validar last_inbound_at < 24h (janela Meta aberta); se não, marcar falha
      POST Graph API → text
      INSERT lead_activities
```

## 5. Data model

### 5.1 Nova linha em `integrations`

```
type = 'whatsapp_cloud_official'
status = 'active'
config = {
  "waba_id": "876161085193833",
  "phone_number_id": "<a descobrir via Graph API>",
  "graph_api_version": "v21.0",
  "templates": {
    "d3d3031f-bc4b-44df-bd83-b1f07d7fbf85": "follow_up_avaliacao",
    "0a58795e-31c1-4cdd-9cfa-408412d5ce7a": "followup_comprovante"
  }
}
secret_id → vault.secrets (via upsert_integration_secret)
```

### 5.2 Nova tabela `follow_up_dispatches`

```sql
CREATE TABLE follow_up_dispatches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL REFERENCES organizations(id),
  lead_id uuid NOT NULL,
  stage_entry_id uuid NOT NULL REFERENCES lead_stage_history(id),
  kind text NOT NULL CHECK (kind IN ('template_24h','nudge_4h')),
  dispatched_at timestamptz NOT NULL DEFAULT now(),
  wamid text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','failed')),
  error jsonb,
  attempt int NOT NULL DEFAULT 1,
  CONSTRAINT uq_dispatch UNIQUE (lead_id, stage_entry_id, kind)
);

CREATE INDEX idx_dispatch_org_kind ON follow_up_dispatches (organization_id, kind, status);
```

Service role bypassa RLS; policy explícita bloqueia qualquer outro role. Tabela não aparece na UI (observability vem de `lead_activities`).

### 5.3 Config em `automation_settings` (por org)

```
key='follow_up_business_hours'
variables={"start_hour":8,"end_hour":18,"tz":"America/Manaus"}
is_enabled=true
```

Kill-switch reutiliza a coluna existente `automation_settings.is_enabled`.

### 5.4 Índices adicionais

```sql
CREATE INDEX idx_activities_inbound_by_lead
  ON lead_activities (lead_id, created_at DESC)
  WHERE metadata->>'direction' = 'inbound';

CREATE INDEX idx_stage_history_lead_stage
  ON lead_stage_history (lead_id, to_stage_id, changed_at DESC);
```

### 5.5 Migration

Nome: `027_whatsapp_cloud_followup.sql` (025 = `025_rls_production_safe_part3.sql`; 026 já em uso por `026_lead_search.sql`).

## 6. Query do bloco 24h

```sql
WITH current_entry AS (
  SELECT DISTINCT ON (l.id)
    l.id AS lead_id,
    l.organization_id,
    l.phone,
    l.stage_id,
    h.id AS stage_entry_id,
    h.changed_at
  FROM leads l
  LEFT JOIN integrations i ON i.id = l.integration_id
  JOIN lead_stage_history h
    ON h.lead_id = l.id AND h.to_stage_id = l.stage_id
  WHERE l.organization_id = :org
    AND l.deleted_at IS NULL
    AND l.stage_id IN (:followup_stage, :about_to_pay_stage)
    AND (i.id IS NULL OR i.type <> 'whatsapp_lite')
  ORDER BY l.id, h.changed_at DESC
)
SELECT ce.*
FROM current_entry ce
WHERE ce.changed_at <= now() - interval '24 hours'
  AND NOT EXISTS (
    SELECT 1 FROM lead_activities a
    WHERE a.lead_id = ce.lead_id
      AND a.metadata->>'direction' = 'inbound'
      AND a.created_at > ce.changed_at
  )
  AND NOT EXISTS (
    SELECT 1 FROM follow_up_dispatches d
    WHERE d.lead_id = ce.lead_id
      AND d.stage_entry_id = ce.stage_entry_id
      AND d.kind = 'template_24h'
  );
```

**Cutoff de backfill no primeiro rollout:** `AND ce.changed_at > now() - interval '48 hours'` — evita bombardear leads antigos.

## 7. Query do bloco 4h

```sql
WITH last_msgs AS (
  SELECT
    l.id AS lead_id, l.organization_id, l.phone, l.stage_id,
    (SELECT MAX(a.created_at) FROM lead_activities a
      WHERE a.lead_id = l.id AND a.metadata->>'direction'='outbound') AS last_out,
    (SELECT MAX(a.created_at) FROM lead_activities a
      WHERE a.lead_id = l.id AND a.metadata->>'direction'='inbound') AS last_in,
    h.id AS stage_entry_id
  FROM leads l
  LEFT JOIN integrations i ON i.id = l.integration_id
  JOIN LATERAL (
    SELECT id FROM lead_stage_history
    WHERE lead_id = l.id AND to_stage_id = l.stage_id
    ORDER BY changed_at DESC LIMIT 1
  ) h ON true
  WHERE l.organization_id = :org
    AND l.deleted_at IS NULL
    AND l.stage_id IN (:followup_stage, :about_to_pay_stage)
    AND (i.id IS NULL OR i.type <> 'whatsapp_lite')
)
SELECT * FROM last_msgs
WHERE last_out IS NOT NULL
  AND last_out <= now() - interval '4 hours'
  AND (last_in IS NULL OR last_in < last_out)
  AND (last_in IS NOT NULL AND last_in > now() - interval '24 hours')  -- janela Meta aberta
  AND NOT EXISTS (
    SELECT 1 FROM follow_up_dispatches d
    WHERE d.lead_id = last_msgs.lead_id
      AND d.kind = 'nudge_4h'
      AND d.dispatched_at > COALESCE(last_in, '-infinity'::timestamptz)
  );
```

A última cláusula garante "1 nudge por fase de silêncio": só dispara se não há nudge desde a última inbound.

## 8. Envio Graph API

### Template
```
POST https://graph.facebook.com/v21.0/{phone_number_id}/messages
Authorization: Bearer {token}
{
  "messaging_product": "whatsapp",
  "to": "<phone sem +>",
  "type": "template",
  "template": {
    "name": "<follow_up_avaliacao | followup_comprovante>",
    "language": { "code": "pt_BR" }
  }
}
```
**Omitir `components` inteiramente** (templates são POSITIONAL com zero variáveis).

### Texto
```
{
  "messaging_product": "whatsapp",
  "to": "<phone sem +>",
  "type": "text",
  "text": { "body": "Oi, podemos continuar?" }
}
```

### Persistência
Após resposta 200:
```
INSERT INTO lead_activities (organization_id, lead_id, type, content, metadata)
VALUES (:org, :lead, 'whatsapp', <texto>, jsonb_build_object(
  'source','automation',
  'direction','outbound',
  'kind', <'template_24h'|'nudge_4h'>,
  'template_name', <nome ou null>,
  'stage_entry_id', <uuid>,
  'wamid', <id retornado>
));
UPDATE follow_up_dispatches SET status='sent', wamid=... WHERE id=:dispatch_id;
```

Em erro: `status='failed'`, `error=<jsonb>`. Retry até 3 tentativas, backoff 30s/2min/10min. Em 429 respeitar `Retry-After`.

## 9. Pré-requisitos (bloqueadores antes do plano de implementação)

Estes 6 itens precisam estar feitos antes do `writing-plans` deste spec:

1. **Header secreto no endpoint Edge Function.** Env `FOLLOW_UP_CRON_SECRET`. Worker rejeita requests sem header.
2. **RPC `get_integration_secret_service(p_integration_id, p_org_id)`** `SECURITY DEFINER`, `GRANT EXECUTE` restrito a `service_role`. Retorna o secret sem checar `has_permission()`.
3. **Trigger `AFTER INSERT ON leads`** que insere primeira linha em `lead_stage_history` com `from_stage_id=NULL` quando `NEW.stage_id IS NOT NULL`. Sem isso, leads criados direto no stage nunca são detectados.
4. **HMAC no webhook UAZAPI** — já listado na Janela 0 do `ROADMAP.md`.
5. **Remover `ignoreBuildErrors`** do `next.config.ts` — já listado na Janela 0.
6. **Refactor real da UI `whatsapp-cloud-api/page.tsx`** com campos `waba_id`, `phone_number_id`, `system_token` (este último via `upsert_integration_secret`); handler de submit; diferenciação visual da card UAZAPI.

## 10. Observabilidade

- Todos os envios geram linha em `lead_activities` → aparecem na timeline do lead na UI naturalmente.
- `follow_up_dispatches.status` e `.error` para debugging técnico.
- Logs estruturados JSON no stdout da Edge Function (`console.log(JSON.stringify({...}))`).
- Tabela `follow_up_worker_runs(tick_at, orgs_processed, sent_count, failed_count, duration_ms)` para contagens por execução — opcional, decidir no plano.

## 11. Rollout

1. Migration 026 aplicada.
2. Pré-requisitos §9 prontos.
3. Linha em `integrations` criada via script, secret no Vault.
4. `automation_settings` seed para Todabella com `is_enabled=false`.
5. Edge Function deployada, mas Scheduled Function desligada.
6. Teste manual: `curl` no endpoint com header secreto, verificar seleção de 1 lead seed que está > 24h em `Follow-up`.
7. Ligar Scheduled Function.
8. Ligar `is_enabled=true` para Todabella.
9. Monitorar `follow_up_dispatches` por 48h antes de declarar estável.

## 12. Riscos residuais aceitos

- **Sem opt-in/opt-out:** decisão consciente do usuário. Risco de quality rating drop na Meta mitigado pelo volume inicial baixo.
- **Rate limit Meta:** tier inicial é suficiente para Todabella; revisitar quando outras orgs entrarem.
- **Endpoint público no Supabase:** mitigado pelo header secreto; não é defense-in-depth, mas suficiente para o perfil de ameaça atual.
- **Webhook de status da Meta** (`sent`/`delivered`/`read`/`failed`) não é processado nesta v1. Dispatches marcados como `sent` quando Graph API retorna 200, sem saber se foi entregue. Adicionar em v2 se necessário.

## 13. Trabalho futuro (fora desta v1)

- Processamento de webhook de status da Meta para atualizar `lead_activities.metadata.delivery_status`.
- Tabela de worker_runs com dashboard.
- Sincronização de versão Graph API com Kestra (Kestra hoje usa v19.0).
- Tabela de template registry se o número de templates crescer além de 2.
