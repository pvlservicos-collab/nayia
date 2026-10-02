# vw_captacao_thread_leads  (view, ~0 linhas)
Conversas da captacao que tiveram resposta, com a triagem e o rascunho ao lado. So leitura.

## colunas
id  bigint
nome  text
tratamento  text
telefone  text
imovel  text
situacao  text
status  text
opt_out  boolean
com_o_tel  boolean
prioridade  text
resumo  text
motivo  text
mensagem  text
ordem  integer
qtd_mensagens  bigint
ultima_em  timestamp with time zone

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT l.id,
    l.nome,
    COALESCE(l.tratamento, ''::text) AS tratamento,
    l.telefone,
    COALESCE(l.condominio, l.imovel_desc, l.bairro, ''::text) AS imovel,
    l.situacao,
    l.status,
    l.opt_out,
    l.humano_assumiu_em IS NOT NULL AS com_o_tel,
    r.prioridade,
    r.resumo,
    r.motivo,
    r.mensagem,
    COALESCE(r.ordem, 0) AS ordem,
    ( SELECT count(*) AS count
           FROM captacao_mensagens m
          WHERE m.lead_id = l.id) AS qtd_mensagens,
    ( SELECT max(m.criada_em) AS max
           FROM captacao_mensagens m
          WHERE m.lead_id = l.id) AS ultima_em
   FROM captacao_leads l
     LEFT JOIN captacao_revisao r ON r.lead_id = l.id
  WHERE (EXISTS ( SELECT 1
           FROM captacao_mensagens m
          WHERE m.lead_id = l.id AND m.direcao = 'recebida'::text));
