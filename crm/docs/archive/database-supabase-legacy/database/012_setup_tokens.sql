-- =========================================================
-- 012) SETUP TOKENS — Tokens pré-autorizados para onboarding
-- de donos de organização. Cada token só pode ser usado uma vez.
-- =========================================================

CREATE TABLE IF NOT EXISTS public.setup_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    token_hash text NOT NULL UNIQUE,
    org_name text NOT NULL DEFAULT 'Minha Organização',
    org_id uuid REFERENCES public.organizations(id),
    is_used boolean DEFAULT false,
    used_by uuid REFERENCES auth.users(id),
    used_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- RLS: ninguém lê via client (apenas service_role)
ALTER TABLE public.setup_tokens ENABLE ROW LEVEL SECURITY;

-- Sem policies = nenhum acesso via anon/authenticated.
-- Apenas service_role (bypass) pode ler/escrever.
