# Refactor — `LeadDetailsSidebar.tsx`

**Arquivo alvo:** `atlas-eye/src/components/Chat/LeadDetailsSidebar.tsx` (758 linhas)
**Meta:** componente final ≤180 linhas; 0 `any`; lógica de domínio fora do componente.

---

## Mapa atual de responsabilidades

| Trecho | Linhas | Responsabilidade | Destino |
|---|---|---|---|
| `CustomFieldSelect` | 46-103 | Dropdown genérico single-select | `Shared/CustomFieldSelect.tsx` |
| `CustomFieldMultiSelect` | 105-180 | Dropdown genérico multi-select | `Shared/CustomFieldMultiSelect.tsx` |
| Imports + props | 1-43 | - | fica |
| Handlers de webhook (`handleSidebarWebhook`, `getSidebarButtonStyles`, `renderSidebarButtonIcon`, `getSidebarButtonTextClass`) | 213-261 | Lógica de botões de ação IA | `Chat/LeadSidebar/ActionButtons.tsx` |
| Estado + handler de renomear | 209-271, 285-330 | Edit de `lead.title` com optimistic + log de history | hook `useLeadRename(lead, onUpdateLead)` |
| Header (avatar + name + tags + add-tag menu) | 339-489 | UI do cabeçalho | `Chat/LeadSidebar/LeadHeader.tsx` |
| `<style>` inline para `.tag-pill` | 392-403 | CSS | mover para `globals.css` ou classe Tailwind arbitrária |
| Action buttons grid | 524-570 | UI dos 4 botões sidebar | `Chat/LeadSidebar/ActionButtons.tsx` |
| Responsável | 493-521 | UI do owner | `Chat/LeadSidebar/OwnerRow.tsx` |
| Informações de contato | 574-611 | Email + telefone | `Chat/LeadSidebar/ContactInfo.tsx` |
| Campos customizados (group by category + render por tipo) | 615-730 | Render de 5 tipos de campo + colapso por categoria | `Chat/LeadSidebar/CustomFieldsSection.tsx` |
| FunnelMiniMap (já extraído) | 734-746 | - | fica (já é componente) |
| LeadHistoryTimeline (já extraído) | 750-754 | - | fica |

---

## Estrutura alvo de arquivos

```
atlas-eye/src/components/
├── Chat/
│   ├── LeadDetailsSidebar.tsx          ← ~150 linhas (orquestrador)
│   ├── LeadSidebar/
│   │   ├── LeadHeader.tsx              ← avatar + nome editável + tags
│   │   ├── ActionButtons.tsx           ← 4 botões de webhook IA
│   │   ├── OwnerRow.tsx                ← responsável
│   │   ├── ContactInfo.tsx             ← email + telefone
│   │   └── CustomFieldsSection.tsx     ← campos customizados agrupados
│   ├── FunnelMiniMap.tsx               ← (existente)
│   ├── LeadHistoryTimeline.tsx         ← (existente)
│   └── ...
└── Shared/
    ├── CustomFieldSelect.tsx           ← extraído (genérico, reusável)
    └── CustomFieldMultiSelect.tsx      ← extraído (genérico, reusável)
```

```
atlas-eye/src/hooks/
├── useLeadRename.ts                    ← novo: optimistic update + log de history
└── useSidebarWebhook.ts                ← novo: estado sending/success/error dos botões
```

---

## Passos do refactor (ordem recomendada)

### 1. Extrair `CustomFieldSelect` e `CustomFieldMultiSelect` (baixo risco)
- Mover para `components/Shared/`.
- Tipagem: `options: string[]`, sem mudança de API.
- **Verificar** com `grep` se alguém mais usa esses componentes hoje (se não, apenas arquivos novos + import).
- **Ganho:** -135 linhas, componentes reutilizáveis.

### 2. Extrair `<style>` inline
- Criar classe `.tag-pill` em `atlas-eye/src/app/globals.css` (ou usar `group-hover:` puro do Tailwind no X).
- Remover `<style>{...}</style>` do JSX.
- **Ganho:** -12 linhas; elimina style inline em runtime.

### 3. Extrair `useLeadRename` hook
```ts
// hooks/useLeadRename.ts
export function useLeadRename(lead, onUpdateLead) {
  const { currentOrganization, user, profileName } = useAuth()
  const [isEditing, setIsEditing] = useState(false)
  const [value, setValue] = useState(lead.title)
  const inputRef = useRef<HTMLInputElement>(null)

  useEffect(() => setValue(lead.title), [lead.title])
  useEffect(() => { if (isEditing) inputRef.current?.focus() }, [isEditing])

  const save = useCallback(async () => { /* lógica existente 285-330 */ }, [...])
  const cancel = useCallback(() => { setValue(lead.title); setIsEditing(false) }, [...])

  return { isEditing, setIsEditing, value, setValue, inputRef, save, cancel }
}
```
- Move a query Supabase para fora do componente.
- **Ganho:** -50 linhas no componente; lógica testável isolada.

### 4. Extrair `useSidebarWebhook` hook
```ts
// hooks/useSidebarWebhook.ts
export function useSidebarWebhook() {
  const [status, setStatus] = useState<{ key: ChatButtonKey; status: 'sending'|'success'|'error' } | null>(null)
  const { fireWebhook } = useChatButtonSettings()

  const trigger = useCallback(async (key, payload) => { /* 218-223 */ }, [fireWebhook])
  const getButtonStyles = useCallback((key, hoverClass) => { /* 225-236 */ }, [status])
  const getButtonIcon = useCallback((key, Icon, color) => { /* 238-252 */ }, [status])
  const getButtonTextClass = useCallback((key) => { /* 254-261 */ }, [status])

  return { trigger, getButtonStyles, getButtonIcon, getButtonTextClass }
}
```

