# vw_captacao_outros_imoveis  (view, ~0 linhas)
O que a campanha CAPTOU: imoveis que o proprietario disse ter alem do cadastrado.

## colunas
id  bigint
lead_id  bigint
nome  text
telefone  text
descricao  text
negocio  text
criado_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT e.id,
    e.lead_id,
    l.nome,
    l.telefone,
    e.descricao,
    e.negocio,
    e.criado_em
   FROM captacao_imoveis_extra e
     JOIN captacao_leads l ON l.id = e.lead_id
  ORDER BY e.id DESC;
