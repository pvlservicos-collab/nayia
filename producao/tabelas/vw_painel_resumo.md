# vw_painel_resumo  (view, ~0 linhas)

## colunas
periodo  text
desde  date
corretores  bigint
mensagens_recebidas  bigint
corretores_falaram_de_visita  bigint
visitas_pedidas  bigint
visitas_confirmadas  bigint
visitas_realizadas  bigint
captacao_responderam  bigint
captacao_disparos  bigint
captacao_com_o_tel  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH p(periodo, desde) AS (
         VALUES ('hoje'::text,(now() AT TIME ZONE 'America/Manaus'::text)::date), ('7d'::text,(now() AT TIME ZONE 'America/Manaus'::text)::date - 6), ('30d'::text,(now() AT TIME ZONE 'America/Manaus'::text)::date - 29)
        )
 SELECT periodo,
    desde,
    ( SELECT count(DISTINCT nay_fone_chave(m.telefone)) AS count
           FROM mensagens m
          WHERE m.direcao = 'recebida'::text AND (m.criada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS corretores,
    ( SELECT count(*) AS count
           FROM mensagens m
          WHERE m.direcao = 'recebida'::text AND (m.criada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS mensagens_recebidas,
    ( SELECT count(DISTINCT nay_fone_chave(m.telefone)) AS count
           FROM mensagens m
          WHERE m.direcao = 'recebida'::text AND nay_pede_visita(m.texto) AND (m.criada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS corretores_falaram_de_visita,
    ( SELECT count(*) AS count
           FROM nai_visita v
          WHERE (v.criado_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS visitas_pedidas,
    ( SELECT count(*) AS count
           FROM nai_visita v
          WHERE v.confirmada_em IS NOT NULL AND (v.confirmada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS visitas_confirmadas,
    ( SELECT count(*) AS count
           FROM nai_visita v
          WHERE (v.estado = ANY (ARRAY['realizada'::text, 'encerrada'::text])) AND v.confirmada_em IS NOT NULL AND (v.confirmada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS visitas_realizadas,
    ( SELECT count(*) AS count
           FROM captacao_leads l
          WHERE l.respondeu_em IS NOT NULL AND (l.respondeu_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS captacao_responderam,
    ( SELECT count(*) AS count
           FROM captacao_mensagens c
          WHERE c.direcao = 'enviada'::text AND c.origem = 'disparo'::text AND (c.criada_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS captacao_disparos,
    ( SELECT count(*) AS count
           FROM captacao_leads l
          WHERE l.humano_assumiu_em IS NOT NULL AND (l.humano_assumiu_em AT TIME ZONE 'America/Manaus'::text)::date >= p.desde) AS captacao_com_o_tel
   FROM p;
