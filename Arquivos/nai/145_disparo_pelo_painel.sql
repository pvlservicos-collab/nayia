-- =====================================================================
-- 145 — O DISPARO DE IMÓVEL PELO PAINEL (28/09/2026)
--
-- Pedido: "põe no site uma aba de disparo que eu disparo o imóvel
-- automático... lá em cima o número, embaixo um campo de pesquisar imóvel,
-- digita uma parte e desce uma lista de imóveis, eu seleciono e clico em
-- enviar e ele envia via zapi, eu seleciono também qual número quero enviar,
-- por padrão fica o de parceria. Quero esse menu de envio no site e no CRM lá
-- em cima."
--
-- UM REMETENTE SÓ: as duas telas (admin do site e CRM) chamam o CRM, e o CRM
-- chama estas funções -- pelo usuário `nay_disparo`, que só pode EXECUTAR as
-- três, nada de tabela.
--
--   PARCERIA (Z-API, o padrão): `nai_disparo_enfileirar` põe o envio na caixa
--   de saída da Nay -- a mesma de todo dia: o ritmo das fotos que protege o
--   número de banimento, e as paredes (parceiro não sai, indisponível não sai,
--   fotos do mesmo imóvel 1x a cada 24h por pessoa). O eco é reconhecido como
--   da Nay, e a conversa aparece no CRM pelo espelho.
--
--   API OFICIAL: `nai_disparo_conferir` confere e reserva; quem manda é o CRM,
--   pela API da Meta (só para quem falou com o número nas últimas 24h).
--   `nai_disparo_liberar` desfaz a reserva se o envio falhar.
-- =====================================================================
\set ON_ERROR_STOP on
BEGIN;
SET LOCAL lock_timeout = '5s';

-- ---------------------------------------------------------------------
-- Parceria: vira um turno de comando e cai na caixa de saída da Nay.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_disparo_enfileirar(p_telefone text, p_codigos integer[], p_quem text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  v_tel   bigint := nai_contato_do_cadastro(nai_cfg('tel_telefone'), 'Tel');
  v_turno bigint;
  v_msg   text;
BEGIN
  IF coalesce(array_length(p_codigos, 1), 0) = 0 THEN
    RETURN 'Escolha pelo menos um imóvel.';
  END IF;
  INSERT INTO nai_turno (contato_id, papel, texto)
  VALUES (v_tel, 'tel', left('disparo pelo painel (' || coalesce(nullif(btrim(p_quem), ''), '?') || '): '
                             || array_to_string(p_codigos, ', ') || ' para ' || coalesce(p_telefone, ''), 500))
  RETURNING id INTO v_turno;

  v_msg := nai_enviar_imoveis_para(v_turno, p_codigos, p_telefone);

  -- sai no próximo ciclo (hora marcada), e não daqui a 3 minutos
  UPDATE nai_saida SET enviar_apos = now() + interval '2 seconds'
   WHERE turno_id = v_turno AND estado = 'pendente';
  UPDATE nai_turno SET fechado_em = now() WHERE id = v_turno;
  RETURN v_msg;
END;
$fn$;

-- ---------------------------------------------------------------------
-- API oficial: confere as paredes, reserva as 24h e devolve card e fotos.
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION nai_disparo_conferir(p_telefone text, p_codigo integer, p_quem text)
RETURNS TABLE (pode boolean, motivo text, card text, fotos text[])
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  i     imoveis;
  v_ja  timestamptz;
  v_ch  text := nai_chave(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'));
BEGIN
  SELECT * INTO i FROM imoveis WHERE codigo = p_codigo;
  IF i.codigo IS NULL THEN
    RETURN QUERY SELECT false, 'não achei esse código'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF coalesce(i.e_parceiro, false) THEN
    RETURN QUERY SELECT false, 'é imóvel de parceiro (parceria não sai)'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF NOT nai_imovel_disponivel(p_codigo) THEN
    RETURN QUERY SELECT false, ('está ' || lower(coalesce(i.status, 'indisponível')) || ', não mandei')::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  IF v_ch IS NULL THEN
    RETURN QUERY SELECT false, 'número inválido'::text, NULL::text, NULL::text[]; RETURN;
  END IF;
  v_ja := nay_reservar_imovel_do_dia(v_ch, p_codigo, 'disparo', NULL);
  IF v_ja IS NOT NULL THEN
    RETURN QUERY SELECT false, ('as fotos já foram para esse número ' || nay_quando_foi(v_ja)
                                || ' (libera ' || nay_quando_foi(v_ja + interval '24 hours') || ')')::text,
                        NULL::text, NULL::text[];
    RETURN;
  END IF;
  RETURN QUERY
    SELECT true, NULL::text,
           (SELECT c.texto_pronto FROM nai_card_do_imovel(p_codigo) c),
           (SELECT coalesce(array_agg(f.url), '{}') FROM nai_imagens_do_envio(p_codigo) f WHERE NOT f.e_colagem);
END;
$fn$;

CREATE OR REPLACE FUNCTION nai_disparo_liberar(p_telefone text, p_codigo integer)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $fn$
  DELETE FROM imovel_enviado_no_dia
   WHERE chave = nai_chave(regexp_replace(coalesce(p_telefone, ''), '[^0-9]', '', 'g'))
     AND codigo = p_codigo AND origem = 'disparo'
     AND dia = (now() AT TIME ZONE 'America/Manaus')::date;
$fn$;

-- Só o `nay_disparo` executa estas três. Função no Postgres nasce executável
-- por PUBLIC; e estas escrevem na caixa de saída.
REVOKE EXECUTE ON FUNCTION nai_disparo_enfileirar(text, integer[], text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION nai_disparo_conferir(text, integer, text) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION nai_disparo_liberar(text, integer) FROM PUBLIC;

DO $do$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nay_disparo') THEN
    CREATE ROLE nay_disparo LOGIN;   -- a senha é posta à parte, fora do repositório
  END IF;
END;
$do$;
GRANT CONNECT ON DATABASE naydb TO nay_disparo;
GRANT USAGE ON SCHEMA public TO nay_disparo;
GRANT EXECUTE ON FUNCTION nai_disparo_enfileirar(text, integer[], text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION nai_disparo_conferir(text, integer, text) TO nay_disparo;
GRANT EXECUTE ON FUNCTION nai_disparo_liberar(text, integer) TO nay_disparo;

COMMIT;
