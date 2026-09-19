-- O que o site não diz, e o Tel só precisa dizer UMA vez.
--
-- OS DOIS CASOS (01/09), nas palavras do Tel:
--
--   Gustavo perguntou se o Harmonia está quitado e qual o valor de
--   entrada. "é uma informação que não está no site e ela precisa me
--   perguntar e deixar gravado que é informação que outro corretor pode
--   perguntar e só apagar quando o imóvel não estiver disponível."
--
--   Uma corretora perguntou as condições de locação da casa do Nova
--   Cidade e o Tel respondeu à mão: caução, renda, restrições, aluguel
--   antecipado. "essa informação a Nay pode ter gravada até alugar a casa
--   do nova cidade e ela aprender sobre a situação do imóvel."
--
-- POR QUE NÃO BASTAVA `pendencias.resposta`: aquele reuso exige uma
-- pergunta PARECIDA (`word_similarity >= 0.5`) no MESMO imóvel. "está
-- quitado?" e "aceita financiamento?" e "quanto preciso pra entrar?" são
-- a mesma informação com três redações, e o casamento por texto não junta
-- as três. Aqui o conhecimento é guardado por ASSUNTO, e o assunto é uma
-- lista curta e fixa.
--
-- APAGA SOZINHO quando o imóvel sai da carteira: `nay_esquecer_imovel` é
-- chamada pelo VENDEU/ALUGOU. Conhecimento de imóvel vendido, reusado
-- depois, é pior que conhecimento nenhum.
--
--   docker cp conhecimento_do_imovel.sql nay-postgres:/tmp/ci.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ci.sql

