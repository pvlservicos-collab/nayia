CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 301: o n8n ("Liberar saída") só entrega o que é da Nay; a entrega manual é do enviador_manual.py
  -- 550: e só enquanto a parte for dele -- sem turno é a agenda (agenda_de); com turno é a entrada da Parceria.
  -- A guarda vem ANTES de chamar: a liberação marca as linhas 'enviando', e linha marcada que ninguém manda se perde.
  IF (p_turno IS NULL AND coalesce(nullif(btrim(nai_cfg('agenda_de', 'n8n')), ''), 'n8n') <> 'n8n')
     OR (p_turno IS NOT NULL AND coalesce(nullif(btrim(nai_cfg('entrada', 'n8n')), ''), 'n8n') = 'python') THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.nai_liberar_saida(p_turno, false);
END
$function$;
