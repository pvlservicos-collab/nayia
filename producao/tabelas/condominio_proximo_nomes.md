# condominio_proximo_nomes  (view, ~0 linhas)

## colunas
id  integer
norma  text

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
 SELECT DISTINCT p.id,
    n.norma
   FROM condominio_proximo p
     CROSS JOIN LATERAL ( SELECT lower(unaccent(p.nome)) AS norma
        UNION
         SELECT lower(unaccent(c.nome)) AS lower
           FROM condominios c
          WHERE c.id = p.condo_id
        UNION
         SELECT lower(unaccent(i.condominio_nome)) AS lower
           FROM imoveis i
          WHERE i.condo_id = p.condo_id AND p.condo_id IS NOT NULL AND COALESCE(i.condominio_nome, ''::text) <> ''::text) n
  WHERE COALESCE(n.norma, ''::text) <> ''::text;
