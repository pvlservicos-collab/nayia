# vw_proprietarios_site  (view, ~0 linhas)

## colunas
id  integer
nome  text
cpf  text
email  text
telefone  text
etapa  text
especialista  text
criado_em  date
imoveis  bigint
codigos  text
vencimento  date

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT id,
    nome,
    cpf,
    email,
    telefone,
    COALESCE(NULLIF(btrim(status), ''::text), 'Sem etapa'::text) AS etapa,
    NULLIF(btrim(corretor), ''::text) AS especialista,
    criado_em,
    ( SELECT count(DISTINCT x.codigo) AS count
           FROM ( SELECT ip.codigo::text AS codigo
                   FROM imovel_privado ip
                  WHERE ip.proprietario_id = pe.id
                UNION
                 SELECT pai.codigo
                   FROM proprietarios_admin_imoveis pai
                  WHERE pai.proprietario_id = pe.id) x) AS imoveis,
    ( SELECT string_agg(x.codigo, ', '::text ORDER BY x.codigo) AS string_agg
           FROM ( SELECT ip.codigo::text AS codigo
                   FROM imovel_privado ip
                  WHERE ip.proprietario_id = pe.id
                UNION
                 SELECT pai.codigo
                   FROM proprietarios_admin_imoveis pai
                  WHERE pai.proprietario_id = pe.id) x) AS codigos,
    ( SELECT min(c.vencimento) AS min
           FROM contratos_locacao c
          WHERE c.proprietario_id_admin = pe.id AND c.vencimento IS NOT NULL) AS vencimento
   FROM proprietarios_export pe
  WHERE COALESCE(corretor, ''::text) !~* 'parceir'::text AND NOT site_nao_e_dono(nome);
