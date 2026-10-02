-- 261 (02/10/2026): O CADASTRO NÃO FALA DA CONSULTA.
-- Pedro, 01/10 à noite: "são webhooks diferentes com funções diferentes que vão
-- ser disparados por bots diferentes, você precisa se atentar a isso".
--
-- A 260 devolvia ao bot do cadastro um `parecido_com` (o melhor candidato da
-- consulta da 258). Era a consulta vazando para dentro do outro webhook: o bot
-- que cadastra passava a receber resposta de um serviço que não é o dele.
-- Sai da resposta. O que NÃO muda: os parecidos continuam guardados no envio
-- (`candidatos`) para a PESSOA que aprova ver na aba -- isso é ajuda para o
-- humano, do nosso lado, e se a busca falhar o cadastro entra do mesmo jeito.
--
-- O resto da separação é no CRM (token, limite e rota de porta 80 próprios de
-- cada webhook: crm/src/lib/botDeImoveis.ts).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

SELECT pg_temp.trocar('crm_olx_bot_receber(jsonb)'::regprocedure,
$de$    -- o bot fica sabendo se parece com algo que já é nosso
    'parecido_com', CASE WHEN coalesce((v_cand ->> 'melhor_score')::int, 0) >= 45
        THEN jsonb_build_object('id_imovel', v_cand -> 'candidatos' -> 0 ->> 'id_imovel',
                                'score', (v_cand ->> 'melhor_score')::int,
                                'confianca', v_cand -> 'candidatos' -> 0 ->> 'confianca') END,
$de$,
$para$    -- 261: sem `parecido_com`. Este webhook é de outro bot e não devolve nada
    -- da consulta; os parecidos ficam só no envio, para quem aprova.
$para$);
COMMIT;
