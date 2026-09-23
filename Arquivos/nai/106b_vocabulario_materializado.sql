-- =====================================================================
-- NAI -- 106b: o filtro de palavras tem que ser barato (23/09/2026)
--
-- A primeira versao levava 1,58 SEGUNDO numa mensagem de 50 palavras. Nao da:
-- isso entra no caminho de TODA mensagem que chega.
--
-- ONDE ESTAVA O CUSTO: o vocabulario era uma VIEW em cima de
-- `vw_condominio_som`, que recalcula a chave de som dos 1.248 imoveis. Isso
-- rodava de novo a cada janela de palavras -- umas 90 vezes por mensagem.
--
-- AGORA: tabela materializada, com indice. O texto passa a ser corrigido em
-- milissegundos.
--
-- QUANDO ATUALIZA: uma vez por dia, junto da sincronizacao do catalogo, e
-- sempre que alguem rodar `SELECT nai_vocabulario_atualizar()`. Condominio
-- novo entra no filtro no dia seguinte -- e, se for urgente, um comando
-- resolve.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

DROP MATERIALIZED VIEW IF EXISTS mv_vocabulario_nomes;
CREATE MATERIALIZED VIEW mv_vocabulario_nomes AS
  SELECT nome, especie,
         array_length(regexp_split_to_array(btrim(nome), '\s+'), 1) AS palavras,
         length(nome) AS tamanho,
         lower(unaccent(nome)) AS chave
    FROM vw_vocabulario_nomes;

CREATE INDEX mv_vocabulario_palavras ON mv_vocabulario_nomes (palavras, tamanho);
CREATE INDEX mv_vocabulario_trgm ON mv_vocabulario_nomes USING gin (chave gin_trgm_ops);

CREATE OR REPLACE FUNCTION public.nai_vocabulario_atualizar()
 RETURNS integer LANGUAGE plpgsql
AS $function$
DECLARE n int;
BEGIN
  REFRESH MATERIALIZED VIEW mv_vocabulario_nomes;
  SELECT count(*) INTO n FROM mv_vocabulario_nomes;
  RETURN n;
END;
$function$;

