-- =====================================================================
-- NAI -- 84: a Nay de Locacao e Parceria volta ao ar, SO para corretor
-- (Tel, 22/09/2026)
--
-- Ele: "agora ligue a Nay de locacao e parceria no whatsapp dela, com aquela
-- nova funcao de ao chamar o proprietario quando alguem agendar visita chamar
-- o Tel para evitar o numero cair, e separa direitinho para responder apenas
-- os corretores, que sao todos os que estao nos grupos ou estao com xx antes
-- no numero, garanta que ela so responda esses, e comeca a rodar de agora
-- para a frente, nao responda as pessoas que ja estavam conversando com o
-- Tel antes, so se elas pedirem imoveis claramente".
--
-- O QUE CADA PEDIDO VIROU:
--
--   "chamar o Tel no lugar do proprietario" -> ja estava ligado
--     (proprietario_pelo_tel = sim, arquivo 37). Conferido, nao muda.
--
--   "so os corretores: grupos ou Xx na agenda" -> a lista `corretores`.
--     Os dos grupos ja estavam; os da agenda entram pelo
--     sincronizar_agenda_xx.py (34 novos, fonte 'agenda', de hora em hora).
--     E a PORTA muda: ate aqui `nai_lista_governa` deixava FORA da regra da
--     lista todo dono de imovel (cadastro, captacao, visita, quem ja foi
--     tratado como dono). Isso tinha motivo -- nao calar dono no meio de uma
--     visita -- mas com o desvio para o Tel ligado a Nay nao fala com dono
--     nenhum, e a isencao virou uma porta aberta: qualquer dono entrava e
--     era julgado pelas outras regras, como se fosse corretor. E 70 dos 176
--     corretores salvos com Xx estao no cadastro de proprietarios -- ficariam
--     de fora da lista que o Tel mandou valer. Agora ficam fora da regra so:
--     o Tel, quem pode dar comando, o acompanhante, a equipe, e o dono de uma
--     visita EM ANDAMENTO (esse e roteado como proprietario antes da porta).
--
--   "de agora para a frente" -> o carimbo `regra_publico_desde` vira AGORA.
--     Quem tem mensagem antes do carimbo e conversa do Tel: a Nay so entra se
--     a pessoa pedir foto de um imovel ou pedir imoveis ("so se elas pedirem
--     imoveis claramente"). E o `liberado_em` de quem tinha pedido foto entre
--     15 e 19/09 volta a zero -- senao essas conversas, que o Tel tocou
--     depois, voltariam direto para ela. Guardado antes em tabela.
--
--   limpeza do treino -> 27 pendencias abertas vieram do treino e do numero
--     de teste; o ciclo de pendencias cobraria o Tel por elas. Descartadas.
--
-- A VIRADA DE CHAVE (modo e envio_simulado) NAO esta aqui: vai num passo
-- separado, depois de conferir o resultado deste arquivo.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1. guarda quem estava liberado, e zera --------------------------------
CREATE TABLE IF NOT EXISTS nai_backup_liberado_20260922 AS
  SELECT id, chave, liberado_em, liberado_motivo, now() AS guardado_em
    FROM nai_contato WHERE liberado_em IS NOT NULL;
UPDATE nai_contato SET liberado_em = NULL, liberado_motivo = NULL
 WHERE liberado_em IS NOT NULL
   AND NOT (chave = ANY (nai_chaves_teste()));

-- 2. pendencias do treino e do teste ------------------------------------
UPDATE pendencias p SET status = 'descartada', respondida_em = now(),
       resposta = coalesce(resposta, 'descartada ao ligar a Nay (22/09): veio do treino/teste')
 WHERE p.status = 'aberta'
   AND (EXISTS (SELECT 1 FROM pendencia_interessado i
                 WHERE i.pendencia_id = p.id
                   AND nai_chave(i.telefone) IN (nai_chave('559990000001'), nai_chave('5596991712835'),
                                                 nai_chave('5592988887777')))
        OR p.de_quem ~ '(559990000001|5596991712835|5592988887777|Treino)');

-- 3. a porta: so fica fora da lista quem nao e atendido como corretor -----
CREATE OR REPLACE FUNCTION public.nai_lista_governa(p_chave text, p_contato bigint)
 RETURNS boolean
 LANGUAGE sql
 STABLE
AS $function$
  -- 84 (Tel, 22/09): "garanta que ela so responda esses". Fica FORA da regra
  -- da lista so quem nunca e atendido como corretor: o Tel, quem pode dar
  -- comando, o acompanhante, a equipe e o dono de uma visita EM ANDAMENTO.
  -- Dono de imovel sem visita aberta agora passa pela lista como qualquer
  -- um: com o desvio para o Tel ligado, a Nay nao conversa com dono.
  SELECT NOT (
       p_chave = nai_chave(nai_cfg('tel_telefone'))
    OR nai_pode_comandar(p_chave)
    OR nai_e_motoboy(p_chave)
    OR EXISTS (SELECT 1 FROM equipe e WHERE nai_chave(e.telefone) = p_chave)
    OR (p_contato IS NOT NULL AND EXISTS (
          SELECT 1 FROM nai_visita x
           WHERE x.proprietario_id = p_contato AND nai_visita_aberta(x.estado)))
  );
$function$;

-- 4. de agora para a frente -----------------------------------------------
UPDATE nai_config SET valor = to_char(now(), 'YYYY-MM-DD HH24:MI:SSOF'), atualizado_em = now()
 WHERE chave = 'regra_publico_desde';

COMMIT;

SELECT chave, valor FROM nai_config
 WHERE chave IN ('regra_publico', 'regra_publico_desde', 'so_corretor_da_lista', 'proprietario_pelo_tel',
                 'modo', 'envio_simulado', 'pausada')
 ORDER BY 1;
SELECT (SELECT count(*) FROM nai_backup_liberado_20260922) AS liberados_guardados,
       (SELECT count(*) FROM nai_contato WHERE liberado_em IS NOT NULL) AS liberados_agora,
       (SELECT count(*) FROM pendencias WHERE status = 'aberta') AS pendencias_abertas;
