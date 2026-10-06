CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE sql
AS $function$
  -- 301: o n8n ("Liberar saída") só entrega o que é da Nay; a entrega manual é do enviador_manual.py
  SELECT * FROM public.nai_liberar_saida(p_turno, false);
$function$;
