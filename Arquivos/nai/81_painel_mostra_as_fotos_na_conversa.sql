-- =====================================================================
-- NAI -- 81: a conversa do treino mostra AS FOTOS, na ordem (Tel, 22/09/2026)
--
-- Ele, olhando a rodada 7: "estou achando que pode ter um bug mas nao sei se
-- e visual, so nas nossas conversas, que e ela juntando as mensagens em um
-- blocao, falando que enviou as fotos mas nao enviou mesmo".
--
-- MEDIDO ANTES DE MEXER: na rodada 7 inteira, nenhuma resposta em que ela
-- diz "aqui as fotos"/"ja te mando as fotos" ficou sem foto na caixa de
-- saida. O envio esta certo; quem mente e a tela.
--   * a lista junta tudo numa linha so (o "blocao");
--   * a aba Conversa monta os baloes a partir SO do texto dela, entao as
--     fotos nao aparecem em lugar nenhum -- le-se "Aqui as fotos" sem foto
--     nenhuma embaixo.
--
-- A view passa a devolver a SAIDA EM BLOCOS, na ordem em que sai no
-- WhatsApp: cada texto um balao, cada lote de fotos um balao "(12 fotos)".
-- Nenhuma URL de foto sai daqui, so a contagem.
--
-- DENTRO DA VIEW, NAO NUMA FUNCAO. A primeira versao poe isso numa funcao em
-- SQL e o painel passou a dar 500: funcao roda com a permissao de QUEM CHAMA,
-- e a role da API (nay_site_nai) nao pode ler `nai_saida` -- a parede do
-- arquivo 67. View roda com a do dono, entao a montagem vem num LATERAL.
--
-- Junto, um estado novo: CALADA. "o fluxo nao abriu turno nenhum" nao e
-- falha do executor -- e a conversa que passou para o Tel (escalada, visita
-- urgente). Marcar como erro faz o painel dizer "falhou" para o
-- comportamento certo.
-- =====================================================================

\set ON_ERROR_STOP on
BEGIN;
-- A FUNCAO NAO SERVE AQUI: funcao em SQL roda com a permissao de QUEM CHAMA,
-- e a role do painel (nay_site_nai) nao pode ler `nai_saida` -- a parede do
-- arquivo 67. A view, sim, roda com a do dono. Entao a montagem dos baloes
-- vem para dentro dela, num LATERAL. (O painel deu 500 por isso.)
CREATE OR REPLACE VIEW nai_treino_painel AS
 SELECT k.id, k.ciclo_id, k.estado, k.erro AS erro_execucao, k.turno_origem,
    k.turno_simulado, k.exec_id, k.quando_original, k.rodado_em, k.ele_disse,
    k.ela_respondeu_antes, k.ela_respondeu_agora, k.ferramentas_antes,
    k.ferramentas_agora, k.contexto,
    k.estado = 'rodado'::text
      AND btrim(COALESCE(k.ela_respondeu_agora, ''::text))
          IS DISTINCT FROM btrim(COALESCE(k.ela_respondeu_antes, ''::text)) AS mudou,
    c.nome_whatsapp, c.nome_completo, c.telefone,
    j.veredito, j.erro AS julgamento_erro, j.solucao AS julgamento_solucao,
    j.aplicada_em, j.julgado_em,
    cic.rotulo AS ciclo_rotulo,
    (( SELECT count(*) FROM nai_saida s
        WHERE s.turno_id = k.turno_simulado AND s.tipo = 'imagem'::text))::integer AS fotos_agora,
    k.roteiro, k.passo, k.persona,
    blocos.saida
   FROM nai_treino_caso k
     JOIN nai_contato c ON c.id = k.contato_origem
     JOIN nai_treino_ciclo cic ON cic.id = k.ciclo_id
     LEFT JOIN nai_treino_julgamento j ON j.caso_id = k.id
     LEFT JOIN LATERAL (
       -- cada texto e um balao (e uma mensagem no WhatsApp); fotos seguidas
       -- viram um balao so, com a contagem. Nenhuma URL sai daqui.
       SELECT coalesce(jsonb_agg(jsonb_build_object(
                'tipo', b.tipo, 'texto', b.texto, 'fotos', b.fotos)
              ORDER BY b.ordem), '[]'::jsonb) AS saida
         FROM (
           SELECT min(g.ordem) AS ordem,
                  CASE WHEN g.e_foto THEN 'fotos' ELSE 'texto' END AS tipo,
                  CASE WHEN g.e_foto THEN NULL ELSE min(g.texto) END AS texto,
                  CASE WHEN g.e_foto THEN count(*)::int END AS fotos
             FROM (
               SELECT s.ordem, s.texto, (s.tipo = 'imagem') AS e_foto,
                      CASE WHEN s.tipo = 'imagem'
                           THEN 'f' || (row_number() OVER (ORDER BY s.ordem, s.id)
                                        - row_number() OVER (PARTITION BY (s.tipo = 'imagem') ORDER BY s.ordem, s.id))::text
                           ELSE 't' || s.id::text END AS grupo
                 FROM nai_saida s
                WHERE s.turno_id = k.turno_simulado
                  AND s.estado <> 'bloqueado'
                  AND (s.tipo <> 'texto' OR btrim(coalesce(s.texto, '')) <> '')
             ) g
            GROUP BY g.grupo, g.e_foto
         ) b
     ) blocos ON true;
DROP FUNCTION IF EXISTS nai_treino_saida_em_blocos(bigint);

COMMIT;
SET ROLE nay_site_nai;
SELECT count(*) AS casos_do_ciclo_11, count(*) FILTER (WHERE jsonb_array_length(saida) > 0) AS com_baloes
  FROM nai_treino_painel WHERE ciclo_id = 11;
RESET ROLE;
