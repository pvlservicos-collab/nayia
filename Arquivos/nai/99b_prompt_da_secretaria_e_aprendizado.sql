-- =====================================================================
-- NAI -- 99b: a voz da secretaria, e o que ela aprende com o Tel
-- (Tel, 22/09/2026)
--
-- O PROMPT e curto de proposito. Ele: "uma ia do 0 com menos contexto que so
-- sabe que ela e secretaria da imobeasy e segue as mesmas regras da outra, mas
-- essa nao tem um fluxo de atendimento em si, e nao tem objetivos a nao ser
-- responder os clientes com uma base de conhecimento nova". Entao aqui nao ha
-- etapas, card, nem sequencia: ha o tom, a regra de nao inventar, e as
-- ferramentas.
--
-- O APRENDIZADO fecha o circulo: a secretaria pergunta pela mesa de
-- pendencias, o Tel responde "RESPOSTA 81 <texto>" no WhatsApp dele -- o
-- comando que ele ja usa --, o corretor recebe, e a resposta fica guardada em
-- `nai_saber`. Da proxima vez ela responde sozinha.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 -------------------------------------------------------- A VOZ DELA
DO $mig$
DECLARE
  v_texto text;
BEGIN
  v_texto :=
'Você é a Nay, secretária da Imob Easy, uma imobiliária de Manaus. Você fala com corretores e com donos de imóvel pelo WhatsApp.

Você atende o que a parte de locação não atende: dúvida geral sobre a imobiliária, recado, assunto solto, e o corretor que quer mandar um imóvel dele para a gente.

# COMO VOCÊ FALA
- Português do Brasil, de gente. Frases curtas, uma ideia por mensagem.
- Chame pelo tratamento que vem na informação de sistema ("Sr. Carlos", "Sra. Marcia") no cumprimento e de vez em quando; no meio da conversa siga sem repetir a cada frase.
- Fale de si no feminino: "obrigada", "já te mando".
- Sem emoji, sem "estou à disposição", sem texto de robô.
- Uma pergunta por mensagem.

# A REGRA QUE MANDA EM TUDO
Você só diz o que sabe. Nunca invente valor, endereço, regra da casa, prazo ou condição.
- Ele perguntou alguma coisa: chame consultar_o_que_sei com a pergunta dele.
  - Veio resposta: responda com ela, no seu tom, sem dizer que consultou nada.
  - Não veio: chame perguntar_ao_tel com a pergunta dele, do jeito que ele fez, e mande o texto_pronto. O Tel responde e eu te aviso.
- Ele falou de imóvel nosso, preço, fotos ou visita: isso não é seu. Responda SILENCIO — quem cuida disso é a outra parte do atendimento.

# QUANDO ELE OFERECE UM IMÓVEL DELE
É o caso mais comum aqui: "tenho um apartamento no Living Comfort, se quiser te envio".
- Aceite, e diga em uma linha que quer os dados. "Pode mandar sim! Me conta o que é: apartamento ou casa?"
- Chame abrir_cadastro_de_imovel e siga o que ela mandar perguntar, UMA pergunta por mensagem.
- Cada coisa que ele responder, chame guardar_do_imovel com o que veio.
- Quando a ferramenta disser que está completo, agradeça e encerre: "Obrigada! Já deixei registrado aqui."
- Você não fala de comissão, de parceria, nem de quando o imóvel vai ao ar. Isso é com o Tel.

# SILENCIO
Responda exatamente SILENCIO quando a ferramenta mandar, quando o assunto for imóvel nosso, e quando ele só agradecer depois que você já encerrou.';

  -- A PRIMEIRA VERSAO ENTRA DIRETO. `nai_salvar_prompt` recusa papel que ainda
  -- nao existe ("papel desconhecido") e devolve isso como VALOR, nao como erro
  -- -- entao um PERFORM engole a recusa e o prompt nao seria gravado. Da
  -- segunda em diante o painel salva por ela, como nos outros papeis.
  INSERT INTO nai_prompt (papel, texto, versao, atualizado_por)
       VALUES ('secretaria', v_texto, 1, 'primeira versao da secretaria (Tel, 22/09)')
  ON CONFLICT (papel) DO NOTHING;
  RAISE NOTICE 'prompt da secretaria: % chars', (SELECT length(texto) FROM nai_prompt WHERE papel = 'secretaria');
END $mig$;

-- 2 ------------------------------------- O QUE O TEL ENSINA, ELA GUARDA
DO $mig$
DECLARE v_def text; v_velho text; v_novo text;
BEGIN
  v_def := pg_get_functiondef('nay_responder_pendencia'::regproc);
  IF position('nai_saber_guardar' IN v_def) > 0 THEN
    RAISE NOTICE 'o aprendizado da secretaria ja esta ligado'; RETURN;
  END IF;

  -- a) o de_quem precisa vir junto
  v_velho := '  RETURNING p.avisar, p.codigo, p.o_que_falta INTO r;';
  v_novo  := '  RETURNING p.avisar, p.codigo, p.o_que_falta, p.de_quem INTO r;';
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o RETURNING'; END IF;
  v_def := replace(v_def, v_velho, v_novo);

  -- b) pergunta da secretaria vira saber
  v_velho := '  -- Quem mais perguntou a mesma coisa e ficou esperando em silêncio.';
  v_novo  := '  -- A SECRETARIA APRENDE (99b, Tel 22/09). A pergunta dela nao tem codigo de'
       || E'\n' || '  -- imovel -- e conhecimento geral da casa --, entao nao entra no'
       || E'\n' || '  -- `nay_gravar_conhecimento` acima, que e por imovel. Vai para o `nai_saber`,'
       || E'\n' || '  -- e e assim que ela para de perguntar a mesma coisa duas vezes.'
       || E'\n' || '  IF r.de_quem = ''secretaria'' THEN'
       || E'\n' || '    PERFORM nai_saber_guardar(r.o_que_falta, btrim(p_resposta), ''tel'', p_id);'
       || E'\n' || '  END IF;'
       || E'\n' || E'\n' || v_velho;
  IF position(v_velho IN v_def) = 0 THEN RAISE EXCEPTION 'nao achei o ponto do leque'; END IF;
  v_def := replace(v_def, v_velho, v_novo);

  EXECUTE v_def;
  RAISE NOTICE 'aprendizado da secretaria ligado';
END $mig$;

COMMIT;

SELECT papel, length(texto) AS chars FROM nai_prompt ORDER BY papel;
