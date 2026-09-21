-- =========================================================
-- 008) RANK REBALANCING — Redistribuição de ranks de estágios
-- Implementa:
--   1. rebalance_stage_ranks(p_pipeline_id, p_org_id)
--      Redistribui os ranks dos estágios com espaçamento
--      uniforme de 10000 quando os valores convergirem.
-- =========================================================

-- =========================================================
-- 1. rebalance_stage_ranks(p_pipeline_id, p_org_id)
--    Reordena os estágios ativos preservando a ordem atual
--    (ORDER BY rank ASC) e reatribui ranks com step = 10000.
--    Exemplo: 10000, 20000, 30000, ...
--
--    Casos de uso:
--    - Após muitos reorders, ranks ficam muito próximos
--      (ex: 1.0000001, 1.0000002) e a inserção entre eles
--      se torna impossível com numeric(20,6).
--    - Deve ser chamado pelo cliente quando
--      max(rank) - min(rank) / count < threshold.
--
--    Retorna: { rebalanced_count, step }
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
    -- Valida que o pipeline pertence à org
    IF NOT EXISTS (
        SELECT 1 FROM public.pipelines
        WHERE id              = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
    ) THEN
        RAISE EXCEPTION 'Pipeline not found or does not belong to organization';
    END IF;

    -- Itera pelos estágios ativos na ordem atual de rank
    -- e reatribui valores com espaçamento uniforme
    FOR v_stage IN
        SELECT id
        FROM public.pipeline_stages
        WHERE pipeline_id     = p_pipeline_id
          AND organization_id = p_org_id
          AND deleted_at IS NULL
        ORDER BY rank ASC, created_at ASC  -- created_at como desempate
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
