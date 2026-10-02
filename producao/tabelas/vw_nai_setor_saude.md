# vw_nai_setor_saude  (view, ~0 linhas)
Semaforo por setor nos ultimos 7 dias: onde esta doendo (Tel, 19/09).

## colunas
setor  text
ordem  integer
titulo  text
descricao  text
passagens  bigint
erros  bigint
paradas  bigint
correcoes  bigint
pct_problema  numeric
ultimo_problema  timestamp with time zone
semaforo  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH base AS (
         SELECT nai_evento.setor,
            nai_evento.resultado,
            nai_evento.criado_em
           FROM nai_evento
        UNION ALL
         SELECT 'conferencia'::text,
                CASE nai_conferencia.resultado
                    WHEN 'passou'::text THEN 'ok'::text
                    ELSE nai_conferencia.resultado
                END AS resultado,
            nai_conferencia.criado_em
           FROM nai_conferencia
        UNION ALL
         SELECT 'saida'::text,
                CASE nai_saida.estado
                    WHEN 'bloqueado'::text THEN 'parou'::text
                    WHEN 'erro'::text THEN 'erro'::text
                    ELSE 'ok'::text
                END AS "case",
            COALESCE(nai_saida.enviado_em, nai_saida.criado_em) AS "coalesce"
           FROM nai_saida
        )
 SELECT s.setor,
    s.ordem,
    s.titulo,
    s.descricao,
    count(b.*) AS passagens,
    count(b.*) FILTER (WHERE b.resultado = 'erro'::text) AS erros,
    count(b.*) FILTER (WHERE b.resultado = 'parou'::text) AS paradas,
    count(b.*) FILTER (WHERE b.resultado = ANY (ARRAY['mudou'::text, 'cortou'::text])) AS correcoes,
    round(100.0 * count(b.*) FILTER (WHERE b.resultado <> 'ok'::text)::numeric / GREATEST(count(b.*), 1::bigint)::numeric, 1) AS pct_problema,
    max(b.criado_em) FILTER (WHERE b.resultado <> 'ok'::text) AS ultimo_problema,
        CASE
            WHEN count(b.*) = 0 THEN 'cinza'::text
            WHEN count(b.*) FILTER (WHERE b.resultado = 'erro'::text) > 0 THEN 'vermelho'::text
            WHEN (100.0 * count(b.*) FILTER (WHERE b.resultado <> 'ok'::text)::numeric / GREATEST(count(b.*), 1::bigint)::numeric) > 10::numeric THEN 'amarelo'::text
            ELSE 'verde'::text
        END AS semaforo
   FROM nai_setor s
     LEFT JOIN base b ON b.setor = s.setor AND b.criado_em > (now() - '7 days'::interval)
  GROUP BY s.setor, s.ordem, s.titulo, s.descricao
  ORDER BY s.ordem;
