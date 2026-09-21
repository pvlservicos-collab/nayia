-- =========================================================
-- 007) VAULT — Gerenciamento seguro de segredos de integração
-- Implementa:
--   1. Habilita extensão supabase_vault
--   2. Adiciona coluna secret_id em integrations
--   3. upsert_integration_secret() — cria/atualiza segredo no Vault
--   4. get_integration_secret()    — lê segredo decriptado do Vault
-- =========================================================

-- =========================================================
-- 1. Habilitar Vault
-- =========================================================
CREATE EXTENSION IF NOT EXISTS "supabase_vault";

-- =========================================================
-- 2. Coluna secret_id em integrations
--    Guarda a referência ao segredo criptografado no Vault.
--    config jsonb continua para metadados não-sensíveis
--    (ex: webhook URLs, nomes de campos).
-- =========================================================
ALTER TABLE public.integrations
    ADD COLUMN IF NOT EXISTS secret_id uuid;

-- =========================================================
-- 3. upsert_integration_secret(p_integration_id, p_org_id, p_secret)
--    Requer permissão manage_integrations.
--    Se secret_id IS NULL → cria novo segredo no Vault.
--    Se secret_id EXISTS   → atualiza segredo existente.
--    Retorna o secret_id do Vault.
-- =========================================================
CREATE OR REPLACE FUNCTION public.upsert_integration_secret(
    p_integration_id uuid,
    p_org_id         uuid,
    p_secret         jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_secret_id   uuid;
    v_secret_name text;
BEGIN
    -- RBAC: somente quem tem manage_integrations pode gerenciar segredos
    IF NOT public.has_permission(p_org_id, 'manage_integrations') THEN
        RAISE EXCEPTION 'Permission denied: manage_integrations required';
    END IF;

    -- Busca secret_id atual da integração (valida tenant ao mesmo tempo)
    SELECT secret_id INTO v_secret_id
    FROM public.integrations
    WHERE id              = p_integration_id
      AND organization_id = p_org_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Integration not found or does not belong to organization';
    END IF;

    v_secret_name := 'integration:' || p_integration_id::text;

    IF v_secret_id IS NULL THEN
        -- Cria novo segredo no Vault e armazena o ID
        v_secret_id := vault.create_secret(
            p_secret::text,
            v_secret_name,
            'Integration credentials – org ' || p_org_id::text
        );

        -- Associa o segredo à integração
        UPDATE public.integrations
        SET secret_id  = v_secret_id,
            updated_at = now()
        WHERE id              = p_integration_id
          AND organization_id = p_org_id;
    ELSE
        -- Atualiza segredo existente no Vault
        PERFORM vault.update_secret(
            v_secret_id,
            p_secret::text,
            v_secret_name
        );
    END IF;

    RETURN v_secret_id;
END;
$$;

-- =========================================================
-- 4. get_integration_secret(p_integration_id, p_org_id)
--    Requer permissão manage_integrations.
--    Lê e retorna o segredo decriptado do Vault como jsonb.
--    Retorna NULL se a integração não tiver segredo cadastrado.
-- =========================================================
CREATE OR REPLACE FUNCTION public.get_integration_secret(
    p_integration_id uuid,
    p_org_id         uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
    v_secret_id     uuid;
    v_decrypted     text;
BEGIN
    -- RBAC: somente gerenciadores de integrações podem ver segredos
    IF NOT public.has_permission(p_org_id, 'manage_integrations') THEN
        RAISE EXCEPTION 'Permission denied: manage_integrations required';
    END IF;

    -- Busca secret_id (valida tenant)
    SELECT secret_id INTO v_secret_id
    FROM public.integrations
    WHERE id              = p_integration_id
      AND organization_id = p_org_id
      AND deleted_at IS NULL;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Integration not found or does not belong to organization';
    END IF;

    IF v_secret_id IS NULL THEN
        RETURN NULL;
    END IF;

    -- Lê o segredo decriptado do Vault
    SELECT decrypted_secret INTO v_decrypted
    FROM vault.decrypted_secrets
    WHERE id = v_secret_id;

    IF v_decrypted IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN v_decrypted::jsonb;
END;
$$;
