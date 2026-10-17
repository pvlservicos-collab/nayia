-- 400: IMÓVEL DE PARCEIRO -- a marca fica clara e ele passa a ir ao CLIENTE FINAL do número de captação
--
-- Pedro, 17/10/2026: "adicione uma Situação, Parceiros, que são imóveis de parceiro, e que fique sempre claro que esses
-- são de parceiros (uma tag onde ele aparecer internamente). As regras: não enviamos para os corretores, só para os
-- clientes finais que vêm da OLX por enquanto, ou seja, para todos do número Parceria não enviamos, mas pode enviar para
-- os que não são corretores do número captação".
--
-- O que muda aqui:
--  1. a marca à mão vence: extras.parceiro_manual = 'sim'|'nao' (gravado pelo admin) manda em e_parceiro, por cima da
--     leitura diária do site antigo (que regrava e_parceiro às 09:17) e do captador "(Parceiro)";
--  2. nai_card_do_banco / nai_card_do_imovel ganham p_cliente: com ele, o imóvel de parceiro sai com o card completo
--     (sem "esse imóvel é de parceria" e com as fotos contadas). Sem ele, tudo como antes (a Parceria não muda);
--  3. olx_pode_receber_parceiro(telefone): quem NÃO é corretor (grupos ou parceiro do site antigo);
--     olx_imovel_vai_ao_cliente(código, telefone): o que a Nay do WhatsApp (8595) pode mandar a essa pessoa;
--  4. olx_cliente_buscar aceita o imóvel de parceiro Disponível quando os filtros trazem aceita_parceiro = 'true'
--     (o nay-olx só põe isso para quem não é corretor).
-- As paredes da Parceria (nai_saida_validar, core_saida_validar) ficam como estão: lá parceiro nunca sai.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1. a marca à mão vence
CREATE OR REPLACE FUNCTION public.imoveis_parceiro_pelo_captador()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  v_manual text := lower(coalesce(NEW.extras, '{}'::jsonb)->>'parceiro_manual');
BEGIN
  -- 400: quem marcou à mão no admin (Situação > Parceiros) manda, nos dois sentidos
  IF v_manual = 'nao' THEN
    NEW.e_parceiro := false;
    RETURN NEW;
  END IF;
  -- `administrado` e parceiro ao mesmo tempo viola chk_parceiro_nao_administrado:
  -- nesse caso nao mexe (e o humano quem resolve).
  IF NOT coalesce(NEW.administrado, false)
     AND (v_manual = 'sim'
          OR nai_captador_e_parceiro(NEW.captado_por)
          OR nai_captador_e_parceiro(coalesce(NEW.extras, '{}'::jsonb)->>'captado por')) THEN
    NEW.e_parceiro := true;
  END IF;
  RETURN NEW;
END;
$function$;

-- 2. o card para o cliente final
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.nai_card_do_banco(integer)'::regprocedure);
  d := replace(d, 'nai_card_do_banco(p_codigo integer)', 'nai_card_do_banco(p_codigo integer, p_cliente boolean DEFAULT false)');
  d := replace(d, $a$    CASE WHEN coalesce(b.e_parceiro, false) THEN
      '📍 '$a$, $b$    CASE WHEN coalesce(b.e_parceiro, false) AND NOT p_cliente THEN   -- 400: ao cliente final vai o card completo
      '📍 '$b$);
  d := replace(d, $a$CASE WHEN coalesce(b.e_parceiro, false) THEN 0 ELSE$a$,
                  $b$CASE WHEN coalesce(b.e_parceiro, false) AND NOT p_cliente THEN 0 ELSE$b$);
  IF (length(d) - length(replace(d, 'AND NOT p_cliente', ''))) / length('AND NOT p_cliente') <> 2 THEN
    RAISE EXCEPTION 'nai_card_do_banco: as âncoras não bateram';
  END IF;
  DROP FUNCTION public.nai_card_do_banco(integer);
  EXECUTE d;

  d := pg_get_functiondef('public.nai_card_do_imovel(integer)'::regprocedure);
  d := replace(d, 'nai_card_do_imovel(p_codigo integer)', 'nai_card_do_imovel(p_codigo integer, p_cliente boolean DEFAULT false)');
  d := replace(d, $a$               AND NOT coalesce(i.e_parceiro, false)$a$,
                  $b$               AND (p_cliente OR NOT coalesce(i.e_parceiro, false))$b$);
  d := replace(d, $a$    FROM nai_card_do_banco(p_codigo) b;$a$, $b$    FROM nai_card_do_banco(p_codigo, p_cliente) b;$b$);
  IF position('p_cliente OR NOT' IN d) = 0 OR position('nai_card_do_banco(p_codigo, p_cliente)' IN d) = 0 THEN
    RAISE EXCEPTION 'nai_card_do_imovel: as âncoras não bateram';
  END IF;
  DROP FUNCTION public.nai_card_do_imovel(integer);
  EXECUTE d;
END
$do$;

-- 3. quem pode receber imóvel de parceiro, e o que vai a cada pessoa
CREATE OR REPLACE FUNCTION public.olx_pode_receber_parceiro(p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- cliente final: tem telefone e não é corretor (dos grupos ou parceiro do site antigo)
  SELECT length(regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g')) >= 10
     AND NOT coalesce(nay_e_corretor_chave(nay_fone_chave(nay_fone_com_ddi(regexp_replace(p_telefone, '\D', '', 'g')))), false)
$function$;

CREATE OR REPLACE FUNCTION public.olx_imovel_vai_ao_cliente(p_codigo integer, p_telefone text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  SELECT EXISTS (SELECT 1 FROM core_imovel_busca b WHERE b.codigo = p_codigo AND b.ofertavel)
      OR (EXISTS (SELECT 1 FROM imoveis i
                   WHERE i.codigo = p_codigo AND i.e_parceiro AND i.status = 'Disponível'
                     AND coalesce(i.disponivel, true) AND NOT coalesce(i.bloqueado, false)
                     AND (coalesce(i.valor_aluguel, 0) > 0 OR coalesce(i.valor_venda, 0) > 0))
          AND olx_pode_receber_parceiro(p_telefone))
$function$;

-- 4. a busca da Nay do WhatsApp aceita o parceiro quando o nay-olx diz que pode
DO $do$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.olx_cliente_buscar(jsonb,integer[],integer)'::regprocedure);
  d := replace(d, $a$     WHERE i.ofertavel AND NOT coalesce(i.e_parceiro, false)$a$,
    $b$     -- 400: o imóvel de parceiro Disponível vai ao cliente final (o nay-olx só manda aceita_parceiro a quem não é corretor)
     WHERE (i.ofertavel
            OR (coalesce(p_filtros->>'aceita_parceiro', '') = 'true' AND coalesce(i.e_parceiro, false)
                AND x.status = 'Disponível' AND coalesce(x.disponivel, true) AND NOT coalesce(x.bloqueado, false)))$b$);
  IF position('aceita_parceiro' IN d) = 0 THEN RAISE EXCEPTION 'olx_cliente_buscar: a âncora não bateu'; END IF;
  EXECUTE d;
END
$do$;

REVOKE ALL ON FUNCTION public.olx_pode_receber_parceiro(text), public.olx_imovel_vai_ao_cliente(integer, text) FROM PUBLIC;
COMMIT;
