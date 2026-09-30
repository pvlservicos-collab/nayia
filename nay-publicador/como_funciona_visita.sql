-- Como funciona a visita, imóvel por imóvel: a Nay lê, e quando não sabe,
-- aprende com o Tel e guarda.
--
-- O PROBLEMA (dito pelo Tel em 29/08): "cada proprietário tem situações
-- diferentes que ela vai precisar ver dentro da ficha do imóvel como
-- funciona a visita. O que estiver vazio ela me pergunta." Se tem chave
-- com a gente, se é fechadura eletrônica, se precisa agendar com o dono,
-- se ele autoriza a entrada no condomínio -- muda por imóvel, e hoje isso
-- não existe em lugar nenhum: está só na cabeça do Tel.
--
-- ONDE MORA: `imovel_privado`, não `imoveis`. É a tabela privada, fora do
-- alcance das ferramentas de corretor por decisão de arquitetura ("dado de
-- proprietário em tabela separada, sem acesso da ferramenta de corretor" --
-- regra no prompt é pedido, separação no banco é parede). Coluna própria em
-- vez de `notas` porque `notas` já tem conteúdo em 619 dos 1.172.
--
-- A VARREDURA NÃO APAGA: `gerar_sql_atualizacao.py` só toca `imoveis`, e
-- nem `imovel_privado` nem esta coluna aparecem nas listas de UPDATE/INSERT.
--
-- Rodar no servidor:
--   docker cp como_funciona_visita.sql nay-postgres:/tmp/cfv.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/cfv.sql

ALTER TABLE imovel_privado
  ADD COLUMN IF NOT EXISTS como_funciona_visita text,
  ADD COLUMN IF NOT EXISTS visita_atualizada_em timestamptz;

-- ---------------------------------------------------------------- leitura
-- Devolve texto_pronto no padrão das outras ferramentas: a consulta decide
-- o que ela diz, o modelo não pondera.
CREATE OR REPLACE FUNCTION nay_como_funciona_visita(p_codigo text)
RETURNS TABLE(texto_pronto text, sabe boolean)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_cod int := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'')::int;
  v_txt text;
  v_existe boolean;
BEGIN
  IF v_cod IS NULL THEN
    RETURN QUERY SELECT
      'nao entendi de qual imovel voce fala. peca o codigo ao corretor.'::text, false;
    RETURN;
  END IF;

  -- RASPADO. A ficha é texto livre que o Tel digita, e a coisa mais
  -- natural de escrever ali é "chave com o porteiro, apartamento 401" --
  -- que sairia direto ao corretor, furando por dentro a parede que a
  -- pergunta direta não fura. Ver unidade_nunca.sql. Hoje a tabela está
  -- vazia: o conserto é preventivo, e é agora que custa barato.
  SELECT true, btrim(coalesce(nay_descricao_segura(p.como_funciona_visita),''))
    INTO v_existe, v_txt
    FROM imovel_privado p WHERE p.codigo = v_cod;

  IF NOT coalesce(v_existe,false) THEN
    RETURN QUERY SELECT
      ('nao existe ficha privada do imovel ' || v_cod ||
       '. pergunte ao Tel como funciona a visita nesse imovel e guarde a resposta.')::text,
      false;
    RETURN;
  END IF;

  IF coalesce(v_txt,'') = '' THEN
    RETURN QUERY SELECT
      ('ainda nao esta registrado como funciona a visita no imovel ' || v_cod ||
       '. NAO invente e NAO diga ao corretor que tem chave nem que precisa agendar. ' ||
       'Pergunte ao Tel: como funciona a visita no ' || v_cod ||
       '? tem chave com a gente, e fechadura eletronica, precisa agendar com o proprietario? ' ||
       'Quando ele responder, chame guardar_como_funciona_a_visita na MESMA resposta.')::text,
      false;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('assim funciona a visita no imovel ' || v_cod || ': ' || v_txt ||
     ' -- use isso para conduzir, e nao repita ao corretor o que nao interessar a ele.')::text,
    true;
END;
$fn$;

-- ----------------------------------------------------------------- escrita
-- Só o Tel escreve. O telefone vem do FLUXO, não do modelo -- mesma parede
-- do `nay_responder_conversando`: o modelo não consegue forjar quem falou.
CREATE OR REPLACE FUNCTION nay_guardar_como_funciona_visita(
  p_codigo   text,
  p_texto    text,
  p_telefone text
) RETURNS TABLE(texto_pronto text)
LANGUAGE plpgsql AS $fn$
DECLARE
  v_cod int := NULLIF(regexp_replace(coalesce(p_codigo,''),'[^0-9]','','g'),'')::int;
  v_tel text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_txt text := btrim(coalesce(p_texto,''));
  v_n   int;
BEGIN
  -- A parede: quem não é o Tel não grava, mesmo que o modelo tente.
  IF v_tel <> '559294717316' THEN
    RETURN QUERY SELECT
      'so o Tel pode registrar como funciona a visita. nao grave nada e nao diga que gravou.'::text;
    RETURN;
  END IF;

  IF v_cod IS NULL OR v_txt = '' THEN
    RETURN QUERY SELECT
      'faltou o codigo do imovel ou o texto. pergunte ao Tel de qual imovel e como funciona.'::text;
    RETURN;
  END IF;

  IF length(v_txt) > 600 THEN
    RETURN QUERY SELECT
      'esse texto ficou longo demais. peca ao Tel para resumir como funciona a visita.'::text;
    RETURN;
  END IF;

  INSERT INTO imovel_privado (codigo, como_funciona_visita, visita_atualizada_em)
       VALUES (v_cod, v_txt, now())
  ON CONFLICT (codigo) DO UPDATE
       SET como_funciona_visita = EXCLUDED.como_funciona_visita,
           visita_atualizada_em = now();
  GET DIAGNOSTICS v_n = ROW_COUNT;

  IF v_n = 0 THEN
    RETURN QUERY SELECT
      ('nao consegui guardar no imovel ' || v_cod || '. avise o Tel.')::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    ('guardei como funciona a visita no imovel ' || v_cod ||
     '. diga ao Tel que anotou e que nao vai perguntar de novo.')::text;
END;
$fn$;