### 5. Extrair componentes filhos

Ordem por tamanho/complexidade (menor primeiro):

- **OwnerRow** (28 linhas) — props: `owner`, `ownerName`
- **ContactInfo** (38 linhas) — props: `email`, `phone`
- **ActionButtons** (50 linhas + hook) — props: `lead`, `stages`, usa `useChatButtonSettings` e `useSidebarWebhook` internamente
- **LeadHeader** (150 linhas) — props: `lead`, `onUpdateLead`, `onTagsChange`; usa `useLeadRename` e `useTags` internamente
- **CustomFieldsSection** (115 linhas) — props: `leadId`, `organizationId`; usa `useCustomFields` internamente

### 6. Orquestrador final

```tsx
export default function LeadDetailsSidebar({ lead, stages, stageHistory, ...props }: Props) {
  return (
    <aside className="w-72 border-l border-gray-200 flex flex-col flex-shrink-0 overflow-y-auto bg-white">
      <div className="p-5 space-y-5">
        <LeadHeader lead={lead} onUpdateLead={props.onUpdateLead} onTagsChange={props.onTagsChange} />
        <Divider />
        <OwnerRow owner={lead.owner} />
        <ActionButtons lead={lead} stages={stages} />
        <Divider />
        <ContactInfo email={lead.email} phone={lead.phone} />
        <Divider />
        <CustomFieldsSection leadId={lead.id} organizationId={lead.organization_id} />
        <Divider />
        {stages.length > 0 && lead.stage_id && (
          <FunnelMiniMap
            stages={stages}
            currentStageId={lead.stage_id}
            history={stageHistory}
            loading={props.stageHistoryLoading}
            onStageClick={props.onStageChange}
            pipelines={props.pipelines}
            currentPipelineId={props.currentPipelineId}
            onPipelineChange={props.onPipelineChange}
          />
        )}
        <Divider />
        <LeadHistoryTimeline organizationId={lead.organization_id} leadId={lead.id} />
      </div>
    </aside>
  )
}
```

---

## Eliminação de `any`

5 ocorrências atuais:

| Linha | Atual | Alvo |
|---|---|---|
| 38 | `tagObj?: any` em prop | `tagObj?: Tag` (importar de types.ts) |
| 238 | `DefaultIcon: any` | `DefaultIcon: IconComponent` (type do @phosphor-icons) |
| 408 | `(lt: any) => { const tag = lt.tag \|\| ... }` | tipar `LeadTag` com union `{ tag?: Tag; tag_id: string }` |
| 457 | `displayTags.map((lt: any) =>` | idem |
| - | `onTagsChange?: (..., tagObj?: any) => void` | `tagObj?: Tag` |

---

## Métricas de sucesso

| Métrica | Antes | Alvo |
|---|---|---|
| Linhas em LeadDetailsSidebar.tsx | 758 | ≤180 |
| Linhas em qualquer um dos filhos | — | ≤200 |
| Ocorrências de `any` | 5 | 0 |
| Queries Supabase dentro do componente | 2 | 0 |
| Componentes/hooks novos extraídos | 0 | 5 componentes + 2 hooks |

---

## Riscos

1. **`useCustomFields` em cada filho** — se cada seção invocar o hook, pode duplicar fetch. Mitigação: manter o hook chamado uma vez no topo e passar dados via prop, OU garantir que o hook tem cache interno/SWR. **Verificar antes de quebrar.**
2. **`useTags` idem** — mesma consideração.
3. **Event bubbling do click-outside** — 3 componentes (`CustomFieldSelect`, `CustomFieldMultiSelect`, tag-menu) têm listeners `mousedown` globais. Ao extrair, garantir que ref isolation continua funcionando. Testar em dev.
4. **Inline `<style>`** — se existir algum override em CSS externo dependendo de `.tag-pill`, quebra. Fazer `grep` antes de mover.
5. **Realtime / optimistic em rename** — `handleSaveName` insere linha em `lead_activities`. Mover para hook não pode perder o log de auditoria. Cobrir com teste manual após extração.

---

## Ordem de execução segura

1. **PR #1** — extrair `CustomFieldSelect` e `CustomFieldMultiSelect` (só mover código; sem quebra funcional). Testar na UI.
2. **PR #2** — extrair `<style>` para `globals.css`. Testar tag-pill hover.
3. **PR #3** — extrair `useLeadRename` e `useSidebarWebhook`. Testar rename + webhooks.
4. **PR #4** — extrair `OwnerRow`, `ContactInfo`, `ActionButtons` (3 componentes simples).
5. **PR #5** — extrair `LeadHeader` (maior, mais risco).
6. **PR #6** — extrair `CustomFieldsSection` (lógica de grouping + render por tipo).
7. **PR #7** — eliminar `any` com tipos reais de `LeadTag` e `IconComponent`.

Cada PR é testável isoladamente no browser abrindo um lead e conferindo: rename, tags add/remove, botões IA, campos customizados (text, number, date, datetime, select, multi_select), colapso de categorias.

---

## Estimativa

| PR | Horas | Risco |
|---|---|---|
| #1 | 1h | 🟢 baixo |
| #2 | 0.5h | 🟢 baixo |
| #3 | 2h | 🟡 médio (query Supabase) |
| #4 | 1.5h | 🟢 baixo |
| #5 | 3h | 🟠 alto (tag menu tem lógica complexa) |
| #6 | 3h | 🟠 alto (5 tipos de campo + grouping) |
| #7 | 1h | 🟢 baixo |
| **Total** | **~12h** | |

Sem testes automatizados no projeto, validação é manual. Ideal é quebrar em 7 PRs pequenos que o reviewer consegue aprovar em minutos cada, do que um PR único de 12h que ninguém consegue revisar.