CREATE OR REPLACE FUNCTION public.nai_corrigir_nomes(p_texto text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_palavras text[];
  v_saida    text[] := '{}';
  v_piso     real := coalesce(nullif(nai_cfg('piso_correcao_nome', '0.70'), ''), '0.70')::real;
  i          int := 1;
  n          int;
  j          int;
  v_janela   text;
  v_limpo    text;
  v_chave    text;
  v_certo    text;
  v_forca    real;
  v_folga    int;
  v_achou    boolean;
BEGIN
  IF btrim(coalesce(p_texto, '')) = '' THEN RETURN p_texto; END IF;
  v_palavras := regexp_split_to_array(p_texto, '\s+');
  n := coalesce(array_length(v_palavras, 1), 0);

  WHILE i <= n LOOP
    v_achou := false;
    -- JANELA GRANDE PRIMEIRO: "bom pedro" antes de "bom" e "pedro" soltos.
    FOR j IN REVERSE least(3, n - i + 1) .. 1 LOOP
      v_janela := array_to_string(v_palavras[i : i + j - 1], ' ');
      v_limpo  := btrim(regexp_replace(v_janela, '[^[:alnum:] ]', '', 'g'));
      v_chave  := lower(unaccent(v_limpo));
      CONTINUE WHEN length(regexp_replace(v_chave, '[^a-z0-9]', '', 'g')) < 5;
      CONTINUE WHEN j = 1 AND nai_palavra_comum(v_limpo);
      -- NOME PROPRIO NAO COMECA NEM TERMINA EM CONECTIVO. Sem esta linha,
      -- "na ponta negrra" (3 palavras) casava com o condominio "Luar Ponta
      -- Negra" e o "na" era engolido -- quando o certo era o bairro Ponta
      -- Negra, na janela de 2.
      CONTINUE WHEN j > 1 AND (
           lower(unaccent(regexp_replace(v_palavras[i], '[^[:alnum:]]', '', 'g'))) = ANY (ARRAY[
             'na','no','em','de','da','do','das','dos','a','o','as','os','um','uma','uns','umas',
             'para','pra','com','sem','por','pelo','pela','e','ou','que','se','ai','aqui','la',
             'ta','to','meu','minha','seu','sua','esse','essa','este','esta','tem','quero'])
        OR lower(unaccent(regexp_replace(v_palavras[i + j - 1], '[^[:alnum:]]', '', 'g'))) = ANY (ARRAY[
             'na','no','em','de','da','do','das','dos','a','o','as','os','um','uma','uns','umas',
             'para','pra','com','sem','por','pelo','pela','e','ou','que','se']));

      -- QUANTAS LETRAS PODEM ESTAR ERRADAS, no maximo. Sai do piso: com 0,70
      -- e uma palavra de 10 letras, cabem 3 erros. Passar isso ao
      -- `levenshtein_less_equal` faz ele desistir cedo, em vez de contar a
      -- distancia inteira de cada nome do catalogo.
      -- O TETO DA BUSCA e folgado de proposito: a conta final compara com o
      -- MAIOR dos dois nomes, entao "aquareli" (8) x "Acquarelle" (10) aceita
      -- 3 letras erradas, e nao 2. Calculando a folga so pela palavra dita,
      -- esse caso ficava de fora por um caractere.
      v_folga := floor((1.0 - v_piso) * (length(v_chave) + 4))::int + 1;

      -- CUIDADO COM O `less_equal`: quando a distancia passa do teto, ele NAO
      -- devolve a distancia -- devolve um numero maior que o teto. Usar esse
      -- numero na conta como se fosse a distancia real fez "bem estou com"
      -- virar "porto marina taua" no primeiro teste. Por isso a linha
      -- `WHERE x.d <= ...`: so vale quem ficou DENTRO do teto de verdade.
      SELECT x.nome, x.forca INTO v_certo, v_forca FROM (
        SELECT v.nome, v.tamanho,
               levenshtein_less_equal(v.chave, v_chave, v_folga) AS d,
               1.0 - levenshtein_less_equal(v.chave, v_chave, v_folga)::real
                     / greatest(v.tamanho, length(v_chave), 1) AS forca
          FROM mv_vocabulario_nomes v
         WHERE v.palavras = j
           -- nome de tamanho muito diferente nao tem como estar a 70%
           AND v.tamanho BETWEEN length(v_chave) - v_folga AND length(v_chave) + v_folga
        ) x
       -- a conta exata do piso, por linha: ate aqui o teto acima era so
       -- para o `less_equal` desistir cedo.
       WHERE x.d <= floor((1.0 - v_piso) * greatest(x.tamanho, length(v_chave), 1))
       ORDER BY x.forca DESC LIMIT 1;

      IF v_certo IS NOT NULL AND v_forca >= v_piso THEN
        IF v_chave = lower(unaccent(v_certo)) THEN
          v_saida := v_saida || v_palavras[i : i + j - 1];
        ELSE
          -- a pontuacao do fim da janela volta junto ("dom pedro," fica com a virgula)
          v_saida := v_saida || (v_certo || coalesce((regexp_match(v_palavras[i + j - 1], '([^[:alnum:]]+)$'))[1], ''));
        END IF;
        i := i + j;
        v_achou := true;
        EXIT;
      END IF;
    END LOOP;

    IF NOT v_achou THEN
      v_saida := v_saida || v_palavras[i];
      i := i + 1;
    END IF;
  END LOOP;

  RETURN array_to_string(v_saida, ' ');
END;
$function$;

GRANT SELECT ON mv_vocabulario_nomes TO nay_site_nai, nay_leitura;

COMMIT;

SELECT 'palavras no vocabulario' AS o, count(*)::text FROM mv_vocabulario_nomes;
