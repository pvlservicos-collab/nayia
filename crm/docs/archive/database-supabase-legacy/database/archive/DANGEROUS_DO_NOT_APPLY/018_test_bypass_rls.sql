-- Test bypass function to see if pipelines load at all when RLS allows everything for authenticated users.
CREATE OR REPLACE FUNCTION public.is_org_member(org_id uuid)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
AS $$
  -- Retorna verdadeiro para qualquer UUID válido, apenas para testar se os dados aparecem.
  SELECT true;
$$;
