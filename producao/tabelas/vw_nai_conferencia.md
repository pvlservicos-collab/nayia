# vw_nai_conferencia  (view, ~0 linhas)

## colunas
turno_id  bigint
quando  timestamp with time zone
telefone  text
agiram  bigint
esteira  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT turno_id,
    min(criado_em) AS quando,
    ( SELECT k.telefone
           FROM nai_turno t
             JOIN nai_contato k ON k.id = t.contato_id
          WHERE t.id = c.turno_id) AS telefone,
    count(*) FILTER (WHERE resultado <> 'passou'::text) AS agiram,
    string_agg(((((ordem || '. '::text) || etapa) || ' -> '::text) || resultado) || COALESCE((' ('::text || detalhe) || ')'::text, ''::text), '
'::text ORDER BY ordem) AS esteira
   FROM nai_conferencia c
  GROUP BY turno_id;
