-- =====================================================================
-- NAI -- 71: o painel de treino ganha as FOTOS e a RODADA (Tel, 21/09/2026)
--
-- Ele, olhando a rodada 2: "eu ja vi uma la que a nay nao mandou as fotos,
-- n precisa aparecer as fotos la so (fotos)".
--
-- FUI CONFERIR E ELA MANDOU. O caso 10 gerou 10 fotos e o 13 gerou 7, todas
-- em `nai_saida` com tipo='imagem'. O que acontece e que
-- `nai_treino_caso.ela_respondeu_agora` guarda SO TEXTO -- as linhas de
-- imagem nunca chegam ao painel. Ou seja: era ponto cego da tela, nao falha
-- dela. Julgar por uma tela que esconde metade da resposta produz julgamento
-- errado, e foi o que quase aconteceu.
--
-- A CONTAGEM VEM PELA VIEW, nao por GRANT. A role da API (nay_site_nai) NAO
-- pode ler `nai_saida` -- e a parede do arquivo 67, e ela fica de pe. View
-- roda com o privilegio do DONO, entao ela conta la dentro e devolve so o
-- numero. Nenhuma URL de foto sai daqui: o Tel pediu "(fotos)", nao as fotos.
--
-- E o ROTULO DO CICLO junto, para cada conversa poder carregar a etiqueta da
-- rodada de onde veio.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE VIEW nai_treino_painel AS
 SELECT k.id,
    k.ciclo_id,
    k.estado,
    k.erro AS erro_execucao,
    k.turno_origem,
    k.turno_simulado,
    k.exec_id,
    k.quando_original,
    k.rodado_em,
    k.ele_disse,
    k.ela_respondeu_antes,
    k.ela_respondeu_agora,
    k.ferramentas_antes,
    k.ferramentas_agora,
    k.contexto,
    k.estado = 'rodado'::text
      AND btrim(COALESCE(k.ela_respondeu_agora, ''::text))
          IS DISTINCT FROM btrim(COALESCE(k.ela_respondeu_antes, ''::text)) AS mudou,
    c.nome_whatsapp,
    c.nome_completo,
    c.telefone,
    j.veredito,
    j.erro AS julgamento_erro,
    j.solucao AS julgamento_solucao,
    j.aplicada_em,
    j.julgado_em,
    -- AS DUAS NOVAS VAO NO FIM de proposito: CREATE OR REPLACE VIEW so aceita
    -- coluna acrescentada no final. No meio, ele recusa com "cannot change
    -- name of view column" -- e ai so dropando, o que quebraria a API no ar.
    cic.rotulo AS ciclo_rotulo,
    -- Quantas FOTOS ela mandou nesta re-execucao. So o numero, nunca a URL.
    (SELECT count(*) FROM nai_saida s
      WHERE s.turno_id = k.turno_simulado AND s.tipo = 'imagem')::int AS fotos_agora
   FROM nai_treino_caso k
     JOIN nai_contato c ON c.id = k.contato_origem
     JOIN nai_treino_ciclo cic ON cic.id = k.ciclo_id
     LEFT JOIN nai_treino_julgamento j ON j.caso_id = k.id;

COMMIT;

-- Prova: os casos que mandaram foto aparecem com o numero.
SELECT id, ciclo_rotulo, fotos_agora,
       left(regexp_replace(ele_disse, '\s+', ' ', 'g'), 40) AS ele_disse
  FROM nai_treino_painel
 WHERE ciclo_id = 4 AND fotos_agora > 0
 ORDER BY id;
