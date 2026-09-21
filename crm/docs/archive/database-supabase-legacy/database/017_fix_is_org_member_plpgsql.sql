CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  current_user_id uuid;
  is_admin boolean;
  is_member boolean;
BEGIN
  -- 1. Obter o ID do usuario logado com seguranca
  current_user_id := auth.uid();
  
  IF current_user_id IS NULL THEN
    RETURN false;
  END IF;

  -- 2. Verificar se o usuario atual eh superadmin (master)
  SELECT is_superadmin INTO is_admin
  FROM public.profiles
  WHERE id = current_user_id;
  
  IF is_admin = true THEN
    RETURN true;
  END IF;

  -- 3. Verificar se o usuario eh membro ativo ou convidado da organizacao especificada
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
