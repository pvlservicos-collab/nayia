-- =========================================================
-- 006) RBAC, AUTOMAÇÕES E AUDIT TRAIL
-- Implementa:
--   1. has_permission()             — helper RBAC via roles.permissions
--   2. record_lead_stage_change()   — trigger → lead_stage_history
--   3. notify_lead_assigned()       — trigger → notifications (lead atribuído)
--   4. notify_lead_stage_changed()  — trigger → notifications (estágio mudou)
--   5. log_member_changes()         — trigger → audit_logs (membros)
--   6. log_stage_soft_delete()      — trigger → audit_logs (estágios)
--   7. RLS write policies           — escrita granular com has_permission()
-- =========================================================

-- =========================================================
-- 1. has_permission()
--    Retorna true se o usuário atual tem a permissão p_permission
--    na organização p_org_id (via organization_roles.permissions jsonb).
--
--    Estrutura esperada em organization_roles.permissions:
--    {
--      "manage_pipelines":    true,  -- criar/editar/deletar pipelines/estágios
--      "manage_custom_fields": true, -- criar/editar/deletar campos customizados
--      "manage_integrations": true,  -- criar/editar integrações
--      "manage_roles":        true,  -- criar/editar roles
--      "invite_members":      true,  -- convidar membros
--      "remove_members":      true,  -- remover membros
--      "view_audit_logs":     true   -- ver logs de auditoria
--    }
-- =========================================================
CREATE OR REPLACE FUNCTION public.has_permission(
    p_org_id     uuid,
    p_permission text
)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members m
    JOIN public.organization_roles r
      ON r.id              = m.role_id
     AND r.organization_id = m.organization_id
    WHERE m.user_id         = auth.uid()
      AND m.organization_id = p_org_id
      AND m.status          = 'active'
      AND m.deleted_at      IS NULL
      AND (r.permissions ->> p_permission)::boolean = true
  );
$$;

-- =========================================================
-- 2. record_lead_stage_change()
--    Disparado AFTER UPDATE OF stage_id ON leads.
--    Grava automaticamente em lead_stage_history cada mudança de estágio,
--    capturando o membro que fez a alteração via auth.uid().
-- =========================================================
CREATE OR REPLACE FUNCTION public.record_lead_stage_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_member_id uuid;
BEGIN
    -- Só executa se stage_id realmente mudou
    IF OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id THEN
        RETURN NEW;
    END IF;

    -- Resolve o member_id do usuário atual dentro da org
    SELECT id INTO v_actor_member_id
    FROM public.organization_members
    WHERE user_id         = auth.uid()
      AND organization_id = NEW.organization_id
      AND deleted_at      IS NULL
    LIMIT 1;

    INSERT INTO public.lead_stage_history
        (organization_id, lead_id, from_stage_id, to_stage_id, changed_by_member_id, changed_at)
    VALUES
        (NEW.organization_id, NEW.id, OLD.stage_id, NEW.stage_id, v_actor_member_id, now());

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_lead_stage_change
AFTER UPDATE OF stage_id ON public.leads
FOR EACH ROW EXECUTE FUNCTION public.record_lead_stage_change();

-- =========================================================
-- 3. notify_lead_assigned()
--    Disparado AFTER UPDATE OF owner_member_id ON leads.
--    Notifica o novo owner se new_lead_alert = true
--    (ou se não houver linha em user_notification_settings).
-- =========================================================
CREATE OR REPLACE FUNCTION public.notify_lead_assigned()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_member_id uuid;
    v_wants_notif     boolean;
