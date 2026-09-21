-- =========================================================
-- 009) RPC RBAC FIX — Adiciona verificação de caller nas RPCs
-- SECURITY DEFINER bypassa RLS, então os checks precisam ser
-- feitos INTERNAMENTE via has_permission() / is_org_member().
--
-- Funções corrigidas:
--   1. delete_pipeline_stage   → has_permission('manage_pipelines')
--   2. reorder_pipeline_stages → has_permission('manage_pipelines')
--   3. remove_member           → has_permission('remove_members')
--   4. delete_custom_field     → has_permission('manage_custom_fields')
--   5. rebalance_stage_ranks   → is_org_member() (operação não-destrutiva)
-- =========================================================

-- =========================================================
-- 1. delete_pipeline_stage (corrigido)
-- =========================================================
CREATE OR REPLACE FUNCTION public.delete_pipeline_stage(
    p_stage_id          uuid,
    p_org_id            uuid,
    p_fallback_stage_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_moved_count integer := 0;
    v_actor_id    uuid;
    v_lead        record;
BEGIN
    -- RBAC: caller deve ter manage_pipelines na org
    IF NOT public.has_permission(p_org_id, 'manage_pipelines') THEN
        RAISE EXCEPTION 'Permission denied: manage_pipelines required';
    END IF;

    -- Verifica que o estágio pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.pipeline_stages
        WHERE id = p_stage_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Stage not found or does not belong to organization';
    END IF;

    -- Verifica fallback (se fornecido)
    IF p_fallback_stage_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.pipeline_stages
            WHERE id = p_fallback_stage_id
              AND organization_id = p_org_id
              AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Fallback stage not found or does not belong to organization';
        END IF;

        -- Obtém o member_id do caller
        SELECT id INTO v_actor_id
        FROM public.organization_members
        WHERE user_id         = auth.uid()
          AND organization_id = p_org_id
          AND deleted_at IS NULL
        LIMIT 1;

        -- Move leads e registra histórico
        FOR v_lead IN
            SELECT id FROM public.leads
            WHERE stage_id        = p_stage_id
              AND organization_id = p_org_id
              AND deleted_at IS NULL
        LOOP
            INSERT INTO public.lead_stage_history
                (organization_id, lead_id, from_stage_id, to_stage_id, changed_by_member_id, changed_at)
            VALUES
                (p_org_id, v_lead.id, p_stage_id, p_fallback_stage_id, v_actor_id, now());

            v_moved_count := v_moved_count + 1;
        END LOOP;

        UPDATE public.leads
        SET stage_id   = p_fallback_stage_id,
            updated_at = now()
        WHERE stage_id        = p_stage_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL;
    ELSE
        SELECT COUNT(*) INTO v_moved_count
        FROM public.leads
        WHERE stage_id        = p_stage_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL;
    END IF;

    -- Soft-delete do estágio
    UPDATE public.pipeline_stages
    SET deleted_at = now(),
        updated_at = now()
    WHERE id              = p_stage_id
      AND organization_id = p_org_id;

    RETURN jsonb_build_object('moved_count', v_moved_count);
END;
$$;

-- =========================================================
-- 2. reorder_pipeline_stages (corrigido)
-- =========================================================
CREATE OR REPLACE FUNCTION public.reorder_pipeline_stages(
    p_pipeline_id uuid,
    p_org_id      uuid,
    p_stage_ranks jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_item     jsonb;
    v_stage_id uuid;
    v_rank     numeric;
    v_count    integer := 0;
BEGIN
    -- RBAC: caller deve ter manage_pipelines na org
    IF NOT public.has_permission(p_org_id, 'manage_pipelines') THEN
        RAISE EXCEPTION 'Permission denied: manage_pipelines required';
    END IF;

    -- Valida que o pipeline pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.pipelines
        WHERE id              = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Pipeline not found or does not belong to organization';
    END IF;

    FOR v_item IN SELECT * FROM jsonb_array_elements(p_stage_ranks)
    LOOP
        v_stage_id := (v_item->>'id')::uuid;
        v_rank     := (v_item->>'rank')::numeric;

        UPDATE public.pipeline_stages
        SET rank       = v_rank,
            updated_at = now()
        WHERE id              = v_stage_id
          AND pipeline_id     = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Stage % not found in pipeline or does not belong to organization', v_stage_id;
        END IF;

        v_count := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object('updated_count', v_count);
END;
$$;

-- =========================================================
-- 3. remove_member (corrigido)
-- =========================================================
CREATE OR REPLACE FUNCTION public.remove_member(
    p_member_id             uuid,
    p_org_id                uuid,
    p_transfer_to_member_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_transferred_count integer := 0;
BEGIN
    -- RBAC: caller deve ter remove_members na org
    IF NOT public.has_permission(p_org_id, 'remove_members') THEN
        RAISE EXCEPTION 'Permission denied: remove_members required';
    END IF;

    -- Valida que o membro a remover pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE id              = p_member_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Member not found or does not belong to organization';
    END IF;

    -- Valida membro de destino (se fornecido)
    IF p_transfer_to_member_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members
            WHERE id              = p_transfer_to_member_id
              AND organization_id = p_org_id
              AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Transfer target member not found or does not belong to organization';
        END IF;

        UPDATE public.leads
        SET owner_member_id = p_transfer_to_member_id,
            updated_at      = now()
        WHERE owner_member_id = p_member_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL;

        GET DIAGNOSTICS v_transferred_count = ROW_COUNT;
    END IF;

    -- Soft-delete do membro
    UPDATE public.organization_members
    SET deleted_at = now(),
        updated_at = now(),
        status     = 'disabled'
    WHERE id              = p_member_id
      AND organization_id = p_org_id;

    RETURN jsonb_build_object('transferred_leads_count', v_transferred_count);
END;
$$;

-- =========================================================
-- 4. delete_custom_field (corrigido)
-- =========================================================
CREATE OR REPLACE FUNCTION public.delete_custom_field(
    p_field_id uuid,
    p_org_id   uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_deleted_values_count integer := 0;
BEGIN
    -- RBAC: caller deve ter manage_custom_fields na org
    IF NOT public.has_permission(p_org_id, 'manage_custom_fields') THEN
        RAISE EXCEPTION 'Permission denied: manage_custom_fields required';
    END IF;

    -- Valida que o campo pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.custom_field_definitions
        WHERE id              = p_field_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Custom field not found or does not belong to organization';
    END IF;

    DELETE FROM public.custom_field_index_values
    WHERE field_id        = p_field_id
      AND organization_id = p_org_id;

    GET DIAGNOSTICS v_deleted_values_count = ROW_COUNT;

    UPDATE public.custom_field_definitions
    SET deleted_at = now(),
        updated_at = now()
    WHERE id              = p_field_id
      AND organization_id = p_org_id;

    RETURN jsonb_build_object('deleted_values_count', v_deleted_values_count);
END;
$$;

-- =========================================================
-- 5. rebalance_stage_ranks (corrigido)
--    Não é destrutivo, mas exige que o caller seja membro ativo.
-- =========================================================
CREATE OR REPLACE FUNCTION public.rebalance_stage_ranks(
    p_pipeline_id uuid,
    p_org_id      uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_stage    record;
    v_new_rank numeric := 10000.0;
    v_step     numeric := 10000.0;
    v_count    integer := 0;
BEGIN
    -- Membership: qualquer membro ativo pode rebalancear
    IF NOT public.is_org_member(p_org_id) THEN
        RAISE EXCEPTION 'Permission denied: active membership required';
    END IF;

    -- Valida que o pipeline pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.pipelines
        WHERE id              = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Pipeline not found or does not belong to organization';
    END IF;

    FOR v_stage IN
        SELECT id
        FROM public.pipeline_stages
        WHERE pipeline_id     = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
        ORDER BY rank ASC, created_at ASC
    LOOP
        UPDATE public.pipeline_stages
        SET rank       = v_new_rank,
            updated_at = now()
        WHERE id              = v_stage.id
          AND pipeline_id     = p_pipeline_id
          AND organization_id = p_org_id;

        v_new_rank := v_new_rank + v_step;
        v_count    := v_count + 1;
    END LOOP;

    RETURN jsonb_build_object(
        'rebalanced_count', v_count,
        'step',             v_step
    );
END;
$$;
