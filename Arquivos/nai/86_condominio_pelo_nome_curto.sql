-- =====================================================================
-- NAI -- 86: "Acquarelle" tambem e o Condominio Acquarelle (Tel, 22/09/2026)
--
-- Primeira hora no ar. A Marlucia (corretora dos grupos) escreveu:
--   "Nay. Aquele Acquarelle de 2 qts ! 3.500 ainda ta disponivel?"
-- A Nay nao respondeu. A porta disse "conversa que ja existia: quem responde
-- e o Tel" -- e conversa antiga so volta para ela quando a pessoa pede imovel
-- claramente, que e a ordem do Tel de hoje.
--
-- Ela PEDIU: citou um imovel nosso pelo nome. Quem devia ter aberto a porta e
-- `nai_imovel_pelo_condominio`, e ele falhou por um detalhe: procura o nome
-- INTEIRO do cadastro dentro do texto. No cadastro esta "Condominio
-- Acquarelle"; ela escreveu so "Acquarelle". "Mirante das Flores" funciona
-- porque o nome inteiro aparece na frase.
--
-- Agora vale tambem o NUCLEO do nome, sem as palavras genericas na frente ou
-- atras (condominio, residencial, edificio, ed., apart hotel, condominio
-- residencial). O piso de 8 letras continua, e agora vale para o nucleo:
-- "Vitta Club House" -> "Vitta Club House"; "Passaredo Residencial" ->
-- "Passaredo" (9). Nome curto demais depois do corte nao entra, senao
-- "Casa Nova" viraria qualquer frase.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

CREATE OR REPLACE FUNCTION public.nai_condominio_nucleo(p_nome text)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
AS $function$
  -- o nome sem as palavras genericas na frente e atras
  SELECT nullif(btrim(regexp_replace(regexp_replace(
           lower(unaccent(coalesce(p_nome, ''))),
           '^\s*(cond\.?|condominio|condominio residencial|residencial|resid\.?|edificio|ed\.?|apart hotel|apto)\s+', '', 'g'),
           '\s+(cond\.?|condominio|residencial|resid\.?|edificio|ed\.?)\s*$', '', 'g')), '');
$function$;

CREATE OR REPLACE FUNCTION public.nai_imovel_pelo_condominio(p_texto text, p_telefone text)
 RETURNS integer[]
 LANGUAGE sql
 STABLE
AS $function$
  -- CARD SEM CODIGO (Tel, 16/09). O corretor manda a ficha de um imovel
  -- copiada de outro sistema -- sem a linha "Codigo:" -- e nada no sistema o
  -- reconhecia. O nome do condominio basta.
  --
  -- VENDA CONTA (Tel, 16/09): por isso aqui nao entra `nai_oferta_serve`.
  --
  -- NOME QUE E TIPO NAO CONTA: "Apartamento", "Casa", "Predio" e "Flat" sao
  -- nomes de condominio na base e apareceriam em qualquer frase.
  --
  -- O NUCLEO TAMBEM VALE (86, Tel 22/09): no cadastro "Condominio Acquarelle",
  -- na boca do corretor "Acquarelle". Sem isso a porta nao abria para quem
  -- citava o imovel pelo nome curto -- foi o caso da Marlucia na primeira
  -- hora no ar.
  SELECT coalesce(array_agg(DISTINCT i.codigo), '{}')
    FROM imoveis i
   WHERE nai_condominio_ok(i.condominio_nome) IS NOT NULL
     AND nai_condominio_ok(i.condominio_nome) !~ '/'
     AND lower(unaccent(nai_condominio_ok(i.condominio_nome))) NOT IN (
           SELECT lower(unaccent(x.tipo)) FROM imoveis x WHERE x.tipo IS NOT NULL)
     AND nay_esta_no_mercado(i.disponivel, i.bloqueado, i.publicado_no_site)
     AND NOT coalesce(i.e_parceiro, false)
     AND (
       (length(nai_condominio_ok(i.condominio_nome)) >= 8
        AND position(lower(unaccent(nai_condominio_ok(i.condominio_nome)))
                     IN lower(unaccent(coalesce(p_texto, '')))) > 0)
       OR
       (length(coalesce(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)), '')) >= 8
        AND lower(unaccent(coalesce(p_texto, ''))) ~
            ('\m' || regexp_replace(nai_condominio_nucleo(nai_condominio_ok(i.condominio_nome)),
                                    '([.^$*+?()\[\]{}|\\-])', '\\\1', 'g') || '\M'))
     );
$function$;

COMMIT;

-- Prova: o que abre e o que NAO abre a porta.
SELECT t AS texto, nai_imovel_pelo_condominio(t, '559281136220') AS imoveis
  FROM unnest(ARRAY[
    'Nay. Àquele Acquarelle de 2 qts ! 3.500 ainda tá disponível?',
    'tem no Acquarelle?',
    'o Mirante das Flores ainda esta disponivel?',
    'bom dia, tudo bem?',
    'Mobiliada',
    'obrigado pela ajuda, boa noite',
    'vou passar na casa do meu cliente hoje',
    'o predio tem elevador?'
  ]) t;
