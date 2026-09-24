-- =====================================================================
-- NAI -- 120c: anuncio colado nao e pedido (24/09/2026)
--
-- Faltava um caso para a 120b fechar. `nai_oferece_imovel` (da 97) reconhece
-- quem OFERECE com verbo -- "tenho um Living Confort, se quiser te envio".
-- Nao reconhece o corretor que simplesmente COLA O CARTAZ no chat:
--
--   *EXCELENTE OPORTUNIDADE*
--   *CD living confort*
--   3 Dormitorios sendo uma suite com modulados, sala de estar e jantar
--
-- Sem verbo nenhum. E foi esse cartaz que ensinou a Nay que o corretor
-- "procurava sala" e a fez engolir o Park Golf dois dias depois.
--
-- A PENEIRA E SO PARA LER O PEDIDO. Ela nao entra no roteamento: quem
-- decide se a conversa e da secretaria continua sendo o Jev mais a 97,
-- intocados. Aqui ela serve a uma pergunta so -- "esta fala diz o que ele
-- PROCURA?" -- e a resposta para um anuncio e nao.
--
-- COMO ELA DECIDE. Verbo explicito ("vendo meu", "aluga-se") basta. Sem
-- verbo, exige TRES marcas de cartaz ao mesmo tempo, para que a pergunta
-- de um corretor de verdade nunca caia aqui: "procuro casa 3 quartos com
-- suite ate 3 mil" tem uma marca, e passa.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

INSERT INTO nai_config (chave, valor) VALUES ('pedido_ignora_anuncio', 'sim')
ON CONFLICT (chave) DO NOTHING;

CREATE OR REPLACE FUNCTION public.nai_e_anuncio_dele(p_texto text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
AS $function$
  WITH s AS (SELECT coalesce(p_texto, '') AS t)
  SELECT CASE
    -- 1. o verbo entrega sozinho
    -- (\M e FIM de palavra; \m e inicio. Trocar os dois faz a regra nunca
    --  casar, que foi o que aconteceu na primeira tentativa.)
    WHEN (SELECT t FROM s) ~* '(\mvend[eo]\s*-?\s*se\M|\maluga\s*-?\s*se\M|\m(vendo|alugo|repasso|passo)\s+(meu|minha)\M)'
      THEN true
    -- 2. sem verbo, sao as MARCAS DE CARTAZ, e precisa de tres
    ELSE (
      ((SELECT t FROM s) ~ '\*[^*]{3,}\*')::int                                    -- negrito de anuncio
    + ((SELECT t FROM s) ~ '[✅✔\U0001F3E0\U0001F3E1\U0001F3EC\U0001F4CD\U0001F4B0\U0001F6CF\U0001F6BF\U0001F511]')::int
    + ((SELECT t FROM s) ~* '(oportunidade|imperd[ií]vel|aceita financ|agende (sua |uma )?visita|documenta[çc][ãa]o ok|pronto para morar)')::int
    + ((SELECT t FROM s) ~* '\m(dormit[óo]rios?|su[ií]te|vagas? de garagem|[áa]rea de lazer|m²|metros quadrados)')::int
    + ((SELECT t FROM s) ~* '\m(valor|cond|condom[ií]nio|iptu)\s*:?\s*r?\$')::int
    ) >= 3
  END;
$function$;

-- A regra do pedido passa a ignorar as duas coisas: a oferta com verbo e o
-- cartaz sem verbo.
CREATE OR REPLACE FUNCTION public.nai_fala_e_dele(p_texto text)
 RETURNS boolean
 LANGUAGE sql STABLE
AS $function$
  SELECT (nai_cfg('pedido_ignora_oferta', 'sim') = 'sim' AND nai_oferece_imovel(coalesce(p_texto, '')))
      OR (nai_cfg('pedido_ignora_anuncio', 'sim') = 'sim' AND nai_e_anuncio_dele(p_texto));
$function$;

CREATE OR REPLACE FUNCTION public.nai_tipo_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_tipo_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nai_tipo_pedido(f.fala) IS NOT NULL
     AND NOT nai_fala_e_dele(f.fala)
   ORDER BY f.pos LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.nai_negocio_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nay_negocio_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nay_negocio_pedido(f.fala) IS NOT NULL
     AND NOT nai_fala_e_dele(f.fala)
   ORDER BY f.pos LIMIT 1;
$function$;

-- Os casos que provam que a peneira nao pega pergunta de corretor.
INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Park Golf 24/09',
  '*EXCELENTE OPORTUNIDADE* *CD living confort* 3 Dormitórios sendo uma suíte com modulados, sala de estar e jantar',
  'anuncio', 'true', 'cartaz colado no chat é anúncio dele'),
 ('Geina 22/09',
  'procuro casa 3 quartos com suíte até 3 mil',
  'anuncio', 'false', 'pergunta de corretor nunca é anúncio'),
 ('Tel 22/09',
  'tenho cliente para 3 quartos ate 700 mil no aleixo',
  'anuncio', 'false', 'cliente do corretor não é anúncio dele');

CREATE OR REPLACE FUNCTION public.nai_rodar_casos()
 RETURNS TABLE(passou boolean, regra text, frase text, esperado text, deu text)
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE c record; v text;
BEGIN
  FOR c IN SELECT * FROM nai_caso WHERE ativo ORDER BY id LOOP
    v := CASE c.pergunta
      WHEN 'tipo'       THEN coalesce(nai_tipo_pedido(c.frase), '-')
      WHEN 'tipo_canon' THEN coalesce(nai_tipo_canonico(c.frase), '-')
      WHEN 'negocio'    THEN coalesce(nay_negocio_pedido(c.frase), '-')
      WHEN 'cortesia'   THEN nai_e_so_cortesia(c.frase)::text
      WHEN 'oferta'     THEN nai_oferece_imovel(c.frase)::text
      WHEN 'anuncio'    THEN nai_e_anuncio_dele(c.frase)::text
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      WHEN 'tipo_conversa'    THEN coalesce(nai_tipo_das_falas(string_to_array(c.frase, ' || ')), '-')
      WHEN 'negocio_conversa' THEN coalesce(nai_negocio_das_falas(string_to_array(c.frase, ' || ')), '-')
      ELSE '(pergunta desconhecida: ' || c.pergunta || ')'
    END;
    passou := (v = c.esperado);
    regra := c.regra; frase := c.frase; esperado := c.esperado; deu := v;
    RETURN NEXT;
  END LOOP;
END;
$function$;

COMMIT;

SELECT count(*) FILTER (WHERE passou) || ' de ' || count(*) AS bateria FROM nai_rodar_casos();
SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;

-- =====================================================================
-- COMO DESFAZER
--   UPDATE nai_config SET valor='nao' WHERE chave='pedido_ignora_anuncio';
-- Volta ao comportamento da 120b (so a oferta com verbo e ignorada).
-- =====================================================================
