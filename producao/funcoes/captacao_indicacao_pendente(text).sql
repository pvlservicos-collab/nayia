CREATE OR REPLACE FUNCTION public.captacao_indicacao_pendente(p_telefone text)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT CASE WHEN EXISTS (
           SELECT 1 FROM captacao_mensagens m
            WHERE nay_fone_chave(m.telefone) = nay_fone_chave(p_telefone) AND m.direcao = 'enviada'
              AND m.texto ~* '\mindic(ar|a|ou|ando|a[cç][aã]o)\M' AND m.texto ~ '\?'
              -- desde o último disparo (campanha nova pergunta de novo). Pela ORDEM das mensagens, não pela
              -- hora: duas gravadas na mesma transação têm a mesma hora.
              AND m.id > coalesce((SELECT max(d.id) FROM captacao_mensagens d
                                    WHERE nay_fone_chave(d.telefone) = nay_fone_chave(p_telefone)
                                      AND d.direcao = 'enviada' AND d.origem = 'disparo'), 0))
         THEN NULL
         ELSE 'Para finalizar: conhece alguém que esteja vendendo um imóvel e que possa nos indicar?' END;
$function$;
