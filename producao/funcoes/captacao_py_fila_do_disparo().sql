CREATE OR REPLACE FUNCTION public.captacao_py_fila_do_disparo()
 RETURNS SETOF bigint
 LANGUAGE sql
 STABLE
AS $function$
  SELECT l.id
    FROM captacao_leads l
   WHERE l.tentativas < 4 AND NOT l.opt_out AND l.humano_assumiu_em IS NULL
     AND coalesce(btrim(l.telefone), '') <> '' AND coalesce(btrim(l.nome), '') <> ''
     AND captacao_fora_da_campanha(l.id) IS NULL
     AND (
          -- quem nunca recebeu nada nosso por este número
          (l.status IN ('novo', 'erro')
           AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                            WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada' AND m.status <> 'Falhou'))
          -- 323: a retomada pelo oficial -- recebeu pela Z-API, nunca respondeu, ainda sem o modelo oficial
          OR (l.status = 'enviado'
              AND EXISTS (SELECT 1 FROM captacao_retomada_oficial r WHERE r.lead_id = l.id)
              AND l.respondeu_em IS NULL
              AND NOT EXISTS (SELECT 1 FROM captacao_mensagens m
                               WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'recebida')
              AND NOT EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id))
         )
     AND NOT EXISTS (SELECT 1 FROM captacao_leads o
                      WHERE o.id <> l.id AND o.proprietario_id IS NOT NULL AND o.proprietario_id = l.proprietario_id
                        AND (o.ultimo_envio_em IS NOT NULL OR o.respondeu_em IS NOT NULL))
     AND NOT EXISTS (SELECT 1 FROM captacao_nao_disparar n WHERE n.telefone_chave = l.telefone_chave)
     -- 352: quem falou conosco por qualquer número nos últimos 60 dias não recebe disparo; corretor não é proprietário
     AND NOT nay_falou_conosco(l.telefone_chave, 60)
     AND NOT nay_e_corretor_chave(l.telefone_chave)
   ORDER BY (l.status = 'enviado'), l.id;
$function$;
