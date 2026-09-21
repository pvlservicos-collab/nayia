-- =========================================================
-- 005) RPC FUNCTIONS — Lógica transacional do CRM
-- Todas as funções usam SET search_path = '' e qualificam
-- tabelas com public. para evitar search_path injection.
-- =========================================================

-- =========================================================
-- 1. delete_pipeline_stage
--    Move leads para o estágio de fallback (se fornecido)
--    e faz soft-delete do estágio de forma atômica.
--    Retorna o número de leads movidos.
-- =========================================================
CREATE OR REPLACE FUNCTION public.delete_pipeline_stage(
    p_stage_id        uuid,
    p_org_id          uuid,
    p_fallback_stage_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_moved_count   integer := 0;
    v_actor_id      uuid;
    v_lead          record;
BEGIN
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

        -- Obtém o member_id do usuário atual (via auth.uid() → profiles → members)
        SELECT id INTO v_actor_id
        FROM public.organization_members
        WHERE user_id = auth.uid()
          AND organization_id = p_org_id
          AND deleted_at IS NULL
        LIMIT 1;

        -- Move leads e registra histórico para cada um
        FOR v_lead IN
            SELECT id FROM public.leads
            WHERE stage_id = p_stage_id
              AND organization_id = p_org_id
              AND deleted_at IS NULL
        LOOP
            -- Registra no histórico
            INSERT INTO public.lead_stage_history
                (organization_id, lead_id, from_stage_id, to_stage_id, changed_by_member_id, changed_at)
            VALUES
                (p_org_id, v_lead.id, p_stage_id, p_fallback_stage_id, v_actor_id, now());

            v_moved_count := v_moved_count + 1;
        END LOOP;

        -- Atualiza os leads em lote
        UPDATE public.leads
        SET stage_id   = p_fallback_stage_id,
            updated_at = now()
        WHERE stage_id        = p_stage_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL;

    ELSE
        -- Sem fallback: apenas conta leads (não move — leads ficam sem estágio)
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
-- 2. reorder_pipeline_stages
--    Recebe [{id, rank}] e atualiza os ranks em lote.
--    Valida que todos os estágios pertencem ao pipeline/org.
--    Retorna lista de estágios atualizados.
-- =========================================================
CREATE OR REPLACE FUNCTION public.reorder_pipeline_stages(
    p_pipeline_id  uuid,
    p_org_id       uuid,
    p_stage_ranks  jsonb     -- [{"id": "uuid", "rank": 1.0}, ...]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_item      jsonb;
    v_stage_id  uuid;
    v_rank      numeric;
    v_count     integer := 0;
BEGIN
    -- Valida que o pipeline pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.pipelines
        WHERE id = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Pipeline not found or does not belong to organization';
    END IF;

    -- Itera sobre os pares {id, rank} e atualiza cada estágio
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_stage_ranks)
    LOOP
        v_stage_id := (v_item->>'id')::uuid;
        v_rank     := (v_item->>'rank')::numeric;

        -- Valida que o estágio pertence ao pipeline/org
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
-- 3. remove_member
--    Transfere leads do membro removido para outro membro
--    (opcional) e faz soft-delete do membro.
--    Retorna o número de leads transferidos.
-- =========================================================
CREATE OR REPLACE FUNCTION public.remove_member(
    p_member_id              uuid,
    p_org_id                 uuid,
    p_transfer_to_member_id  uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_transferred_count integer := 0;
BEGIN
    -- Valida que o membro pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.organization_members
        WHERE id              = p_member_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Member not found or does not belong to organization';
    END IF;

    -- Valida o membro de destino (se fornecido)
    IF p_transfer_to_member_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.organization_members
            WHERE id              = p_transfer_to_member_id
              AND organization_id = p_org_id
              AND deleted_at IS NULL
        ) THEN
            RAISE EXCEPTION 'Transfer target member not found or does not belong to organization';
        END IF;

        -- Transfere leads
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
-- 4. delete_custom_field
--    Remove os valores indexados do campo e faz soft-delete
--    da definição do campo customizado.
--    Retorna o número de valores deletados.
-- =========================================================
CREATE OR REPLACE FUNCTION public.delete_custom_field(
    p_field_id  uuid,
    p_org_id    uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_deleted_values_count integer := 0;
BEGIN
    -- Valida que o campo pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.custom_field_definitions
        WHERE id              = p_field_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Custom field not found or does not belong to organization';
    END IF;

    -- Remove valores indexados (hard delete — são dados derivados)
    DELETE FROM public.custom_field_index_values
    WHERE field_id        = p_field_id
      AND organization_id = p_org_id;

    GET DIAGNOSTICS v_deleted_values_count = ROW_COUNT;

    -- Soft-delete da definição
    UPDATE public.custom_field_definitions
    SET deleted_at = now(),
        updated_at = now()
    WHERE id              = p_field_id
      AND organization_id = p_org_id;

    RETURN jsonb_build_object('deleted_values_count', v_deleted_values_count);
END;
$$;
