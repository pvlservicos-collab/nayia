# vw_captacao_envios  (view, ~0 linhas)
Tudo que saiu pelo numero da captacao, dizendo se foi ela ou alguem digitando. Tel, 15/09.

## colunas
id  bigint
quando  timestamp with time zone
para_quem  text
codigo  text
condominio  text
quem_mandou  text
texto  text
status  text

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT c.id,
    c.criada_em AS quando,
    COALESCE(l.nome, nai_fone_fmt(c.telefone)) AS para_quem,
    l.codigo,
    l.condominio,
        CASE c.origem
            WHEN 'disparo'::text THEN 'a Nay (1ª mensagem)'::text
            WHEN 'resposta'::text THEN 'a Nay (resposta)'::text
            WHEN 'humano'::text THEN 'alguém digitou'::text
            ELSE COALESCE(c.origem, '-'::text)
        END AS quem_mandou,
        CASE
            WHEN COALESCE(btrim(c.texto), ''::text) = ''::text THEN '[foto ou mídia]'::text
            ELSE "left"(c.texto, 160)
        END AS texto,
    c.status
   FROM captacao_mensagens c
     LEFT JOIN captacao_leads l ON l.id = c.lead_id
  WHERE c.direcao = 'enviada'::text
  ORDER BY c.id DESC;
