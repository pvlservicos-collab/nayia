-- O corretor escreve "taruma", o banco guarda "Tarumã", e a Nay diz que
-- não temos imóvel. Sobre um terço do catálogo.
--
-- A CONTA (31/08): 394 dos 1.172 imóveis moram em bairro com acento ou
-- número -- Adrianópolis (84), Parque 10 de Novembro (78), Tarumã (72),
-- Tarumã-Açu (43), Nossa Senhora das Graças (35), Colônia Terra Nova (29).
-- `nay_buscar_por_perfil` comparava com ILIKE cru, então quem digitava sem
-- acento ouvia "não temos imóvel disponível nesse perfil no momento" --
-- uma mentira, e ainda escalava ao Tel como demanda não atendida.
--
-- POR QUE `unaccent` SOZINHO NÃO BASTA: ninguém digita "Parque 10 de
-- Novembro". Digita "parque dez", "pq 10", "pq dez". Acento é só metade
-- do problema; a outra metade é como as pessoas escrevem de verdade.
--
-- A SEGUNDA MENTIRA, e é pior: bairro que não existe no catálogo dava a
-- MESMA resposta de bairro que existe e está sem imóvel. "Não temos nesse
-- perfil" para quem escreveu "Ponta Negrra" mandava o Tel atrás de uma
-- demanda que nunca houve. Agora ela sabe distinguir os dois casos.
--
--   docker cp bairro_sem_acento.sql nay-postgres:/tmp/ba.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/ba.sql

CREATE EXTENSION IF NOT EXISTS unaccent;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Deixa os dois lados na mesma língua: sem acento, minúsculo, sem
-- pontuação, com as abreviações abertas e os números por extenso viram
-- dígito. Vale para o que o corretor digitou E para o que está no banco.
CREATE OR REPLACE FUNCTION nay_normalizar_lugar(p_texto text)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT btrim(regexp_replace(
    regexp_replace(
      -- as abreviações que aparecem de verdade nas mensagens
      regexp_replace(
        regexp_replace(lower(unaccent(coalesce(p_texto,''))),
                       '[^a-z0-9]+', ' ', 'g'),
        '\m(pq|pque)\M', 'parque', 'g'),
      '\m(dez)\M', '10', 'g'),
    '\s+', ' ', 'g'));
$fn$;

-- As demais, aplicadas em cima da primeira. Separadas por legibilidade;
-- cada uma nasceu de uma forma que alguém escreveu.
CREATE OR REPLACE FUNCTION nay_normalizar_lugar(p_texto text, p_fundo boolean)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT btrim(regexp_replace(regexp_replace(regexp_replace(regexp_replace(
    regexp_replace(regexp_replace(nay_normalizar_lugar(p_texto),
      '\m(quatorze|catorze)\M', '14', 'g'),
      '\m(sto)\M', 'santo', 'g'),
      '\m(sta)\M', 'santa', 'g'),
      '\m(cj|conj)\M', 'conjunto', 'g'),
      '\m(jd)\M', 'jardim', 'g'),
      '\s+', ' ', 'g'));
$fn$;

-- --------------------------------------------------------------------
-- Depois de não achar nada: o bairro existe no catálogo?
--
-- Devolve o nome do bairro mais parecido que TEM imóvel, ou NULL quando
-- nem parecido existe. É o que separa "esse bairro está sem imóvel agora"
-- de "esse bairro não é nosso" -- duas conversas diferentes, e a segunda
-- não é demanda não atendida.
CREATE OR REPLACE FUNCTION nay_bairro_parecido(p_bairro text)
RETURNS text
LANGUAGE sql STABLE AS $fn$
  SELECT i.bairro
    FROM imoveis i
   WHERE coalesce(i.disponivel, true)
     AND coalesce(i.bairro,'') <> ''
     AND similarity(nay_normalizar_lugar(i.bairro, true),
                    nay_normalizar_lugar(p_bairro, true)) > 0.4
   GROUP BY i.bairro
   ORDER BY max(similarity(nay_normalizar_lugar(i.bairro, true),
                           nay_normalizar_lugar(p_bairro, true))) DESC,
            count(*) DESC
   LIMIT 1;
$fn$;
