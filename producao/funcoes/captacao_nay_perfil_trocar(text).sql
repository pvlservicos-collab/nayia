CREATE OR REPLACE FUNCTION public.captacao_nay_perfil_trocar(p_nome text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_antes text := (SELECT valor FROM captacao_config WHERE chave = 'nay_perfil_ativo');
BEGIN
  IF NOT EXISTS (SELECT 1 FROM captacao_nay_perfil WHERE nome = p_nome) THEN
    RETURN 'não existe o perfil ' || coalesce(p_nome, '(vazio)') || '. Os que existem: ' ||
           (SELECT string_agg(nome, ', ' ORDER BY nome) FROM captacao_nay_perfil);
  END IF;
  UPDATE captacao_config SET valor = p_nome WHERE chave = 'nay_perfil_ativo';
  RETURN 'perfil ativo: ' || p_nome || ' (antes: ' || coalesce(v_antes, 'nenhum') ||
         '). Quem já foi chamado segue com a Nay com que foi chamado.';
END $function$;
