-- File: 020_fix_is_org_member_bomba.sql
-- 1. Garante que `auth.uid()` é resolvido corretamente mesmo quando `search_path=public`.
-- 2. Evita recursão no RLS.

-- Restaura o dono para o usuário normal para garantir execução segura, mas usando SECURITY DEFINER
ALTER FUNCTION public.is_org_member(uuid) OWNER TO postgres;

CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
-- IMPORTANTE: "auth" precisa estar no search_path para o Supabase resolver auth.uid()
SET search_path = public, auth
AS $$
DECLARE
  current_user_id uuid;
  is_admin boolean;
  is_member boolean;
BEGIN
  -- Obter usuário
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- Checar admin
  SELECT is_superadmin INTO is_admin
  FROM public.profiles
  WHERE id = current_user_id;
  
  IF is_admin = true THEN
    RETURN true;
  END IF;

  -- Checar membro ativamente ignorando políticas RLS recursivas porque é SECURITY DEFINER rodando como postgres
  SELECT EXISTS (
    SELECT 1
    FROM public.organization_members
    WHERE organization_id = org_id
      AND user_id = current_user_id
      AND (status = 'active' OR status = 'invited') 
      AND (deleted_at IS NULL)
  ) INTO is_member;
  
  RETURN is_member;
END;
$$;
