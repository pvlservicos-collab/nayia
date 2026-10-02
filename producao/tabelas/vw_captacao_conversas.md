# vw_captacao_conversas  (view, ~0 linhas)
Ultimas conversas da captacao, com o que ele disse e o que ela respondeu.

## colunas
id  bigint
nome  text
codigo  text
condominio  text
status  text
etapa  text
situacao  text
situacao_por  text
contrato_ate  text
valor_locacao_pedido  text
tem_outro_imovel  boolean
opt_out  boolean
tentativas  integer
com_o_tel  boolean
ultimo_envio_em  timestamp with time zone
respondeu_em  timestamp with time zone
ele_disse  text
ela_respondeu  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT id,
    nome,
    codigo,
    condominio,
    status,
    etapa,
    situacao,
    COALESCE(situacao_por,
        CASE
            WHEN situacao IS NOT NULL THEN 'ia'::text
            ELSE NULL::text
        END) AS situacao_por,
    contrato_ate,
    valor_locacao_pedido,
    tem_outro_imovel,
    opt_out,
    tentativas,
    humano_assumiu_em IS NOT NULL AS com_o_tel,
    ultimo_envio_em,
    respondeu_em,
    ( SELECT m.texto
           FROM captacao_mensagens m
          WHERE m.lead_id = l.id AND m.direcao = 'recebida'::text AND NULLIF(btrim(m.texto), ''::text) IS NOT NULL
          ORDER BY m.id DESC
         LIMIT 1) AS ele_disse,
    ( SELECT m.texto
           FROM captacao_mensagens m
          WHERE m.lead_id = l.id AND m.direcao = 'enviada'::text AND NULLIF(btrim(m.texto), ''::text) IS NOT NULL
          ORDER BY m.id DESC
         LIMIT 1) AS ela_respondeu
   FROM captacao_leads l
  WHERE ultimo_envio_em IS NOT NULL
  ORDER BY (COALESCE(respondeu_em, ultimo_envio_em)) DESC;
