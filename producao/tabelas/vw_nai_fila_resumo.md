# vw_nai_fila_resumo  (view, ~0 linhas)
Quantos estao na fila, dos dois lados. Painel, Tel 15/09.

## colunas
a_sair  bigint
saindo  bigint
barradas_24h  bigint
chegando  bigint
conversas_com_o_tel  bigint
conversas_liberadas  bigint
mais_velha_segundos  integer

## permissões
nay: DELETE, INSERT, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE
nay_leitura: SELECT
nay_site_nai: SELECT

## funções que escrevem aqui
(nenhuma função; quem escreve é o n8n, o site ou o CRM)

## funções que citam
(nenhuma)

## definição da view
 SELECT ( SELECT count(*) AS count
           FROM nai_saida
          WHERE nai_saida.estado = 'pendente'::text) AS a_sair,
    ( SELECT count(*) AS count
           FROM nai_saida
          WHERE nai_saida.estado = 'enviando'::text) AS saindo,
    ( SELECT count(*) AS count
           FROM nai_saida
          WHERE nai_saida.estado = 'bloqueado'::text AND nai_saida.criado_em > (now() - '24:00:00'::interval)) AS barradas_24h,
    ( SELECT count(*) AS count
           FROM mensagens
          WHERE mensagens.fluxo = 'nai'::text AND mensagens.direcao = 'recebida'::text AND (mensagens.status = ANY (ARRAY['Recebido'::text, 'Processando'::text])) AND mensagens.criada_em > (now() - '24:00:00'::interval)) AS chegando,
    ( SELECT count(*) AS count
           FROM nai_contato
          WHERE nai_contato.humano_assumiu_em IS NOT NULL) AS conversas_com_o_tel,
    ( SELECT count(*) AS count
           FROM nai_contato
          WHERE nai_contato.liberado_em IS NOT NULL) AS conversas_liberadas,
    ( SELECT round(EXTRACT(epoch FROM now() - min(nai_saida.criado_em)))::integer AS round
           FROM nai_saida
          WHERE nai_saida.estado = ANY (ARRAY['pendente'::text, 'enviando'::text])) AS mais_velha_segundos;
