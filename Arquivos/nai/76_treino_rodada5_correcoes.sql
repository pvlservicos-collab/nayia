-- =====================================================================
-- NAI -- 76: as correcoes do Tel na rodada 5 de treino (22/09/2026)
--
-- Tres julgamentos. Dois viram regra de prompt, um era verificacao:
--
--   caso 97  -- "posso anunciar alguns imoveis seus, os de alugueis?"
--     Ela escalou ao Tel dizendo "nao achei na base". Ele: "Dizer que pode, e
--     perguntar -- basta estar no grupo. Modelo: Boa noite, pode trabalhar
--     sim, voce ja esta no nosso grupo (anunciar imoveis easy)?"
--     O nome real do grupo na tabela `corretores` e "IMOVEIS PARA ANUNCIAR
--     EASY"; a frase usa esse nome.
--
--   caso 144 -- antes o corretor pediu "imovel para locacao ate R$ 5.000
--     mobiliado na Adrianopolis"; depois perguntou do acabamento. Ela
--     respondeu "de qual imovel o Sr. fala?". Ele: "ele errou nao mandando".
--     O pedido estava na memoria dela e ficou sem resposta.
--
--   caso 140 -- nao era sobre a resposta: ele pediu para confirmar que, ao
--     ligar a IA, ela so responde quem esta cadastrado como corretor. A
--     conferencia foi feita no chat (regra `so_corretor_da_lista`); aqui so
--     fica marcado como tratado.
--
-- As duas regras entram NO LUGAR DELAS no fluxo (etapa 1 e "Releia a
-- mensagem"), afirmativas e com o exemplo da fala certa -- nao no fim do
-- prompt. Da ultima vez que pendurei regra no fim (a CTA, arquivo 72), ela
-- nao pegou.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_texto  text;
  v_novo   text;
  v_versao int;
  a text; b text;
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF v_texto IS NULL THEN RAISE EXCEPTION 'nai_prompt do corretor nao existe'; END IF;
  v_novo := v_texto;

  -- 1. pedido de parceria: etapa 1, logo depois de "Quando ele ja pedir visita"
  a := E'- Quando ele já pedir visita, vá para a etapa 5.\n';
  IF position('Imóveis para Anunciar Easy' IN v_novo) = 0 THEN
    IF position(a IN v_novo) = 0 THEN RAISE EXCEPTION 'nao achei o fim da etapa 1'; END IF;
    v_novo := replace(v_novo, a, a ||
E'- Quando ele perguntar se pode anunciar ou trabalhar com os nossos imóveis, diga que pode e pergunte se ele já está no nosso grupo. É pedido de parceria: responda você mesma, na hora.\n' ||
E'  - Ele: "posso anunciar alguns imóveis seus, os de aluguel?" → "Boa tarde, pode trabalhar sim! O Sr. já está no nosso grupo, o Imóveis para Anunciar Easy?"\n');
  END IF;

  -- 2. pedido anterior sem resposta: dentro de "Releia a mensagem antes de perguntar"
  b := E'  quartos e teto: chame a busca. Nao pergunte nada.\n';
  IF position('Releia tambem as mensagens anteriores dele' IN v_novo) = 0 THEN
    IF position(b IN v_novo) = 0 THEN RAISE EXCEPTION 'nao achei a secao Releia a mensagem'; END IF;
    v_novo := replace(v_novo, b, b ||
E'Releia tambem as mensagens anteriores dele. Quando ele ja pediu imovel e o\n' ||
E'pedido ficou sem resposta, faca essa busca agora e mande a lista.\n' ||
E'- Antes ele escreveu "tem imovel para locacao ate R$ 5.000 mobiliado no\n' ||
E'  Adrianopolis?" e agora pergunta "como e o acabamento?" -> chame\n' ||
E'  buscar_por_perfil com Adrianopolis, teto 5000 e mobiliado, e mande a lista.\n');
  END IF;

  IF v_novo = v_texto THEN RAISE NOTICE 'as duas regras ja estavam no prompt'; RETURN; END IF;

  SELECT coalesce(max(versao), 0) + 1 INTO v_versao FROM nai_prompt_historico WHERE papel = 'corretor';
  PERFORM nai_salvar_prompt('corretor', v_novo, v_versao,
    'treino rodada 5: pedido de parceria (caso 97) e pedido anterior sem resposta (caso 144)');
  RAISE NOTICE 'prompt do corretor: % -> % chars (versao % guardada)', length(v_texto), length(v_novo), v_versao;
END $$;

UPDATE nai_treino_julgamento SET aplicada_em = now(), aplicada_como = CASE caso_id
    WHEN 97  THEN '76: etapa 1 -- pedido de parceria: "pode trabalhar sim! O Sr. ja esta no nosso grupo, o Imoveis para Anunciar Easy?"'
    WHEN 144 THEN '76: Releia a mensagem -- pedido anterior sem resposta vira busca agora'
    WHEN 140 THEN '76: verificacao respondida no chat -- so_corretor_da_lista=sim; dono de imovel segue o caminho de proprietario'
  END
 WHERE caso_id IN (97, 140, 144) AND aplicada_em IS NULL;

COMMIT;

SELECT length(texto) AS chars,
       texto LIKE '%Imóveis para Anunciar Easy%'                 AS regra_parceria,
       texto LIKE '%Releia tambem as mensagens anteriores dele%' AS regra_pedido_anterior
  FROM nai_prompt WHERE papel = 'corretor';
SELECT caso_id, aplicada_em IS NOT NULL AS aplicada FROM nai_treino_julgamento WHERE caso_id IN (97,140,144) ORDER BY 1;
