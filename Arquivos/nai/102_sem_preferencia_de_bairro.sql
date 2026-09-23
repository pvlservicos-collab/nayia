-- =====================================================================
-- NAI -- 102: sem preferencia de bairro, e Manaus nao e bairro
-- (Tel, 23/09/2026)
--
-- Ele: "ela alucinou... ela disse que nao queriamos saber de bairro entao ela
-- deveria pular para a proxima pergunta, e perguntar de preco e depois
-- mobilia, nao precisa ter os 3 filtros". E logo depois: "ela disse que nao
-- trabalha com imoveis em Manaus, ela nao pode falar isso pow".
--
-- O CASO (Deborah, (92) 9295-8201, hoje de manha):
--   09:19  ela:   "casal de clientes buscando ap mobiliado por 2k, que aceite
--                  pet"
--   09:21  Nay:   "Claro! A Sra. esta procurando imoveis em qual bairro?"
--   09:21  ela:   "nao teria preferencia por bairro"
--   09:22  Nay:   "Claro! A Sra. esta procurando imoveis em qual bairro?"
--   09:23  Nay:   "NAO TRABALHAMOS COM IMOVEL EM MANAUS NO MOMENTO."
--
-- DUAS COISAS ERRADAS, uma atras da outra:
--   1. "Nao tenho preferencia" nao era resposta aceita. A sequencia exige
--      bairro, entao ela repetiu a pergunta -- e ia repetir para sempre.
--   2. Sem bairro, o modelo mandou "Manaus" como bairro. A busca antiga nao
--      conhece bairro chamado Manaus e devolveu a frase de "fora da nossa
--      area" com o nome da CIDADE dentro. Para o corretor, a Nay da
--      imobiliaria de Manaus disse que nao trabalha em Manaus.
--
-- COMO FICA: sem preferencia de bairro, ela procura na cidade inteira e segue
-- para a proxima pergunta. O nome da cidade nunca mais entra como bairro --
-- nem na busca, nem na frase.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- 1 ------------------------------------------------- ELE NAO TEM PREFERENCIA
CREATE OR REPLACE FUNCTION public.nai_sem_preferencia_de_bairro(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT s ~ ('((nao|n) (tem|teria|ha|tenho|tem nenhuma) preferencia|'
           || 'sem preferencia|tanto faz|nao importa|indiferente|'
           || '(qualquer|todos os|todo) (bairro|lugar|regiao|local)|'
           || 'qualquer (um|uma)\M|'
           || '(nao|n) (tem|ha) (bairro|preferencia) (especifico|definido)|'
           || 'em qualquer|pode ser qualquer)')
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

-- A CIDADE NAO E BAIRRO. Quem escreve "Manaus" nao esta pedindo um bairro --
-- esta dizendo que nao tem bairro. Sem isto, a busca antiga responde "nao
-- trabalhamos com imovel em Manaus", que e a pior frase que ela pode dizer.
CREATE OR REPLACE FUNCTION public.nai_e_a_cidade(p_texto text)
 RETURNS boolean LANGUAGE sql IMMUTABLE
AS $function$
  SELECT btrim(s) ~ '^(manaus|manaus/?am|manaus - am|amazonas|am|cidade|a cidade)$'
    FROM (SELECT lower(unaccent(coalesce(p_texto, ''))) AS s) x;
$function$;

-- A busca em si e patcheada em 102b (montada fora, com o `montar102.py`):
-- costurar aspas dentro de um DO deu tres erros seguidos, e a funcao inteira
-- montada de fora se le melhor.

COMMIT;

SELECT nai_sem_preferencia_de_bairro(t) AS sem_preferencia, nai_e_a_cidade(t) AS e_a_cidade, t AS frase
  FROM unnest(ARRAY[
    'não teria preferência por bairro',
    'tanto faz',
    'qualquer bairro',
    'Manaus',
    'manaus/am',
    'Aleixo',
    'Ponta Negra',
    'prefiro no Adrianópolis'
  ]) t;
