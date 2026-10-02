# nai_treino_pool  (view, ~0 linhas)

## colunas
turno_id  bigint
contato_id  bigint
papel  text
criado_em  timestamp with time zone
ele_disse  text
ferramentas  text[]
nome_whatsapp  text
nome_completo  text
telefone  text
ela_respondeu  text
fotos  bigint

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_treino_montar_ciclo

## definição da view
 SELECT t.id AS turno_id,
    t.contato_id,
    t.papel,
    t.criado_em,
    t.texto AS ele_disse,
    t.ferramentas,
    c.nome_whatsapp,
    c.nome_completo,
    c.telefone,
    ( SELECT string_agg(x.texto, '
---
'::text ORDER BY x.ordem, x.id) AS string_agg
           FROM nai_saida x
          WHERE x.turno_id = t.id AND x.tipo = 'texto'::text) AS ela_respondeu,
    ( SELECT count(*) AS count
           FROM nai_saida x
          WHERE x.turno_id = t.id AND x.tipo = 'imagem'::text) AS fotos
   FROM nai_turno t
     JOIN nai_contato c ON c.id = t.contato_id
  WHERE t.papel = 'corretor'::text AND btrim(COALESCE(t.texto, ''::text)) <> ''::text AND (EXISTS ( SELECT 1
           FROM nai_saida x
          WHERE x.turno_id = t.id)) AND NOT (EXISTS ( SELECT 1
           FROM nai_treino_caso k
          WHERE k.turno_origem = t.id)) AND c.chave IS DISTINCT FROM nai_chave(nai_cfg('treino_espelho'::text, ''::text)) AND NOT (EXISTS ( SELECT 1
           FROM nai_treino_caso k2
          WHERE k2.turno_simulado = t.id));
