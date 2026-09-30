CREATE OR REPLACE FUNCTION public.nay_entregas_devidas()
 RETURNS TABLE(telefone text, ids bigint[], codigos text, abertura text)
 LANGUAGE sql
 STABLE
AS $function$
  WITH ok AS (
    SELECT NOT COALESCE((SELECT valor = 'sim' FROM config
                          WHERE chave = 'atendimento_pausado'), true) AS pode
  ), devidas AS (
    SELECT p.*, coalesce(split_part(btrim(c.nome),' ',1), '') AS primeiro_nome
      FROM entrega_pendente p
      JOIN imoveis i ON i.codigo::text = p.codigo
      LEFT JOIN corretores c ON right(regexp_replace(c.telefone,'[^0-9]','','g'),8)
                              = right(regexp_replace(p.telefone,'[^0-9]','','g'),8)
     WHERE p.estado = 'devendo'
       AND (SELECT pode FROM ok)
       AND coalesce(i.disponivel, true)   -- imóvel que saiu não se manda
       AND nay_pode_falar(p.telefone)     -- teto de 1 por dia
       -- Só depois de 3 minutos: se ela conseguir mandar na própria
       -- conversa, o cron não atropela.
       AND p.criado_em < now() - interval '3 minutes'
       -- E NÃO DEPOIS DE 24 HORAS. Dívida sem prazo faz um pedido de
       -- terça chegar no sábado, sem contexto nenhum -- o corretor já
       -- resolveu com o cliente e recebe um card do nada. Achado na
       -- auditoria de 01/09. Passado o prazo, ela não manda; se ele
       -- perguntar de novo, nasce dívida nova.
       AND p.criado_em > now() - interval '24 hours'
  )
  SELECT d.telefone,
         array_agg(d.id ORDER BY d.criado_em),
         string_agg(d.codigo, ',' ORDER BY d.criado_em),
         CASE WHEN min(d.primeiro_nome) <> '' THEN min(d.primeiro_nome) || ', segue '
              ELSE 'segue ' END
         || CASE WHEN count(*) > 1 THEN 'as opções' ELSE 'o imóvel' END
         || ' que fiquei de te enviar 👇'
    FROM devidas d
   GROUP BY d.telefone;
$function$;
