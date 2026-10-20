# condominio_proximo_lista  (view, ~0 linhas)

## colunas
de_id  integer
de_nome  text
de_recente  boolean
ordem  bigint
para_id  integer
para_nome  text
para_recente  boolean
mesmo_bairro  boolean

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
olx_cliente_buscar

## definição da view
 SELECT p.id AS de_id,
    p.nome AS de_nome,
    p.recente AS de_recente,
    l.ordem,
    q.id AS para_id,
    q.nome AS para_nome,
    q.recente AS para_recente,
    string_to_array(p.bairro, ', '::text) && string_to_array(q.bairro, ', '::text) AS mesmo_bairro
   FROM condominio_proximo p
     CROSS JOIN LATERAL unnest(p.proximos) WITH ORDINALITY l(nome, ordem)
     JOIN condominio_proximo q ON q.nome = l.nome;
