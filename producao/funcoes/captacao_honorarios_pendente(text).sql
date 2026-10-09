CREATE OR REPLACE FUNCTION public.captacao_honorarios_pendente(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN EXISTS (
           SELECT 1 FROM captacao_mensagens m
            WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_telefone) AND m.direcao = 'enviada'
              AND m.texto ~* 'honor[aá]rio|corretagem' AND m.texto ~ '\?'
              AND m.id > coalesce((SELECT max(d.id) FROM captacao_mensagens d
                                    WHERE nay_fone_chave(d.telefone) = nay_fone_chave(p_telefone)
                                      AND d.direcao = 'enviada' AND d.origem = 'disparo'), 0))
         THEN NULL
         ELSE captacao_honorarios_frase(p_telefone) END;
$function$;
