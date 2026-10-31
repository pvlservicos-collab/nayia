CREATE OR REPLACE FUNCTION public.captacao_relatorio_da_vez(p_quem text DEFAULT 'n8n'::text)
 RETURNS TABLE(phone text, message text, "delayMessage" integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- o relatório marca o dia ao sair (_relatorio_dia): quem não é o dono nem chega a chamar
  IF coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'rotinas_de')), ''), 'n8n') <> p_quem THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM captacao_relatorio_da_vez_rodar();
END
$function$;
