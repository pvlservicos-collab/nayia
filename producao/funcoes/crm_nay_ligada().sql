CREATE OR REPLACE FUNCTION public.crm_nay_ligada()
 RETURNS TABLE(ligada boolean, motivo text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  -- a mesma leitura da caixa de saída (nai_liberar_saida): pausada é tudo que
  -- não for exatamente 'nao' -- na dúvida, vermelho
  SELECT x.modo = 'todos' AND x.pausa = 'nao',
         CASE WHEN x.pausa <> 'nao' THEN 'A Nay está pausada (PARAR ATENDIMENTO)'
              WHEN x.modo = 'teste' THEN 'A Nay está só nos testes'
              WHEN x.modo <> 'todos' THEN 'A Nay está desligada'
              ELSE NULL END
    FROM (SELECT nai_cfg('modo', 'desligado') AS modo, nai_cfg('pausada', 'sim') AS pausa) x
$function$;
