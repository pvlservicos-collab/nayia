# vw_captacao_resumo  (view, ~0 linhas)
O funil inteiro da campanha de captacao. Painel, Tel 15/09.

## colunas
leads  bigint
na_fila  bigint
falados  bigint
responderam  bigint
disponiveis  bigint
alugados  bigint
vendidos  bigint
com_outro_imovel  bigint
pediram_para_sair  bigint
com_o_tel  bigint
concluidos  bigint
segundos_ate_responder  integer

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT count(*) AS leads,
    count(*) FILTER (WHERE status = 'novo'::text) AS na_fila,
    count(*) FILTER (WHERE ultimo_envio_em IS NOT NULL) AS falados,
    count(*) FILTER (WHERE respondeu_em IS NOT NULL) AS responderam,
    count(*) FILTER (WHERE situacao = 'disponivel'::text) AS disponiveis,
    count(*) FILTER (WHERE situacao = 'alugado'::text) AS alugados,
    count(*) FILTER (WHERE situacao = 'vendido'::text) AS vendidos,
    count(*) FILTER (WHERE tem_outro_imovel) AS com_outro_imovel,
    count(*) FILTER (WHERE opt_out) AS pediram_para_sair,
    count(*) FILTER (WHERE humano_assumiu_em IS NOT NULL) AS com_o_tel,
    count(*) FILTER (WHERE status = 'concluido'::text) AS concluidos,
    round(avg(EXTRACT(epoch FROM respondeu_em - ultimo_envio_em)) FILTER (WHERE respondeu_em > ultimo_envio_em))::integer AS segundos_ate_responder
   FROM captacao_leads;
