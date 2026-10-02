# vw_colagens  (view, ~0 linhas)

## colunas
codigo  integer
tipo  text
condominio  text
bairro  text
valor_aluguel  numeric
valor_venda  numeric
fotos  integer
url  text
bytes  integer
gerada_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT i.codigo,
    i.tipo,
    i.condominio_nome AS condominio,
    i.bairro,
    i.valor_aluguel,
    i.valor_venda,
    (( SELECT count(*) AS count
           FROM imovel_fotos f
          WHERE f.codigo = i.codigo))::integer AS fotos,
    c.url,
    c.bytes,
    c.gerada_em
   FROM imoveis i
     LEFT JOIN imovel_colagem c ON c.codigo = i.codigo
  WHERE COALESCE(i.disponivel, true) AND NOT COALESCE(i.bloqueado, false) AND (( SELECT count(*) AS count
           FROM imovel_fotos f
          WHERE f.codigo = i.codigo)) >= 4;
