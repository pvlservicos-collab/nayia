-- A PERGUNTA QUE A NAY FEZ AO TEL, esperando "sim" ou "não".
--
-- O PEDIDO (Tel, 14/09), com a conversa dele:
--
--   Tel:  Posta no grupo anunciar easy 1885
--   Nay:  1885 já foi postado no Easy em 01/09/2026. Não postei de novo.
--   Tel:  Pode postar novamente
--   Nay:  posso sim, tel. qual código você quer que eu poste novamente?   <- o AGENTE
--   Tel:  1885
--   Nay:  (o card do 1885, no chat DELE -- não no grupo)
--
-- "quero que poste novamente mas ela me perguntando e eu confirmando". A
-- recusa passa a PERGUNTAR, e o "sim" dele posta.
--
-- POR QUE PRECISA DE ESTADO: "sim" não diz o quê. Sem saber que existe uma
-- pergunta aberta, "Pode postar novamente" caiu no agente, que não sabia de
-- qual imóvel se falava -- e o "1885" solto caiu no ramo de código puro, que
-- manda o card para o chat do próprio Tel.
--
-- POR QUE A FUNÇÃO É LIDA NO `Reservar mensagens`: o "sim" só pode virar
-- comando QUANDO HÁ PERGUNTA. Os três ramos do fluxo rodam em paralelo, e o
-- `Comando do Tel` (que manda ao publicador) e o `Rotear para o agente` (que
-- descarta) precisam ver o MESMO retrato -- calculado uma vez, antes da
-- divisão, como o `pede_visita` já é. Sem isso todo "sim" dele viraria
-- comando, ou nenhum viraria.
--
-- POR QUE "SIM" SÓ VALE SEM PENDÊNCIA ESPERANDO CONFIRMAÇÃO: "sim" é também a
-- palavra que libera a resposta de pendência (`nay_responder_conversando`,
-- `pendencia_rascunho`). Com as duas abertas, o mesmo "sim" dispararia duas
-- coisas irreversíveis ao mesmo tempo. Medido em 14/09: aquele mecanismo
-- nunca foi usado (zero rascunhos desde que existe) -- a parede fica mesmo
-- assim, porque o custo do conflito é postar sem ele querer.
--
--   docker cp pergunta_ao_tel.sql nay-postgres:/tmp/pt.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/pt.sql

CREATE TABLE IF NOT EXISTS pergunta_ao_tel (
    id             serial PRIMARY KEY,
    -- o que o "sim" faz: 'repostar_easy'
    acao           text        NOT NULL,
    codigo         text,
    criada_em      timestamptz NOT NULL DEFAULT now(),
    respondida_em  timestamptz,
    -- 'sim', 'nao', 'trocada' (veio outra pergunta), 'vencida'
    resposta       text
);

-- UMA SÓ EM ABERTO. Com duas, "sim" seria ambíguo e postaria a errada.
CREATE UNIQUE INDEX IF NOT EXISTS pergunta_ao_tel_uma_aberta
    ON pergunta_ao_tel ((true)) WHERE respondida_em IS NULL;

-- A janela. Pergunta de ontem respondida hoje com "sim" não pode postar --
-- ele pode estar respondendo outra coisa.
INSERT INTO config (chave, valor) VALUES ('pergunta_ao_tel_minutos', '30')
    ON CONFLICT (chave) DO NOTHING;

-- Existe pergunta aberta, dentro da janela, e nenhuma pendência esperando o
-- mesmo "sim"? Falha FECHADA: qualquer dúvida devolve false, e false faz o
-- "sim" seguir para o agente como sempre seguiu.
CREATE OR REPLACE FUNCTION nay_pergunta_aberta_do_tel()
RETURNS boolean LANGUAGE sql STABLE AS $fn$
  SELECT coalesce((
    SELECT true FROM pergunta_ao_tel p
     WHERE p.respondida_em IS NULL
       AND p.criada_em > now() - (coalesce(
             (SELECT valor FROM config WHERE chave = 'pergunta_ao_tel_minutos'),
             '30') || ' minutes')::interval
       AND NOT EXISTS (SELECT 1 FROM pendencia_rascunho)
     LIMIT 1), false);
$fn$;
