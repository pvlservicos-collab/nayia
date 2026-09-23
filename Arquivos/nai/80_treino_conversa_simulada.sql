-- =====================================================================
-- NAI -- 80: o treino passa a aceitar CONVERSA SIMULADA (Tel, 22/09/2026)
--
-- Ele: "quero que vc rode a proxima rodada mas que voce crie as variacoes
-- possiveis de conversa como se fosse simulando meus clientes ... e va
-- estendendo a conversa com a Nay ate o final para testarmos todo o fluxo,
-- cria umas 20".
--
-- Ate aqui cada caso era UMA mensagem real, reentregue. Conversa simulada e
-- outra coisa: um roteiro de varios passos, e cada passo entra depois da
-- resposta dela ao anterior, na MESMA conversa (a memoria nao e zerada entre
-- um passo e outro, so entre uma conversa e outra).
--
-- Cada passo vira um caso, para ele julgar mensagem a mensagem, como sempre.
-- O caso de roteiro nao tem turno nem mensagem de origem -- nao existiu na
-- vida real --, entao a regra de origem passa a aceitar o roteiro.
--   roteiro -- nome da conversa ("01-busca-ponta-negra")
--   passo   -- 1, 2, 3...
--   persona -- o nome do corretor simulado ("Carla Mendes")
-- O `contexto` de cada passo e a conversa ate ali, dos dois lados: e o que o
-- painel mostra acima da resposta.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

ALTER TABLE nai_treino_caso ADD COLUMN IF NOT EXISTS roteiro text;
ALTER TABLE nai_treino_caso ADD COLUMN IF NOT EXISTS passo   int;
ALTER TABLE nai_treino_caso ADD COLUMN IF NOT EXISTS persona text;

ALTER TABLE nai_treino_caso DROP CONSTRAINT IF EXISTS nai_treino_caso_origem_ok;
ALTER TABLE nai_treino_caso ADD CONSTRAINT nai_treino_caso_origem_ok
  CHECK (turno_origem IS NOT NULL OR msg_origem IS NOT NULL OR roteiro IS NOT NULL);

-- O painel: as tres colunas novas vao NO FIM (CREATE OR REPLACE VIEW so
-- aceita coluna acrescentada no final).
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
    cic.rotulo AS ciclo_rotulo,
    (( SELECT count(*) AS count
           FROM nai_saida s
          WHERE s.turno_id = k.turno_simulado AND s.tipo = 'imagem'::text))::integer AS fotos_agora,
    k.roteiro,
    k.passo,
    k.persona
   FROM nai_treino_caso k
     JOIN nai_contato c ON c.id = k.contato_origem
     JOIN nai_treino_ciclo cic ON cic.id = k.ciclo_id
     LEFT JOIN nai_treino_julgamento j ON j.caso_id = k.id;

COMMIT;

SELECT column_name FROM information_schema.columns
 WHERE table_name = 'nai_treino_painel' AND column_name IN ('roteiro','passo','persona');
