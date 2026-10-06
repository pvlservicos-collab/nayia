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
 WITH dono_do_imovel AS (
         SELECT i.codigo,
            COALESCE(ip.proprietario_id, i.proprietario_id) AS proprietario_id
           FROM imoveis i
             LEFT JOIN imovel_privado ip ON ip.codigo = i.codigo
        ), do_dono AS (
         SELECT d.proprietario_id,
            count(*) AS imoveis,
            string_agg(d.codigo::text, ', '::text ORDER BY d.codigo) AS codigos
           FROM dono_do_imovel d
          WHERE d.proprietario_id IS NOT NULL
          GROUP BY d.proprietario_id
        )
 SELECT p.id,
    COALESCE(NULLIF(btrim(p.nome), ''::text), NULLIF(btrim(pe.nome), ''::text)) AS nome,
    COALESCE(NULLIF(btrim(p.documento), ''::text), pe.cpf) AS cpf,
    COALESCE(NULLIF(btrim(p.email), ''::text), pe.email) AS email,
    COALESCE(NULLIF(btrim(p.telefone), ''::text), pe.telefone) AS telefone,
    COALESCE(NULLIF(btrim(pe.status), ''::text), 'Sem etapa'::text) AS etapa,
    NULLIF(btrim(pe.corretor), ''::text) AS especialista,
    pe.criado_em,
    COALESCE(dd.imoveis, 0::bigint) AS imoveis,
    dd.codigos,
    ( SELECT min(c.vencimento) AS min
           FROM contratos_locacao c
          WHERE c.proprietario_id_admin = p.id AND c.vencimento IS NOT NULL) AS vencimento
   FROM proprietarios p
     LEFT JOIN proprietarios_export pe ON pe.id = p.id
     LEFT JOIN do_dono dd ON dd.proprietario_id = p.id
  WHERE COALESCE(pe.corretor, ''::text) !~* 'parceir'::text AND NOT site_nao_e_dono(COALESCE(NULLIF(btrim(p.nome), ''::text), pe.nome));
