# vw_nai_ultimos_turnos  (view, ~0 linhas)
As últimas 200 respostas da NAI, com a esteira que agiu (Tel, 15/09).

## colunas
turno  bigint
quando  timestamp with time zone
papel  text
imovel  integer
ele_disse  text
ela_respondeu  text
fotos  bigint
barradas  bigint
conferencias_que_agiram  text
ferramentas  text[]

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT id AS turno,
    criado_em AS quando,
    papel,
    codigo AS imovel,
    "left"(COALESCE(texto, ''::text), 120) AS ele_disse,
    ( SELECT "left"(string_agg(s.texto, ' | '::text ORDER BY s.ordem), 200) AS "left"
           FROM nai_saida s
          WHERE s.turno_id = t.id AND s.tipo = 'texto'::text AND s.estado <> 'bloqueado'::text) AS ela_respondeu,
    ( SELECT count(*) AS count
           FROM nai_saida s
          WHERE s.turno_id = t.id AND s.tipo = 'imagem'::text) AS fotos,
    ( SELECT count(*) AS count
           FROM nai_saida s
          WHERE s.turno_id = t.id AND s.estado = 'bloqueado'::text) AS barradas,
    ( SELECT string_agg(c.etapa, ', '::text ORDER BY c.ordem) AS string_agg
           FROM nai_conferencia c
          WHERE c.turno_id = t.id AND c.resultado <> 'passou'::text) AS conferencias_que_agiram,
    COALESCE(ferramentas, '{}'::text[]) AS ferramentas
   FROM nai_turno t
  ORDER BY id DESC
 LIMIT 200;
