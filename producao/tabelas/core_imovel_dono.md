# core_imovel_dono  (view materializada, ~5676 linhas)
nay-core: o dono de cada imóvel e de onde veio (imovel > privado > admin), com telefone repetido entre donos. REFRESH CONCURRENTLY pelo worker (005).

## colunas
codigo  integer
proprietario_id  integer
origem  text
nome  text
telefone_bruto  text
telefone_digitos  text
dois_donos  boolean
tratar_com_outra_pessoa  boolean
mesmo_telefone_em  integer[]
montado_em  timestamp with time zone

## índices
CREATE INDEX core_imovel_dono_telefone ON public.core_imovel_dono USING btree ("right"(telefone_digitos, 8)) WHERE (telefone_digitos IS NOT NULL)
CREATE UNIQUE INDEX core_imovel_dono_codigo ON public.core_imovel_dono USING btree (codigo)

## permissões
nay_core: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 WITH base AS (
         SELECT i.codigo,
            COALESCE(i.proprietario_id, p.proprietario_id) AS proprietario_id,
                CASE
                    WHEN i.proprietario_id IS NOT NULL THEN 'imovel'::text
                    WHEN p.proprietario_id IS NOT NULL THEN 'privado'::text
                    ELSE NULL::text
                END AS origem
           FROM imoveis i
             LEFT JOIN imovel_privado p ON p.codigo = i.codigo
        ), admin AS (
         SELECT a.codigo::integer AS codigo,
            count(DISTINCT a.proprietario_id) AS donos,
            min(pa.nome) AS nome,
            min(pa.telefone) AS telefone
           FROM proprietarios_admin_imoveis a
             JOIN proprietarios_admin pa ON pa.id = a.proprietario_id
          WHERE a.codigo ~ '^\d{1,6}$'::text
          GROUP BY (a.codigo::integer)
        ), dono AS (
         SELECT b.codigo,
            b.proprietario_id,
            COALESCE(b.origem,
                CASE
                    WHEN ad.donos = 1 THEN 'admin'::text
                    ELSE NULL::text
                END) AS origem,
                CASE
                    WHEN b.origem IS NOT NULL THEN pr.nome
                    ELSE ad.nome
                END AS nome,
                CASE
                    WHEN b.origem IS NOT NULL THEN pr.telefone
                    WHEN ad.donos = 1 THEN ad.telefone
                    ELSE NULL::text
                END AS telefone_bruto,
            b.origem IS NULL AND COALESCE(ad.donos, 0::bigint) > 1 AS dois_donos
           FROM base b
             LEFT JOIN proprietarios pr ON pr.id = b.proprietario_id
             LEFT JOIN admin ad ON ad.codigo = b.codigo
        ), com_tel AS (
         SELECT d.codigo,
            d.proprietario_id,
            d.origem,
            d.nome,
            d.telefone_bruto,
            d.dois_donos,
            "substring"(regexp_replace(COALESCE(d.telefone_bruto, ''::text), '[^\d/;,]'::text, ''::text, 'g'::text), '\d{8,13}'::text) AS telefone_digitos
           FROM dono d
        ), repetido AS (
         SELECT a.codigo,
            array_agg(DISTINCT b.codigo ORDER BY b.codigo) AS outros
           FROM com_tel a
             JOIN com_tel b ON "right"(a.telefone_digitos, 8) = "right"(b.telefone_digitos, 8) AND a.codigo <> b.codigo AND a.proprietario_id IS DISTINCT FROM b.proprietario_id
          WHERE a.telefone_digitos IS NOT NULL AND b.telefone_digitos IS NOT NULL
          GROUP BY a.codigo
        )
 SELECT c.codigo,
    c.proprietario_id,
    c.origem,
    c.nome,
    c.telefone_bruto,
    c.telefone_digitos,
    c.dois_donos,
    COALESCE(c.nome, ''::text) ~* '(tratar|falar|contato)\s+com'::text AS tratar_com_outra_pessoa,
    r.outros AS mesmo_telefone_em,
    now() AS montado_em
   FROM com_tel c
     LEFT JOIN repetido r ON r.codigo = c.codigo;
