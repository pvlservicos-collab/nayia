-- =====================================================================
-- NAI -- 88: "aquarele" tambem e o Acquarelle (Tel, 22/09/2026)
--
-- A Lily mandou AUDIO: "O teu aquarele para locacao ainda esta disponivel? O
-- de uma suite?". A transcricao saiu certa -- o audio e lido, isso funciona --
-- mas o reconhecedor de condominio compara letra por letra, e "aquarele" nao
-- e "Acquarelle". A porta ficou fechada e a Nay nao respondeu, sendo que ela
-- pediu imovel com todas as letras. Mesmo caso da Marlucia (arquivo 86), so
-- que agora quem erra a grafia e o audio.
--
-- A CHAVE DE SOM: uma versao "de ouvido" do nome, que a busca usa dos dois
-- lados. Tira acento, junta tudo, e nivela o que o portugues escreve de mais
-- de um jeito para o mesmo som:
--     qu/c/k -> k    ss/c(e,i)/ç -> s    ph -> f    y -> i    h some
--     letra dobrada -> uma so
--   "Condominio Acquarelle" -> "akuarele"      "aquarele"  -> "akuarele"
--   "Mirante Das Flores"    -> "mirantedaflore" (o s final de plural cai junto
--                              na dobra, e isso nao atrapalha: os dois lados
--                              passam pela mesma regra)
--
-- O piso sobe para 7 letras NA CHAVE (nome curto vira chave curta e casaria
-- com qualquer frase), e o nome que e tipo de imovel continua fora.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_chave_som(p_texto text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT regexp_replace(
           regexp_replace(
             regexp_replace(
               regexp_replace(
                 regexp_replace(
                   regexp_replace(lower(unaccent(coalesce(p_texto, ''))), '[^a-z]', '', 'g'),
                 'ph', 'f', 'g'),
               '(qu|q|c|k)', 'k', 'g'),
             '(ss|z|x)', 's', 'g'),
           '(y|h|w)', 'i', 'g'),
         '(.)\1+', '\1', 'g');
$function$;

CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- CARD SEM CODIGO (Tel, 16/09): o nome do condominio basta.
  -- VENDA CONTA (Tel, 16/09): por isso aqui nao entra `nai_oferta_serve`.
  -- NOME QUE E TIPO NAO CONTA: "Apartamento", "Casa", "Predio", "Flat".
  -- O NUCLEO VALE (86): no cadastro "Condominio Acquarelle", na boca dele
  --   "Acquarelle".
  -- E A CHAVE DE SOM VALE (88): "aquarele", do audio da Lily, tambem e o
  --   Acquarelle. Compara os dois lados pela mesma regra de escrita.
  SELECT coalesce(array_agg(DISTINCT i.codigo), '{}')
    FROM imoveis i
   WHERE nai_condominio_ok(i.condominio_nome) IS NOT NULL
     AND nai_condominio_ok(i.condominio_nome) !~ '/'
     AND lower(unaccent(nai_condominio_ok(i.condominio_nome))) NOT IN (
           SELECT lower(unaccent(x.tipo)) FROM imoveis x WHERE x.tipo IS NOT NULL)
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND (
       -- 1. o nome inteiro, como esta no cadastro
       (length(nai_condominio_ok(i.condominio_nome)) >= 8
        AND position(lower(unaccent(nai_condominio_ok(i.condominio_nome)))
                     IN lower(unaccent(coalesce(p_texto, '')))) > 0)
       -- 2. o nucleo, sem Condominio/Residencial/Edificio
       OR (length(coalesce(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)), '')) >= 8
           AND lower(unaccent(coalesce(p_texto, ''))) ~
               ('\m' || regexp_replace(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)),
                                       '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\M'))
       -- 3. a chave de som do nucleo (audio, erro de digitacao)
       OR (length(nai_chave_som(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)))) >= 7
           AND position(nai_chave_som(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)))
                        IN nai_chave_som(coalesce(p_texto, ''))) > 0)
     );
$function$;

COMMIT;

SELECT nai_chave_som('Condomínio Acquarelle') AS cadastro, nai_chave_som('aquarele') AS audio;
SELECT t AS texto, nai_imovel_pelo_condominio(t, '') AS imoveis
  FROM unnest(ARRAY[
    'O teu aquarele para locação ainda está disponível? O de uma suíte?',
    'Nay. Àquele Acquarelle de 2 qts ! 3.500 ainda tá disponível?',
    'tem no mirante das flores?',
    'o mirante da flor ainda ta disponivel?',
    'bom dia, tudo bem?',
    'Mobiliada',
    'vou passar na casa do meu cliente hoje',
    'o cliente quer 3 quartos ate 4 mil',
    'obrigado, boa noite'
  ]) t;