BEGIN
    -- Só executa se owner mudou e novo owner existe
    IF OLD.owner_member_id IS NOT DISTINCT FROM NEW.owner_member_id
       OR NEW.owner_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Verifica preferência de notificação
    SELECT new_lead_alert INTO v_wants_notif
    FROM public.user_notification_settings
    WHERE member_id = NEW.owner_member_id;

    -- Default true se sem configuração
    IF v_wants_notif IS NULL THEN
        v_wants_notif := true;
    END IF;

    IF NOT v_wants_notif THEN
        RETURN NEW;
    END IF;

    -- Resolve o actor
    SELECT id INTO v_actor_member_id
    FROM public.organization_members
    WHERE user_id         = auth.uid()
      AND organization_id = NEW.organization_id
      AND deleted_at      IS NULL
    LIMIT 1;

    INSERT INTO public.notifications
        (organization_id, recipient_member_id, actor_member_id, type, title, content)
    VALUES (
        NEW.organization_id,
        NEW.owner_member_id,
        v_actor_member_id,
        'lead_assigned',
        'Lead atribuído a você',
        'O lead "' || NEW.title || '" foi atribuído a você.'
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_lead_assigned
AFTER UPDATE OF owner_member_id ON public.leads
FOR EACH ROW EXECUTE FUNCTION public.notify_lead_assigned();

-- =========================================================
-- 4. notify_lead_stage_changed()
--    Disparado AFTER UPDATE OF stage_id ON leads.
--    Notifica o owner do lead quando outra pessoa move o estágio,
--    se last_stage_alert = true.
-- =========================================================
CREATE OR REPLACE FUNCTION public.notify_lead_stage_changed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_member_id uuid;
    v_stage_name      text;
    v_wants_notif     boolean;
BEGIN
    -- Só executa se estágio mudou e lead tem owner
    IF OLD.stage_id IS NOT DISTINCT FROM NEW.stage_id
       OR NEW.owner_member_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Resolve actor
    SELECT id INTO v_actor_member_id
    FROM public.organization_members
    WHERE user_id         = auth.uid()
      AND organization_id = NEW.organization_id
      AND deleted_at      IS NULL
    LIMIT 1;

    -- Não notifica se o próprio owner está movendo o estágio
    IF v_actor_member_id = NEW.owner_member_id THEN
        RETURN NEW;
    END IF;

    -- Verifica preferência do owner
    SELECT last_stage_alert INTO v_wants_notif
    FROM public.user_notification_settings
    WHERE member_id = NEW.owner_member_id;

    IF v_wants_notif IS NULL THEN
        v_wants_notif := true;
    END IF;

    IF NOT v_wants_notif THEN
        RETURN NEW;
    END IF;

    -- Nome do novo estágio
    SELECT name INTO v_stage_name
    FROM public.pipeline_stages
    WHERE id = NEW.stage_id;

    INSERT INTO public.notifications
        (organization_id, recipient_member_id, actor_member_id, type, title, content)
    VALUES (
        NEW.organization_id,
        NEW.owner_member_id,
        v_actor_member_id,
        'lead_stage_changed',
        'Lead movido de estágio',
        'O lead "' || NEW.title || '" foi movido para "' || COALESCE(v_stage_name, 'outro estágio') || '".'
    );

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_lead_stage_changed_notify
AFTER UPDATE OF stage_id ON public.leads
FOR EACH ROW EXECUTE FUNCTION public.notify_lead_stage_changed();

-- =========================================================
-- 5. log_member_changes()
--    Disparado AFTER INSERT OR UPDATE ON organization_members.
--    Registra em audit_logs: member.invited, member.removed,
--    member.role_changed, member.status_changed.
-- =========================================================
CREATE OR REPLACE FUNCTION public.log_member_changes()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_action          text;
    v_actor_member_id uuid;
    v_org_id          uuid;
BEGIN
    v_org_id := COALESCE(NEW.organization_id, OLD.organization_id);

    SELECT id INTO v_actor_member_id
    FROM public.organization_members
    WHERE user_id         = auth.uid()
      AND organization_id = v_org_id
      AND deleted_at      IS NULL
    LIMIT 1;

    IF TG_OP = 'INSERT' THEN
        INSERT INTO public.audit_logs
            (organization_id, actor_member_id, action, entity_type, entity_id, new_values)
        VALUES (
            v_org_id,
            v_actor_member_id,
            'member.invited',
            'organization_members',
            NEW.id,
            jsonb_build_object('user_id', NEW.user_id, 'role_id', NEW.role_id, 'status', NEW.status)
        );

    ELSIF TG_OP = 'UPDATE' THEN
        IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
            v_action := 'member.removed';
        ELSIF OLD.role_id IS DISTINCT FROM NEW.role_id THEN
            v_action := 'member.role_changed';
        ELSIF OLD.status IS DISTINCT FROM NEW.status THEN
            v_action := 'member.status_changed';
        ELSE
            RETURN NEW; -- Nenhuma mudança relevante
        END IF;

        INSERT INTO public.audit_logs
            (organization_id, actor_member_id, action, entity_type, entity_id, old_values, new_values)
        VALUES (
            v_org_id,
            v_actor_member_id,
            v_action,
            'organization_members',
            NEW.id,
            jsonb_build_object('status', OLD.status, 'role_id', OLD.role_id),
            jsonb_build_object('status', NEW.status, 'role_id', NEW.role_id)
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_member_audit
AFTER INSERT OR UPDATE ON public.organization_members
FOR EACH ROW EXECUTE FUNCTION public.log_member_changes();

-- =========================================================
-- 6. log_stage_soft_delete()
--    Disparado AFTER UPDATE OF deleted_at ON pipeline_stages.
--    Registra em audit_logs quando um estágio é soft-deletado.
-- =========================================================
CREATE OR REPLACE FUNCTION public.log_stage_soft_delete()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_actor_member_id uuid;
BEGIN
    IF OLD.deleted_at IS NULL AND NEW.deleted_at IS NOT NULL THEN
        SELECT id INTO v_actor_member_id
        FROM public.organization_members
        WHERE user_id         = auth.uid()
          AND organization_id = NEW.organization_id
          AND deleted_at      IS NULL
        LIMIT 1;

        INSERT INTO public.audit_logs
            (organization_id, actor_member_id, action, entity_type, entity_id, old_values)
        VALUES (
            NEW.organization_id,
            v_actor_member_id,
            'stage.deleted',
            'pipeline_stages',
            NEW.id,
            jsonb_build_object('name', OLD.name, 'pipeline_id', OLD.pipeline_id)
        );
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER on_stage_audit
AFTER UPDATE OF deleted_at ON public.pipeline_stages
FOR EACH ROW EXECUTE FUNCTION public.log_stage_soft_delete();

-- =========================================================
-- 7. RLS WRITE POLICIES — Proteção granular com has_permission()
--    Apenas escrita. Políticas de leitura (SELECT) já definidas
--    em 002_rls_policies.sql e continuam válidas.
-- =========================================================

-- PIPELINES: criar/editar requer manage_pipelines
CREATE POLICY "manage_pipelines: write pipelines" ON public.pipelines
FOR ALL
USING      (public.has_permission(organization_id, 'manage_pipelines'))
WITH CHECK (public.has_permission(organization_id, 'manage_pipelines'));

-- PIPELINE_STAGES: criar/editar/deletar requer manage_pipelines
CREATE POLICY "manage_pipelines: write pipeline_stages" ON public.pipeline_stages
FOR ALL
USING      (public.has_permission(organization_id, 'manage_pipelines'))
WITH CHECK (public.has_permission(organization_id, 'manage_pipelines'));

-- CUSTOM_FIELD_DEFINITIONS: requer manage_custom_fields
CREATE POLICY "manage_custom_fields: write definitions" ON public.custom_field_definitions
FOR ALL
USING      (public.has_permission(organization_id, 'manage_custom_fields'))
WITH CHECK (public.has_permission(organization_id, 'manage_custom_fields'));

-- CUSTOM_FIELD_INDEX_VALUES: qualquer membro (operação de dados de lead)
CREATE POLICY "Members can write field index values" ON public.custom_field_index_values
FOR ALL
USING      (public.is_org_member(organization_id))
WITH CHECK (public.is_org_member(organization_id));

-- TAGS: qualquer membro pode criar/editar/deletar tags
CREATE POLICY "Members can write tags" ON public.tags
FOR ALL
USING      (public.is_org_member(organization_id))
WITH CHECK (public.is_org_member(organization_id));

-- LEAD_TAGS: qualquer membro pode associar/desassociar tags
CREATE POLICY "Members can write lead_tags" ON public.lead_tags
FOR ALL
USING      (public.is_org_member(organization_id))
WITH CHECK (public.is_org_member(organization_id));

-- INTEGRATIONS: requer manage_integrations
CREATE POLICY "manage_integrations: write integrations" ON public.integrations
FOR ALL
USING      (public.has_permission(organization_id, 'manage_integrations'))
WITH CHECK (public.has_permission(organization_id, 'manage_integrations'));

-- ORGANIZATION_ROLES: requer manage_roles
CREATE POLICY "manage_roles: write organization_roles" ON public.organization_roles
FOR ALL
USING      (public.has_permission(organization_id, 'manage_roles'))
WITH CHECK (public.has_permission(organization_id, 'manage_roles'));

-- AUTOMATION_SETTINGS: qualquer membro da org pode gerenciar
CREATE POLICY "Members can write automation_settings" ON public.automation_settings
FOR ALL
USING      (public.is_org_member(organization_id))
WITH CHECK (public.is_org_member(organization_id));

-- AUDIT_LOGS: substituir policy genérica por permissão view_audit_logs
DROP POLICY IF EXISTS "Members view org audit logs" ON public.audit_logs;
CREATE POLICY "view_audit_logs: select audit_logs" ON public.audit_logs
FOR SELECT
USING (public.has_permission(organization_id, 'view_audit_logs'));

-- NOTIFICATIONS: usuários podem marcar as próprias como lidas (UPDATE)
CREATE POLICY "Users can update own notifications" ON public.notifications
FOR UPDATE
USING (
    recipient_member_id IN (
        SELECT id FROM public.organization_members WHERE user_id = auth.uid()
    )
);

-- LEAD_AI_INSIGHTS: qualquer membro pode ler e o sistema escreve via service_role
-- (INSERT/UPDATE via Edge Function com service_role bypass RLS automaticamente)
-- Política de SELECT já existe em 002_rls_policies.sql