CREATE TABLE IF NOT EXISTS imovel_conhecimento (
  id           bigserial PRIMARY KEY,
  codigo       text NOT NULL,
  assunto      text NOT NULL,
  texto        text NOT NULL,
  quem_contou  text,
  criado_em    timestamptz NOT NULL DEFAULT now(),
  atualizado_em timestamptz NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS conhecimento_um_por_assunto
  ON imovel_conhecimento (codigo, assunto);

-- --------------------------------------------------------------------
-- Os assuntos. Lista CURTA e fixa de propósito: assunto livre viraria
-- vinte redações da mesma coisa e o reuso não acharia nenhuma.
--
-- A normalização mapeia as formas que o corretor usa para o assunto
-- canônico -- é o mesmo problema do bairro sem acento, resolvido do
-- mesmo jeito.
CREATE OR REPLACE FUNCTION nay_assunto_do_imovel(p_texto text)
RETURNS text
LANGUAGE sql IMMUTABLE AS $fn$
  SELECT CASE
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(quitad|quitacao|financiad|financiamento|escritura|habite|documenta)'
      THEN 'quitacao'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(entrada|sinal|quanto.{0,15}(pra|para).{0,10}entrar|saldo devedor|gaveta|parcela)'
      THEN 'entrada'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~
         '(cauc|deposito|garantia|fiador|seguro fianca|renda|restric|serasa|spc|analise|antecipad)'
      THEN 'condicoes_locacao'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(pet|animal|cachorro|gato)'
      THEN 'pet'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(mobili|modulad|planejad|movei)'
      THEN 'mobilia'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(reforma|estado|conservacao|pintura)'
      THEN 'estado'
    WHEN lower(unaccent(coalesce(p_texto,''))) ~ '(negociad|proposta|reservad|em analise)'
      THEN 'situacao'
    ELSE NULL
  END;
$fn$;

-- --------------------------------------------------------------------
-- O que já se sabe deste imóvel. Chamada ANTES de escalar.
CREATE OR REPLACE FUNCTION nay_o_que_sei_do_imovel(
  p_codigo text, p_pergunta text DEFAULT NULL
) RETURNS TABLE(texto_pronto text, sabe boolean, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_cod  text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_ass  text := nay_assunto_do_imovel(p_pergunta);
  v_txt  text;
  v_tudo text;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT ''::text, false,
      'sem codigo nao da para consultar. Descubra o imovel primeiro.'::text;
    RETURN;
  END IF;

  -- O assunto exato, quando dá para reconhecer a pergunta.
  IF v_ass IS NOT NULL THEN
    SELECT c.texto INTO v_txt FROM imovel_conhecimento c
     WHERE c.codigo = v_cod AND c.assunto = v_ass;
    IF v_txt IS NOT NULL THEN
      RETURN QUERY SELECT v_txt, true,
        ('o Tel ja explicou isso deste imovel. Responda AGORA com essa '
         || 'informacao, no seu tom. NAO escale e NAO diga que vai '
         || 'verificar.')::text;
      RETURN;
    END IF;
  END IF;

  -- Não sabe o assunto perguntado, mas talvez saiba outras coisas do
  -- imóvel -- e isso vale para ela não escalar o que já está ali.
  SELECT string_agg('• ' || c.assunto || ': ' || c.texto, chr(10) ORDER BY c.assunto)
    INTO v_tudo FROM imovel_conhecimento c WHERE c.codigo = v_cod;

  IF v_tudo IS NULL THEN
    RETURN QUERY SELECT ''::text, false,
      ('nao sei nada alem da ficha sobre o imovel ' || v_cod || '. Se a '
       || 'pergunta nao e respondida pela ficha nem pela descricao, escale ao '
       || 'Tel COM o codigo -- a resposta dele fica gravada e serve para o '
       || 'proximo corretor.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT v_tudo, false,
    ('nao sei exatamente o que ele perguntou, mas sei isto do imovel ' || v_cod
     || '. Use se responder; se nao responder, escale COM o codigo.')::text;
END;
$fn$;

-- --------------------------------------------------------------------
-- O Tel ensina. SÓ o Tel: o telefone vem do fluxo, não do modelo -- a
-- mesma parede do `nay_guardar_como_funciona_visita`.
CREATE OR REPLACE FUNCTION nay_guardar_do_imovel(
  p_codigo text, p_assunto text, p_texto text, p_telefone text
) RETURNS text
LANGUAGE plpgsql AS $fn$
DECLARE
  v_cod text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  v_tel text := right(regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g'),8);
  v_ass text := coalesce(nay_assunto_do_imovel(p_assunto),
                         nay_assunto_do_imovel(p_texto));
  v_txt text := btrim(coalesce(p_texto,''));
BEGIN
  -- PAREDE: só o Tel grava. Corretor ensinando a Nay contaminaria o
  -- conhecimento de todo mundo naquele imóvel.
  IF v_tel <> '94717316' THEN
    RETURN 'so o Tel pode gravar informacao de imovel. NAO diga que guardou.';
  END IF;
  IF v_cod IS NULL OR v_txt = '' THEN
    RETURN 'preciso do codigo do imovel e do texto. Nao gravei nada.';
  END IF;
  IF v_ass IS NULL THEN
    RETURN 'nao reconheci o assunto. Os assuntos sao: quitacao, entrada, '
        || 'condicoes_locacao, pet, mobilia, estado, situacao.';
  END IF;
  -- Imóvel fora da carteira não recebe conhecimento novo.
  IF NOT EXISTS (SELECT 1 FROM imoveis i
                  WHERE i.codigo::text = v_cod AND coalesce(i.disponivel, true)) THEN
    RETURN 'o imovel ' || v_cod || ' nao esta disponivel. Nao gravei.';
  END IF;

  INSERT INTO imovel_conhecimento (codigo, assunto, texto, quem_contou)
  VALUES (v_cod, v_ass, v_txt, 'tel')
  ON CONFLICT (codigo, assunto) DO UPDATE
     SET texto = EXCLUDED.texto, atualizado_em = now();

  RETURN 'guardei: ' || v_ass || ' do imovel ' || v_cod
      || '. Da proxima vez que perguntarem isso desse imovel, eu respondo sozinha.';
END;
$fn$;

-- --------------------------------------------------------------------
-- Imóvel que saiu da carteira esquece tudo. Chamada pelo VENDEU/ALUGOU.
--
-- Conhecimento de imóvel vendido, reusado depois, é pior que
-- conhecimento nenhum: a informação parece atual e não é.
CREATE OR REPLACE FUNCTION nay_esquecer_imovel(p_codigo text)
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE n int;
BEGIN
  DELETE FROM imovel_conhecimento
   WHERE codigo = NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END;
$fn$;
