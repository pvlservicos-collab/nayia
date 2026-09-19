-- nay_escalar: reuso de resposta antiga, agora amarrado AO MESMO IMÓVEL.
--
-- O MECANISMO (que já existia e funciona): quando o Tel responde uma
-- pendência, a resposta fica em `pendencias.resposta`. Da próxima vez que
-- alguém perguntar coisa parecida, `nay_escalar` acha a resposta antiga e
-- devolve "o Tel já respondeu isso antes" -- a Nay responde na hora, sem
-- escalar de novo. É o aprendizado dela.
--
-- O BURACO (achado em 31/08): a condição de casamento era
--     AND (v_cod IS NULL OR p.codigo IS NULL OR p.codigo = v_cod)
-- ou seja, **código nulo de qualquer um dos lados casava com qualquer
-- imóvel**. Medido no banco: a pendência 2 ("aceita pet" -> "aceita sim,
-- até 10kg", gravada sem código) casava 1.00 com uma pergunta de pet sobre
-- QUALQUER outro imóvel. A Samira tinha acabado de dizer "Ele tem pet"
-- sobre a Casa do Nova Cidade -- ela teria recebido a regra de um imóvel
-- que ninguém sabe qual é.
--
-- Duas condições, com pesos diferentes:
--   * reuso de RESPOSTA: exige os dois códigos preenchidos e iguais.
--     Errar aqui manda informação errada para o corretor.
--   * dedupe de pendência ABERTA: `IS NOT DISTINCT FROM` (nulo casa só com
--     nulo). Errar aqui só gera pendência repetida.
--
-- ACRESCENTADO EM 31/08: os dois ramos registram quem perguntou, em
-- `pendencia_interessado`. Antes, o segundo corretor a perguntar a mesma
-- coisa caía no ramo `esperar` e não ficava ligado a pendência nenhuma --
-- quando o Tel respondia, só o primeiro recebia. Ver pendencia_ciclo.sql,
-- que precisa ser aplicado ANTES deste arquivo.
--
--   docker cp escalar_resposta_por_imovel.sql nay-postgres:/tmp/ne.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ne.sql

CREATE OR REPLACE FUNCTION public.nay_escalar(p_telefone text, p_nome text, p_codigo text, p_assunto text, p_disse text)
 RETURNS TABLE(acao text, texto_pronto text, id_pendencia integer)
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_cod     text := NULLIF(regexp_replace(NULLIF(NULLIF(NULLIF(btrim(coalesce(p_codigo,'')),''),'undefined'),'null'), '[^0-9]', '', 'g'),'');
  v_ass     text := CASE WHEN lower(btrim(coalesce(p_assunto,''))) IN ('undefined','null') THEN '' ELSE btrim(coalesce(p_assunto,'')) END;
  v_resp   text;
  v_id     integer;
  v_aberta integer;
BEGIN
  IF v_ass = '' THEN
    RETURN QUERY SELECT
      'invalido'::text,
      'ATENCAO: voce chamou a ferramenta sem dizer qual e o assunto. Chame de novo preenchendo assunto com a duvida em poucas palavras.'::text,
      NULL::integer;
    RETURN;
  END IF;

  -- PAREDE 1: o numero da unidade nao vira pendencia.
  --
  -- A recusa mora AQUI e nao no prompt porque o estrago e permanente: se
  -- isto virasse pendencia, o Tel responderia "ap 401" e o numero ficaria
  -- em `pendencias.resposta`, reusado para todo mundo que perguntasse
  -- parecido naquele imovel, para sempre. Nao chegando a existir
  -- pendencia, nao existe resposta para reusar. Ver unidade_nunca.sql.
  -- OS DOIS LADOS EM SEPARADO, nunca concatenados: com uma string so, o
  -- ruido de um campo cancelava o sinal do outro. Achado no red team de
  -- 01/09.
  IF nay_pede_localizacao_da_unidade(v_ass)
     OR nay_pede_localizacao_da_unidade(coalesce(p_disse,'')) THEN
    RETURN QUERY SELECT 'responder'::text, nay_recusa_de_unidade(), NULL::integer;
    RETURN;
  END IF;

  -- PAREDE 2: o codigo tem que ter vindo do corretor, nao da memoria dela.
  --
  -- Em 01/09 o modelo passou `codigo: "5717"` numa pergunta sobre o imovel
  -- 4946, tirando o numero da conversa anterior. Sem esta checagem a
  -- pendencia nasce no imovel errado e a resposta do Tel vira conhecimento
  -- do imovel errado. Ver codigo_confirmado.sql.
  -- Codigo que nao existe no catalogo tambem nao vale: `v_cod` e so
  -- "digitos que sobraram do texto", e um imovel inventado viraria
  -- pendencia de um imovel inventado.
  IF v_cod IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM imoveis i WHERE i.codigo::text = v_cod) THEN
    v_cod := NULL;
  END IF;

  IF v_cod IS NOT NULL
     AND nay_codigo_confirmado(p_telefone, v_cod) = 'nao' THEN
    RETURN QUERY SELECT 'perguntar'::text,
      (SELECT q.texto_pronto || chr(10) || chr(10) || '[INSTRUCAO: ' || q.instrucao_para_voce
              || ' Voce ia escalar sobre o imovel ' || v_cod || ', mas ele NAO disse esse '
              || 'codigo e voce nao mandou esse card para ele. NAO escale ainda: '
              || 'confirme qual e o imovel primeiro.]'
         FROM nay_qual_imovel(p_telefone) q),
      NULL::integer;
    RETURN;
  END IF;

  -- PAREDE 3: o que o Tel JA explicou deste imovel nao volta a virar
  -- pendencia. `pendencias.resposta` so reusa com redacao parecida
  -- (word_similarity >= 0.5); `imovel_conhecimento` guarda por ASSUNTO, e
  -- "esta quitado?", "aceita financiamento?" e "quanto pra entrar?" sao a
  -- mesma coisa com tres redacoes. Ver conhecimento_do_imovel.sql.
  IF v_cod IS NOT NULL THEN
    SELECT k.texto_pronto INTO v_resp
      FROM nay_o_que_sei_do_imovel(v_cod, v_ass || ' ' || coalesce(p_disse,'')) k
     WHERE k.sabe;
    IF v_resp IS NOT NULL THEN
      RETURN QUERY SELECT
        'responder'::text,
        ('ATENCAO: o Tel ja explicou isso deste imovel. A informacao e: ' || v_resp ||
         ' -- Responda ao corretor agora com ela, no seu tom, sem dizer que '
         || 'consultou ninguem e sem dizer que vai verificar.')::text,
        NULL::integer;
      RETURN;
    END IF;
  END IF;

  SELECT p.resposta INTO v_resp
    FROM pendencias p
   WHERE p.status = 'respondida'
     AND p.resposta IS NOT NULL
     AND v_cod IS NOT NULL AND p.codigo = v_cod  -- resposta so vale para O MESMO imovel:
     -- codigo nulo dos dois lados casava com qualquer um (corrigido 31/08)
     AND word_similarity(unaccent(lower(v_ass)), unaccent(lower(p.o_que_falta))) >= 0.5
   ORDER BY word_similarity(unaccent(lower(v_ass)), unaccent(lower(p.o_que_falta))) DESC,
            p.respondida_em DESC
   LIMIT 1;

  -- Resposta antiga que contenha numero de unidade nao e reusada, mesmo
  -- que tenha sido gravada antes desta parede existir.
  IF v_resp IS NOT NULL AND nay_tem_numero_de_unidade(v_resp) THEN
    v_resp := NULL;
  END IF;

  IF v_resp IS NOT NULL THEN
    RETURN QUERY SELECT
      'responder'::text,
      ('ATENCAO: o Tel ja respondeu isso antes. A resposta e: ' || v_resp ||
       ' -- Responda ao corretor agora com essa informacao, no seu tom, sem dizer que consultou ninguem e sem dizer que vai verificar.')::text,
      NULL::integer;
    RETURN;
  END IF;

  SELECT p.id INTO v_aberta
    FROM pendencias p
   WHERE p.status = 'aberta'
     -- CODIGO CONHECIDO E IGUAL nos dois lados. Antes era
     -- `IS NOT DISTINCT FROM`, e nulo casava com nulo -- o que ate 31/08
     -- so gerava pendencia repetida. Desde 01/09 o custo e outro: a
     -- pendencia casada entra em `pendencia_interessado`, e ao responder,
     -- `resposta_a_entregar` MANDA para todos da lista. Duas perguntas sem
     -- codigo, de corretores diferentes, sobre imoveis diferentes, casando
     -- so por similaridade de texto -- e a resposta de um sai para o
     -- outro. Sem codigo, cada um fica com a sua.
     AND v_cod IS NOT NULL AND p.codigo = v_cod
     AND word_similarity(unaccent(lower(v_ass)), unaccent(lower(p.o_que_falta))) >= 0.5
   ORDER BY p.criada_em DESC
   LIMIT 1;

  IF v_aberta IS NOT NULL THEN
    -- O SEGUNDO que pergunta a mesma coisa entra na lista de quem espera.
    -- Sem isto ele ouvia "estou verificando" e sumia do registro: quando o
    -- Tel respondia, só o primeiro recebia. Ver pendencia_ciclo.sql.
    PERFORM nay_anotar_interessado(v_aberta, p_telefone, p_nome);

    RETURN QUERY SELECT
      'esperar'::text,
      ('ATENCAO: isso ja foi levado ao Tel e a resposta ainda nao voltou. Diga ao corretor, no seu tom, que voce ainda esta verificando e retorna assim que tiver. NAO escale de novo. NAO invente a resposta. Pendencia numero ' || v_aberta || '.')::text,
      v_aberta;
    RETURN;
  END IF;

  INSERT INTO pendencias (codigo, o_que_falta, de_quem, avisar, status, criada_em)
  VALUES (v_cod, v_ass, 'tel', p_telefone, 'aberta', now())
  RETURNING id INTO v_id;

  INSERT INTO escalacoes (telefone, nome, assunto, disse, status, criada_em)
  VALUES (p_telefone, p_nome, v_ass, p_disse, 'aberta', now());

  -- O primeiro entra na mesma lista dos outros, para não existirem duas
  -- noções de "quem perguntou" -- `pendencias.avisar` e a lista.
  PERFORM nay_anotar_interessado(v_id, p_telefone, p_nome);

  RETURN QUERY SELECT
    'escalar'::text,
    ('ATENCAO: o Tel acabou de ser avisado. Diga ao corretor, no seu tom, que voce vai verificar e retorna. Diga isso UMA VEZ SO. Se ele insistir, apenas confirme que ainda esta verificando. NAO invente a resposta e NAO prometa prazo. Pendencia numero ' || v_id
     -- O TEL PRECISA VER DE QUE IMOVEL SE TRATA. O aviso dizia so o
     -- assunto ("quitacao e entrada") e o Tel tinha que ir ao banco
     -- descobrir o resto. Achado na auditoria de 01/09.
     || CASE WHEN v_cod IS NOT NULL THEN ' (imovel ' || v_cod
             || coalesce(' — ' || (SELECT coalesce(NULLIF(i.condominio_nome,''), i.tipo)
                                     FROM imoveis i WHERE i.codigo::text = v_cod), '')
             || ')'
             ELSE ' (imovel NAO identificado — a resposta do Tel nao vai virar '
                  || 'conhecimento reusavel, de proposito)' END
     || '.')::text,
    v_id;
END;
$function$

