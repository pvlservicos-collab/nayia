-- Adiciona a coluna 'rank' para permitir a reordenação de campos customizados na tela
ALTER TABLE public.custom_field_definitions
ADD COLUMN IF NOT EXISTS rank numeric(20, 6) DEFAULT 0;

-- Cria um índice para otimizar ordenação por ranking
CREATE INDEX IF NOT EXISTS idx_custom_fields_rank ON public.custom_field_definitions(organization_id, category_id, rank) WHERE deleted_at IS NULL;

-- Popula os campos existentes com um rank base (baseado na data de criação)
DO $$
DECLARE
    r RECORD;
    v_rank numeric(20, 6);
BEGIN
    FOR r IN (
        SELECT id, category_id, organization_id
        FROM public.custom_field_definitions
        ORDER BY organization_id, category_id, created_at ASC
    ) LOOP
        -- Define o rank inicial baseado na ordem de criação, espaçando por 1000
        -- (Isso facilita a inserção de novos itens no meio, usando a média entre dois ranks)
        SELECT COALESCE(MAX(rank), 0) + 1000 INTO v_rank
        FROM public.custom_field_definitions
        WHERE organization_id = r.organization_id 
          AND (category_id = r.category_id OR (category_id IS NULL AND r.category_id IS NULL))
          AND id != r.id; -- ignora ele mesmo caso estejamos atualizando

        UPDATE public.custom_field_definitions
        SET rank = COALESCE(v_rank, 1000)
        WHERE id = r.id;
    END LOOP;
END $$;
