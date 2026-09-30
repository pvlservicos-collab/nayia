-- A resposta que o Tel dá pelo comando `RESPOSTA <id>` vira conhecimento
-- do imóvel -- e o VENDEU/ALUGOU esquece os DOIS lugares onde ela mora.
--
-- O BURACO (auditoria de 01/09). `imovel_conhecimento` foi criada para o
-- laço "o Tel explica uma vez, ela não pergunta mais", e a única escrita
-- nela era a ferramenta `guardar_do_imovel`, do agente. Só que o nó
-- `Rotear para o agente` DESCARTA toda mensagem do Tel que case com a
-- gramática de pendência -- `RESPOSTA <id> <texto>` inclusive, que o
-- CLAUDE.md chama de "o caminho à prova de tudo". Ou seja: o caminho que
-- o Tel de fato usa nunca chegava ao agente, o agente nunca chamava a
-- ferramenta, e o laço só fechava se ele explicasse em conversa solta.
--
-- O reuso continuava caindo só em `pendencias.resposta`, que exige
-- `word_similarity >= 0.5` sobre a redação da pergunta -- e "está
-- quitado?", "aceita financiamento?" e "quanto pra entrar?" são a mesma
-- coisa em três redações. O assunto canônico existe exatamente para isso.
--
-- O SEGUNDO BURACO, no outro extremo: `nay_esquecer_imovel` limpava
-- `imovel_conhecimento` no VENDEU/ALUGOU -- "conhecimento de imóvel
-- vendido, reusado depois, é pior que conhecimento nenhum" -- mas
-- `pendencias.resposta` guarda a MESMA informação e ninguém a tocava.
-- Depois de um ALUGOU ela esquecia a explicação de caução e continuava
-- respondendo a mesma coisa, com a mesma certeza, a partir da pendência
-- antiga de um imóvel que já saiu do mercado.
--
-- A ASSINATURA de `nay_responder_pendencia` está preservada byte a byte:
-- `nay_comando` faz `SELECT * INTO` dela, e mexer nas colunas quebraria o
-- `RESPOSTA` do Tel. O que muda é só o corpo.
--
--   docker cp resposta_vira_conhecimento.sql nay-postgres:/tmp/rc.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/rc.sql

-- A gravação mora numa função à parte por um motivo bobo e real: dentro
-- de `nay_responder_pendencia` a coluna `codigo` colide com a coluna de
-- saída de mesmo nome, e o `ON CONFLICT (codigo, assunto)` não compila.
CREATE OR REPLACE FUNCTION nay_gravar_conhecimento(
  p_codigo text, p_assunto text, p_texto text, p_quem text
) RETURNS void
LANGUAGE sql AS $fn$
  INSERT INTO imovel_conhecimento (codigo, assunto, texto, quem_contou)
  VALUES (p_codigo, p_assunto, p_texto, p_quem)
  ON CONFLICT (codigo, assunto) DO UPDATE
     SET texto = EXCLUDED.texto,
         quem_contou = EXCLUDED.quem_contou,
         atualizado_em = now();
$fn$;

CREATE OR REPLACE FUNCTION nay_responder_pendencia(p_id integer, p_resposta text)
RETURNS TABLE(ok boolean, avisar text, codigo text, assunto text)
LANGUAGE plpgsql AS $fn$
DECLARE
  r record;
  v_texto text;
  v_outros int;
  v_esperando int := 0;
  v_ass text;
