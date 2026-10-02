# vw_condominio_som  (view, ~0 linhas)

## colunas
nome  text
nucleo  text
chave  text
codigos  integer[]

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_core: SELECT
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
nai_imoveis_pedidos, nai_imovel_pelo_condominio

## definição da view
 SELECT nai_condominio_ok(condominio_nome) AS nome,
    nai_condominio_nucleo(nai_condominio_ok(condominio_nome)) AS nucleo,
    nai_chave_som(nai_condominio_nucleo(nai_condominio_ok(condominio_nome))) AS chave,
    array_agg(DISTINCT codigo) AS codigos
   FROM imoveis i
  WHERE nai_condominio_ok(condominio_nome) IS NOT NULL AND nai_condominio_ok(condominio_nome) !~ '/'::text AND NOT (lower(unaccent(nai_condominio_ok(condominio_nome))) IN ( SELECT lower(unaccent(x.tipo)) AS lower
           FROM imoveis x
          WHERE x.tipo IS NOT NULL)) AND nay_esta_no_mercado(disponivel, bloqueado, publicado_no_site) AND NOT COALESCE(e_parceiro, false)
  GROUP BY (nai_condominio_ok(condominio_nome)), (nai_condominio_nucleo(nai_condominio_ok(condominio_nome))), (nai_chave_som(nai_condominio_nucleo(nai_condominio_ok(condominio_nome))));
