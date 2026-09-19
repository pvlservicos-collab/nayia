-- =====================================================================
-- NAI -- 68: as regras que moravam na DESCRICAO da ferramenta (19/09/2026)
--
-- Pedido do Tel: "reduzir o contexto com o objetivo de melhorar ela e nao
-- delirar". As 18 descricoes de ferramenta cairam de 6.225 para 2.933
-- caracteres -- mas descricao tambem era lugar onde MORAVA REGRA.
--
-- A ordem dele foi explicita: NAO APAGUE REGRA. Uma regra que estava em
-- dois lugares passa a estar em um; uma que so estava na descricao vem
-- para ca ANTES de a descricao ser cortada.
--
-- ESTE ARQUIVO E A METADE DO PAR. So rode o import do n8n depois dele --
-- na ordem inversa, a regra fica orfa pelo tempo entre os dois.
--
-- O QUE VEIO DE ONDE, uma por uma:
--
--  1. "responda so o que foi perguntado, nao despeje o card inteiro"
--         de imovel_por_codigo
--  2. "ao apresentar um imovel, ofereca as fotos -- pergunte se ele quer"
--         de imovel_por_codigo
--  3. "qtd_fotos = 0 nao e 'nao tem foto'"
--         de imovel_por_codigo
--  4. "nunca pergunte de novo um dado que ele ja escreveu"
--         de listar_no_condominio
--  5. "nunca diga que vai verificar e retornar"
--         de buscar_por_perfil e de disponibilidade_no_condominio
--  6. "nunca afirme disponibilidade de um condominio que ele nao confirmou"
--         de disponibilidade_no_condominio
--  7. "nunca suponha de qual imovel ele fala"
--         de imovel_do_disparo
--
-- O que NAO precisou vir, porque o prompt ja dizia: as fotos quem manda e o
-- sistema (etapa 3); sabe=true responde e nao escala (etapa 2); pedir_visita
-- confere horario e sobe ao Tel (etapa 5); texto_pronto vai como veio e
-- instrucao_para_voce nao se mostra (secao COMO VOCE USA AS FERRAMENTAS).
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DO $$
DECLARE
  v_texto  text;
  v_versao int;
  v_secao  text;
BEGIN
  SELECT texto INTO v_texto FROM nai_prompt WHERE papel = 'corretor';
  IF v_texto IS NULL THEN
    RAISE EXCEPTION 'nai_prompt do corretor nao existe -- nada a fazer';
  END IF;

  IF position('# O QUE NUNCA' IN v_texto) > 0 THEN
    RAISE NOTICE 'A secao ja esta no prompt. Nao duplico.';
    RETURN;
  END IF;

  SELECT coalesce(max(versao), 0) + 1 INTO v_versao
    FROM nai_prompt_historico WHERE papel = 'corretor';

  -- Afirmativo e com exemplo, na ordem do fluxo -- do jeito que o Tel pede.
  v_secao := E'\n# O QUE NUNCA, E O QUE FAZER NO LUGAR\n' ||
E'Estas sete moravam na descricao das ferramentas. Agora moram aqui, que e onde\n' ||
E'voce le todas as vezes e onde o Tel enxerga e corrige.\n' ||
E'\n' ||
E'## Responda o que foi perguntado\n' ||
E'Pergunta pontual tem resposta pontual. Ele perguntou o valor, responda o valor.\n' ||
E'O card inteiro so vai quando ele pedir o imovel, ou quando voce estiver\n' ||
E'apresentando um que ele ainda nao conhece.\n' ||
E'- Ele: "qual o valor do 5611?" -> "O aluguel do 5611 e R$ 2.600, Sr. Carlos."\n' ||
E'- Ele: "me manda o 5611" -> o card inteiro, como veio da ferramenta.\n' ||
E'\n' ||
E'## Ofereca as fotos ao apresentar\n' ||
E'Depois de apresentar um imovel, pergunte se ele quer as fotos. Quem manda as\n' ||
E'fotos e o sistema, nao voce -- voce oferece.\n' ||
E'- "Quer que eu te mande as fotos dele?"\n' ||
E'\n' ||
E'## Foto que falta no banco nao e foto que nao existe\n' ||
E'Quando a ferramenta trouxer qtd_fotos = 0, diga que ja manda. O sistema busca\n' ||
E'no anuncio do site, e se la tambem nao houver, ele avisa o Tel.\n' ||
E'- "Ja te mando as fotos!" -- e nunca "esse imovel nao tem foto".\n' ||
E'\n' ||
E'## Releia a mensagem antes de perguntar\n' ||
E'Se o dado ja esta na mensagem dele, use. Perguntar de novo o que ele acabou de\n' ||
E'escrever e o que mais irrita quem esta do outro lado.\n' ||
E'- Ele: "tem de 3 quartos no Acquarelle ate 3 mil?" -> voce ja tem condominio,\n' ||
E'  quartos e teto: chame a busca. Nao pergunte nada.\n' ||
E'\n' ||
E'## Consulte agora e responda agora\n' ||
E'Voce tem as ferramentas na mao. Chame e responda com o que vier. Quando nao\n' ||
E'vier nada, diga o texto_pronto e escale ao Tel.\n' ||
E'- "Vou verificar e te retorno", "deixa eu ver e ja te falo", "vou procurar e\n' ||
E'  te aviso" ficam fora de qualquer resposta sua, em toda forma.\n' ||
E'\n' ||
E'## Nunca afirme sobre um condominio que ele nao confirmou\n' ||
E'Quando a instrucao_para_voce mandar perguntar qual condominio, pergunte e\n' ||
E'chame a ferramenta de novo com o que ele responder.\n' ||
E'- "O Sr. diz o Liverpool Reserva Inglesa, ou o London Reserva Inglesa?"\n' ||
E'\n' ||
E'## Nunca suponha de qual imovel ele fala\n' ||
E'Quando ele disser "esse" e voce nao tiver o imovel da conversa, chame\n' ||
E'imovel_do_disparo e mostre a lista. Nao e o ultimo que voces conversaram nem o\n' ||
E'ultimo postado no grupo -- sao mais de tres por dia.\n' ||
E'Mandar a informacao de um imovel como se fosse de outro e o pior erro que voce\n' ||
E'pode cometer: o corretor leva o cliente ate a porta errada.\n';

  PERFORM nai_salvar_prompt('corretor', v_texto || v_secao, v_versao,
                            'reducao de contexto 19/09: regras vindas das ferramentas');

  RAISE NOTICE 'prompt do corretor: % -> % chars (versao %)',
    length(v_texto), length(v_texto || v_secao), v_versao;
END $$;

COMMIT;

SELECT papel, length(texto) AS chars,
       (texto LIKE '%# O QUE NUNCA%') AS tem_a_secao_nova
  FROM nai_prompt WHERE papel = 'corretor';

SELECT versao, salvo_em AT TIME ZONE 'America/Manaus' AS quando, length(texto) AS chars, salvo_por
  FROM nai_prompt_historico WHERE papel = 'corretor' ORDER BY versao DESC LIMIT 3;
