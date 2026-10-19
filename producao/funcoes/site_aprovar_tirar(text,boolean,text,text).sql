CREATE OR REPLACE FUNCTION public.site_aprovar_tirar(p_chave text, p_tirar boolean DEFAULT true, p_motivo text DEFAULT NULL::text, p_quem text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  IF p_chave !~ '^(ficha|bot|imovel):[0-9]+$' THEN
    RETURN jsonb_build_object('erro', 'chave inválida');
  END IF;
  IF p_tirar THEN
    INSERT INTO privado.imovel_aprovar_fora (chave, motivo, quem) VALUES (p_chave, left(p_motivo, 300), left(p_quem, 60))
    ON CONFLICT (chave) DO UPDATE SET motivo = excluded.motivo, quem = excluded.quem, criado_em = now();
  ELSE
    DELETE FROM privado.imovel_aprovar_fora WHERE chave = p_chave;
  END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;
