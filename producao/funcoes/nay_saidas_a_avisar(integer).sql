CREATE OR REPLACE FUNCTION public.nay_saidas_a_avisar(p_horas integer DEFAULT 6)
 RETURNS TABLE(codigo text, motivo text)
 LANGUAGE sql
 STABLE
AS $function$
  SELECT a.codigo, coalesce(a.motivo, 'alugado')
    FROM aviso_de_saida a
    JOIN imoveis i ON i.codigo::text = a.codigo
   WHERE a.avisado_em IS NULL
     AND NOT coalesce(i.disponivel, true)   -- voltou atrás: não avisa
     -- 334: com a pergunta ligada, só sai o que o Tel respondeu SIM (o prazo conta do SIM dele);
     -- desligada, vale a regra de antes (o prazo conta da saída), menos para o que ele já respondeu NÃO
     AND CASE WHEN lower(coalesce(nai_cfg('aviso_saida_pergunta', 'sim'), 'sim')) = 'sim'
              THEN EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q
                            WHERE q.codigo = a.codigo AND q.marcado_em = a.marcado_em
                              AND q.resposta = 'sim'
                              AND q.respondido_em > now() - make_interval(hours => p_horas))
              ELSE a.marcado_em > now() - make_interval(hours => p_horas)
                   AND NOT EXISTS (SELECT 1 FROM aviso_de_saida_pergunta q
                                    WHERE q.codigo = a.codigo AND q.marcado_em = a.marcado_em AND q.resposta = 'nao') END
   ORDER BY a.marcado_em;
$function$;
