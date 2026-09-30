-- 235 (30/09/2026): "NAY ATENDER COM INSTRUÇÃO" -- o botão do CRM que dá um recado à Nay.
-- Pedro: "no lugar da observação, uma espécie de prompt: eu digito o histórico do
-- cliente, o que ele está buscando, clico em 'Nay atender com instrução' e a Nay lê
-- a conversa recente (48 h) e atende baseado na nossa instrução"; "em qualquer
-- conversa de qualquer chat"; validade 48 h; manda direto.
--
--   nai_instrucao         a instrução da equipe para uma pessoa, válida 48 h.
--   crm_nay_instruir      grava, solta a Nay (o mesmo do "voltar a atender": aprova quem
--                         está fora da lista, volta para Todos) e devolve ok. Quem
--                         reentrega a última mensagem da pessoa é o CRM (rota nay).
--   contexto do turno     enquanto vale, a instrução entra no cabeçalho de TODO turno
--                         do corretor: "INSTRUÇÃO DA EQUIPE (vale até ...): ...".
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS nai_instrucao (
  id         bigserial PRIMARY KEY,
  contato_id bigint NOT NULL,      -- sem FK de propósito (nai_contato é escrita o tempo todo)
  texto      text NOT NULL,
  criado_por text,
  criado_em  timestamptz NOT NULL DEFAULT now(),
  valido_ate timestamptz NOT NULL DEFAULT now() + interval '48 hours'
);
CREATE INDEX IF NOT EXISTS nai_instrucao_contato ON nai_instrucao (contato_id, valido_ate DESC);

CREATE OR REPLACE FUNCTION public.nai_instrucao_texto(p_contato bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 235: a instrução mais recente que ainda vale, para o cabeçalho do turno
  SELECT 'INSTRUÇÃO DA EQUIPE (vale até ' || to_char(i.valido_ate AT TIME ZONE 'America/Manaus', 'DD/MM HH24:MI')
         || '): ' || i.texto || E'\n'
         || 'Siga esta instrução na resposta: ela diz quem é o cliente, o que ele procura e como atender. '
         || 'Continue usando as ferramentas para todo dado de imóvel.' || E'\n'
    FROM nai_instrucao i
   WHERE i.contato_id = ANY (coalesce(nai_contato_irmaos(p_contato), ARRAY[p_contato]))
     AND i.valido_ate > now()
   ORDER BY i.criado_em DESC LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public.crm_nay_instruir(p_telefone text, p_texto text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE v_ids bigint[]; v_contato bigint; v_texto text := left(btrim(coalesce(p_texto, '')), 4000); r record;
BEGIN
  IF v_texto = '' THEN RETURN QUERY SELECT false, 'Escreva a instrução antes.'; RETURN; END IF;
  SELECT p.ids, p.contato_id INTO v_ids, v_contato FROM crm_pessoas(ARRAY[p_telefone]) p LIMIT 1;
  IF v_ids IS NULL OR cardinality(v_ids) = 0 THEN
    v_contato := nai_contato_do_cadastro(p_telefone, NULL);
    v_ids := ARRAY[v_contato];
  END IF;
  v_contato := coalesce(v_contato, v_ids[1]);
  INSERT INTO nai_instrucao (contato_id, texto, criado_por) VALUES (v_contato, v_texto, left(coalesce(p_quem, 'CRM'), 80));
  -- solta a Nay do mesmo jeito do "voltar a atender" (228)
  SELECT * INTO r FROM crm_nay_voltar(p_telefone, p_quem);
  RETURN QUERY SELECT true, 'Instrução guardada por 48 h. ' || coalesce(r.mensagem, '');
END $function$;
REVOKE ALL ON FUNCTION crm_nay_instruir(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_nay_instruir(text, text, text) TO nay_disparo;

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei %', p_fn, p_vezes, n; END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;
SELECT pg_temp.trocar('nai_abrir_turno(text,text,text,text,bigint[])',
$a$    'contexto', CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '')$a$,
$b$    -- 235: a instrução da equipe (CRM) vem na frente de tudo, enquanto vale
    'contexto', CASE WHEN v_papel = 'corretor' THEN coalesce(nai_instrucao_texto(v_contato), '') END
                || CASE WHEN v_papel = 'corretor' THEN nai_etapa_para_o_modelo(v_contato) || E'\n' || coalesce(nai_retomada_texto(v_contato), '')$b$);
COMMIT;