BEGIN
  UPDATE pendencias p
     SET resposta = p_resposta, status = 'respondida', respondida_em = now()
   WHERE p.id = p_id AND p.status = 'aberta'
  RETURNING p.avisar, p.codigo, p.o_que_falta INTO r;

  IF r IS NULL THEN
    RETURN QUERY SELECT false, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  UPDATE escalacoes e SET status = 'resolvida', resolvida_em = now()
   WHERE e.status = 'aberta' AND e.telefone = r.avisar AND e.assunto = r.o_que_falta;

  -- ---------------------------------------------------------------
  -- O QUE ELE ACABOU DE ENSINAR FICA SABIDO, por assunto.
  --
  -- Só com código: resposta sem imóvel não é reusável, e a regra de 31/08
  -- (código nulo era curinga e casava com qualquer imóvel) vale aqui
  -- igual. E nunca com número de unidade dentro -- é a mesma parede do
  -- leque logo abaixo, pelo mesmo motivo: gravado, seria reusado para
  -- sempre naquele imóvel.
  IF r.codigo IS NOT NULL AND NOT nay_tem_numero_de_unidade(p_resposta) THEN
    v_ass := coalesce(nay_assunto_do_imovel(r.o_que_falta),
                      nay_assunto_do_imovel(p_resposta));
    IF v_ass IS NOT NULL THEN
      PERFORM nay_gravar_conhecimento(r.codigo, v_ass, btrim(p_resposta),
                                      'tel (RESPOSTA ' || p_id || ')');
    END IF;
  END IF;

  -- Quem mais perguntou a mesma coisa e ficou esperando em silêncio.
  v_texto := 'Sobre ' ||
             CASE WHEN r.codigo IS NOT NULL THEN 'o ' || r.codigo ELSE 'o que você perguntou' END
             || ': ' || p_resposta;

  -- O LEQUE NAO CARREGA NUMERO DE UNIDADE.
  --
  -- Responder UM corretor e decisao do Tel, e ele pode ter motivo -- o
  -- cara vai fazer a visita hoje. Mandar para os OUTROS e automatico,
  -- ninguem revisa, e a lista pode ter gente que ele nem lembra que
  -- perguntou. Aqui o padrao e negar. Achado no red team de 01/09.
  IF nay_tem_numero_de_unidade(p_resposta) THEN
    v_outros := -1;   -- sinaliza que houve gente esperando e NAO recebeu
    SELECT count(*) INTO v_esperando
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8);
  ELSE
    INSERT INTO resposta_a_entregar (pendencia_id, telefone, texto)
    SELECT p_id, i.telefone, v_texto
      FROM pendencia_interessado i
     WHERE i.pendencia_id = p_id
       AND right(regexp_replace(i.telefone,'[^0-9]','','g'),8)
         <> right(regexp_replace(coalesce(r.avisar,''),'[^0-9]','','g'),8)
    ON CONFLICT DO NOTHING;
    GET DIAGNOSTICS v_outros = ROW_COUNT;
  END IF;

  -- O Tel PRECISA saber que o leque nao saiu, senao ele acha que os
  -- outros foram avisados.
  RETURN QUERY SELECT true, r.avisar, r.codigo,
    r.o_que_falta || CASE WHEN v_outros = -1 AND v_esperando > 0
      THEN ' [ATENCAO: sua resposta tem numero de unidade, entao NAO foi '
           || 'repassada aos outros ' || v_esperando || ' corretor(es) que '
           || 'esperavam. So quem perguntou primeiro recebeu.]'
      ELSE '' END;
END;
$fn$;

-- --------------------------------------------------------------------
-- Esquecer o imóvel é esquecer nos DOIS lugares.
--
-- A linha da pendência não é removida -- só o reuso, exatamente como o
-- `DESCARTAR` já faz para uma pendência só.
CREATE OR REPLACE FUNCTION nay_esquecer_imovel(p_codigo text)
RETURNS int
LANGUAGE plpgsql AS $fn$
DECLARE
  v_cod text := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'');
  n int;
  m int;
BEGIN
  DELETE FROM imovel_conhecimento WHERE codigo = v_cod;
  GET DIAGNOSTICS n = ROW_COUNT;

  UPDATE pendencias SET resposta = NULL
   WHERE codigo = v_cod AND resposta IS NOT NULL;
  GET DIAGNOSTICS m = ROW_COUNT;

  RETURN n + m;
END;
$fn$;
