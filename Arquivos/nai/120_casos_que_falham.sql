-- =====================================================================
-- NAI -- 120: os casos que FALHAM hoje (24/09/2026)
--
-- Primeiro o caso, depois o conserto. Este arquivo so acrescenta prova:
-- ele nao muda comportamento nenhum. Rodar `SELECT * FROM nai_rodar_casos()`
-- depois dele mostra vermelho -- e e para mostrar.
--
-- O QUE ACONTECEU DE VERDADE. Em 24/09 um corretor perguntou:
--   "Ei Nair, deixa eu perguntar, esse Park Golf so tem ar-condicionado?"
-- A Nay montou a resposta (o card do 5728 e 6 fotos) e a conferencia da
-- saida apagou as 7 linhas, com o motivo "tipo errado: ele pediu sala".
-- Ele nunca pediu sala. O "sala" veio do ANUNCIO QUE ELE MESMO MANDOU dois
-- dias antes ("CD living confort, 3 Dormitorios ... sala"). A Nay tratou o
-- imovel que ele OFERECE como o imovel que ele PROCURA -- e ficou muda.
--
-- Sao duas regras do Tel quebradas de uma vez:
--   1. o que ele oferece nao diz o que ele procura;
--   2. imovel que ele pediu pelo nome ele recebe.
-- =====================================================================

\set ON_ERROR_STOP on

BEGIN;

-- A bateria passa a saber perguntar sobre a CONVERSA, e nao so sobre uma
-- frase solta: as falas vao separadas por ' || ', a mais recente primeiro.
-- Sem isso nao havia como escrever o caso do Park Golf, que so existe
-- porque tem um turno de ontem atras dele.
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
      WHEN 'link'       THEN nai_e_link_de_produto(c.frase)::text
      WHEN 'pede_lista' THEN nai_pede_os_valores(c.frase)::text
      WHEN 'sem_bairro' THEN nai_sem_preferencia_de_bairro(c.frase)::text
      WHEN 'de_imovel'  THEN nai_e_assunto_de_locacao(c.frase)::text
      WHEN 'imoveis'    THEN nai_imoveis_pedidos(c.frase, '')::text
      WHEN 'nomes'      THEN nai_corrigir_nomes(c.frase)
      WHEN 'valor'      THEN coalesce(nay_maior_valor(c.frase)::text, '-')
      -- as duas novas: a conversa inteira, a fala de agora primeiro
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

-- As funcoes ainda nao existem: nascem na 120b. Ate la os casos novos dao
-- erro em vez de vermelho, e por isso elas entram aqui como casca, com o
-- comportamento de HOJE -- sem o filtro da oferta. Assim a bateria roda e
-- acusa a falha de verdade, que e o ponto.
CREATE OR REPLACE FUNCTION public.nai_tipo_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nai_tipo_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nai_tipo_pedido(f.fala) IS NOT NULL ORDER BY f.pos LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.nai_negocio_das_falas(p_falas text[])
 RETURNS text LANGUAGE sql STABLE AS $function$
  SELECT nay_negocio_pedido(f.fala)
    FROM unnest(coalesce(p_falas, '{}'::text[])) WITH ORDINALITY AS f(fala, pos)
   WHERE nay_negocio_pedido(f.fala) IS NOT NULL ORDER BY f.pos LIMIT 1;
$function$;

INSERT INTO nai_caso (quem, frase, pergunta, esperado, regra) VALUES
 ('Park Golf 24/09',
  'Ei Nair, deixa eu perguntar, esse Park Golf só tem ar-condicionado? Ele não tem modulados, não? || *EXCELENTE OPORTUNIDADE* *CD living confort* 3 Dormitórios sendo uma suíte com modulados, sala de estar e jantar',
  'tipo_conversa', '-',
  'o imóvel que ele OFERECE não diz o tipo que ele PROCURA'),
 ('Park Golf 24/09',
  'Ei Nair, deixa eu perguntar, esse Park Golf só tem ar-condicionado? Ele não tem modulados, não?',
  'imoveis', '{5728}',
  'imóvel que ele pediu pelo nome a conferência não pode barrar'),
 ('Luiz Bastos 23/09',
  'me manda as opções || tenho um Living Confort com sala ampla, se quiser te envio',
  'tipo_conversa', '-',
  'a oferta dele não ensina o tipo nem no turno seguinte'),
 ('Luiz Bastos 23/09',
  'me manda as opções || vendo meu apartamento por 450 mil',
  'negocio_conversa', '-',
  'o preço do imóvel DELE não faz dele um comprador'),
 ('Geina 22/09',
  'tem no Tarumã? || procuro casa para alugar até 3 mil',
  'tipo_conversa', 'Casa%',
  'o tipo dito antes continua valendo no turno seguinte');

COMMIT;

SELECT passou, regra, esperado, deu FROM nai_rodar_casos() WHERE NOT passou;
