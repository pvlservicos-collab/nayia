-- O que a Nay falou de um imóvel e nunca mandou de verdade.
--
-- O CASO: em 30/08 o Gustavo pediu três imóveis, ela respondeu sobre a
-- forma de pagamento e **não mandou nenhum**. Em 31/08 o Ênio deu o perfil
-- (Ponta Negra, locação, 2 quartos, sem mobília) e também ficou sem
-- receber. Nos dois o assunto morreu no meio da conversa e ninguém --
-- nem ela, nem eu -- percebeu.
--
-- A IDEIA: `envios` guarda o que saiu de verdade (desde 31/08 também o
-- disparo de grupo). `mensagens` guarda os dois lados da conversa. Cruzar
-- os dois responde "de que imóvel a gente falou e nunca mandou?" sem
-- depender de ela lembrar.
--
-- POR QUE NÃO CONFIAR NA MEMÓRIA DELA: `nay_memoria` tem a conversa, mas
-- pedir ao modelo que "lembre o que prometeu" é instrução, e instrução
-- sobre estado falha em silêncio -- foi assim que o Gustavo esperou dois
-- dias. Cruzamento de tabela é dado: ou saiu, ou não saiu.
--
--   docker cp o_que_ficou_de_enviar.sql nay-postgres:/tmp/oq.sql
--   docker exec nay-postgres psql -U nay -d naydb -f /tmp/oq.sql

CREATE OR REPLACE FUNCTION nay_o_que_ficou_de_enviar(
  p_telefone text,
  p_horas    int DEFAULT 72
) RETURNS TABLE(texto_pronto text, codigos text, instrucao_para_voce text)
LANGUAGE plpgsql STABLE AS $fn$
DECLARE
  v_tel  text := regexp_replace(coalesce(p_telefone,''),'[^0-9]','','g');
  v_lista text;
  v_cods  text;
  v_n     int;
BEGIN
  -- Códigos citados na conversa (dos DOIS lados) que não têm envio
  -- registrado para este corretor.
  -- `nay_codigos_citados` tira os VALORES antes de procurar código. Os
  -- códigos deste catálogo vão de 45 a 5712 -- a mesma faixa de um
  -- orçamento de aluguel -- e "Paga até 4000" virava dívida do imóvel
  -- 4000. Ver valor_nao_e_codigo.sql.
  WITH citados AS (
    SELECT DISTINCT unnest(nay_codigos_citados(
             coalesce(m.texto,'') || ' ' || coalesce(m.citado,''))) AS codigo
      FROM mensagens m
     WHERE right(regexp_replace(m.telefone,'[^0-9]','','g'),8) = right(v_tel,8)
       AND m.criada_em > now() - make_interval(hours => greatest(p_horas,1))
  ), faltando AS (
    SELECT c.codigo,
           coalesce(NULLIF(i.condominio_nome,''), i.tipo, 'imóvel') AS nome,
           i.quartos,
           coalesce(i.valor_aluguel, i.valor_venda) AS valor
      FROM citados c
      JOIN imoveis i ON i.codigo::text = c.codigo
     WHERE coalesce(i.disponivel, true)
       AND NOT EXISTS (
             SELECT 1 FROM envios e
              WHERE e.codigo = c.codigo
                AND e.destino = 'corretor'
                AND right(regexp_replace(e.telefone,'[^0-9]','','g'),8) = right(v_tel,8))
  )
  SELECT count(*),
         string_agg(codigo, ',' ORDER BY codigo),
         string_agg('• ' || codigo || ' — ' || nome
                    || coalesce(' — ' || quartos || ' quartos','')
                    || coalesce(' — ' || replace(to_char(valor,'FM999,999,990'),',','.'),''),
                    chr(10) ORDER BY codigo)
    INTO v_n, v_cods, v_lista
    FROM faltando;

  IF coalesce(v_n,0) = 0 THEN
    RETURN QUERY SELECT
      ''::text, ''::text,
      'nao ficou nenhum imovel para mandar a esse corretor. Siga a conversa normal.'::text;
    RETURN;
  END IF;

  RETURN QUERY SELECT
    v_lista,
    v_cods,
    ('voces falaram destes ' || v_n || ' imovel(is) e voce NUNCA mandou o card '
     || 'e as fotos. Se ele pediu, mande AGORA: chame imovel_por_codigo de cada um '
     || 'na mesma resposta. Se voce nao tem certeza de que ele quer, pergunte antes '
     || 'de mandar, para nao encher o WhatsApp dele.')::text;
END;
$fn$;
