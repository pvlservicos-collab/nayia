-- 242 (30/09/2026): A ETAPA DA CAPTAÇÃO ESCOLHIDA À MÃO, COMO NA PARCERIA (+ FOLLOW-UP).
-- Pedro: "adicione lá na aba captação a mesma ferramenta de mudar a etapa do lead que
-- nem na parceria, mas com as etapas da captação, e adicione mais uma etapa: follow-up".
--
--   captacao_etapa_manual      a escolha de quem está no CRM, uma por pessoa. Vale mais
--                              que o que a campanha deduziu (o mesmo desenho da
--                              nai_etapa_manual da Parceria, 201).
--   crm_captacao_etapa_manual  o que o card chama. 'todos' solta (apaga a escolha);
--                              'com_o_tel' para a Nay (humano_assumiu_em) e a solta
--                              quando volta para 'todos'.
--   followup                   etapa nova: "voltar a falar com essa pessoa". Não é
--                              situação do imóvel, é fila de trabalho.
--   crm_captacao_donos().abas  a etapa escolhida à mão SUBSTITUI as abas de situação
--                              (senão a pessoa apareceria em duas); sem escolha, as
--                              abas continuam saindo do que a campanha gravou (236).
--
-- A fila de disparo não é tocada: ela olha captacao_leads.status, e esta tabela é
-- separada. Ninguém vira 'novo' nem sai de 'novo' por aqui.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS captacao_etapa_manual (
  telefone     text PRIMARY KEY,          -- só dígitos, como em captacao_leads
  etapa        text NOT NULL,
  definido_por text,
  definido_em  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT captacao_etapa_manual_ok CHECK (etapa = ANY (ARRAY[
    'todos', 'em_andamento', 'followup', 'disponiveis', 'alugados',
    'quer_vender', 'ja_vendeu', 'tem_outro_imovel', 'sem_resposta', 'com_o_tel']))
);
COMMENT ON TABLE captacao_etapa_manual IS '242: a etapa da captação escolhida no CRM; vale mais que a deduzida pela campanha';

CREATE OR REPLACE FUNCTION public.crm_captacao_etapa_manual(p_telefone text, p_etapa text, p_quem text)
 RETURNS TABLE(ok boolean, mensagem text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
 SET lock_timeout TO '3s'
AS $function$
DECLARE
  v_dig  text := regexp_replace(coalesce(p_telefone, ''), '\D', '', 'g');
  v_quem text := left(coalesce(nullif(btrim(p_quem), ''), 'CRM'), 80);
  v_n    int;
BEGIN
  IF length(v_dig) IN (10, 11) THEN v_dig := '55' || v_dig; END IF;
  IF v_dig !~ '^[0-9]{12,13}$' THEN
    RETURN QUERY SELECT false, 'Não entendi o telefone.'; RETURN;
  END IF;
  IF p_etapa NOT IN ('todos', 'em_andamento', 'followup', 'disponiveis', 'alugados',
                     'quer_vender', 'ja_vendeu', 'tem_outro_imovel', 'sem_resposta', 'com_o_tel') THEN
    RETURN QUERY SELECT false, 'Etapa desconhecida: ' || coalesce(p_etapa, ''); RETURN;
  END IF;

  IF p_etapa = 'todos' THEN
    DELETE FROM captacao_etapa_manual WHERE telefone = v_dig;
    UPDATE captacao_leads SET humano_assumiu_em = NULL, humano_motivo = NULL
     WHERE right(telefone, 8) = right(v_dig, 8) AND humano_assumiu_em IS NOT NULL;
    RETURN QUERY SELECT true, 'Em Todos: a etapa volta a ser a que a campanha diz.';
    RETURN;
  END IF;

  INSERT INTO captacao_etapa_manual (telefone, etapa, definido_por)
  VALUES (v_dig, p_etapa, v_quem)
  ON CONFLICT (telefone) DO UPDATE SET etapa = EXCLUDED.etapa, definido_por = EXCLUDED.definido_por, definido_em = now();

  -- com o Tel: a Nay para de responder essa pessoa (o mesmo da Parceria)
  IF p_etapa = 'com_o_tel' THEN
    UPDATE captacao_leads
       SET humano_assumiu_em = coalesce(humano_assumiu_em, now()),
           humano_motivo = coalesce(humano_motivo, left('CRM: ' || v_quem || ' mandou para o Tel', 200))
     WHERE right(telefone, 8) = right(v_dig, 8);
    GET DIAGNOSTICS v_n = ROW_COUNT;
    RETURN QUERY SELECT true, CASE WHEN v_n > 0
      THEN 'Com o Tel: a Nay não fala mais com essa pessoa até voltar para Todos.'
      ELSE 'Com o Tel. (Essa pessoa não está na campanha, então não havia nada para calar.)' END;
    RETURN;
  END IF;

  RETURN QUERY SELECT true, 'Movido para ' || CASE p_etapa
    WHEN 'em_andamento' THEN 'Em andamento' WHEN 'followup' THEN 'Follow-up'
    WHEN 'disponiveis' THEN 'Disponíveis'  WHEN 'alugados' THEN 'Alugados'
    WHEN 'quer_vender' THEN 'Quer vender'  WHEN 'ja_vendeu' THEN 'Já vendeu'
    WHEN 'tem_outro_imovel' THEN 'Tem outro imóvel' ELSE 'Sem resposta' END || '.';
END $function$;
REVOKE ALL ON FUNCTION crm_captacao_etapa_manual(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_etapa_manual(text, text, text) TO nay_disparo;

-- as abas: a escolha à mão manda; sem escolha, o que a campanha diz (236)
DROP FUNCTION IF EXISTS public.crm_captacao_donos();
CREATE FUNCTION public.crm_captacao_donos()
 RETURNS TABLE(telefone text, chat_lid text, nome text, condominio text, codigo text, bairro text, tipo text,
               captacao_id bigint, imoveis integer, abas text[], etapa_manual text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
 SET jit TO 'off'
AS $function$
  WITH base AS (
    SELECT DISTINCT ON (nai_fone_br(l.telefone))
           nai_fone_br(l.telefone) AS fone,
           nullif(regexp_replace(coalesce(l.chat_lid, ''), '\D', '', 'g'), '') AS lid,
           nullif(btrim(l.nome), '') AS nome,
           nullif(btrim(coalesce(nullif(btrim(l.condominio), ''), i.condominio_nome)), '') AS condominio,
           nullif(btrim(l.codigo), '') AS codigo,
           nullif(btrim(l.bairro), '') AS bairro,
           nullif(btrim(l.tipo_imovel), '') AS tipo,
           l.id AS captacao_id,
           greatest(1, coalesce(jsonb_array_length(CASE WHEN jsonb_typeof(l.imoveis_prop) = 'array' THEN l.imoveis_prop END), 1)) AS imoveis,
           array_remove(ARRAY[
             CASE WHEN l.humano_assumiu_em IS NOT NULL THEN 'com_o_tel' END,
             CASE WHEN l.situacao = 'disponivel' THEN 'disponiveis' END,
             CASE WHEN l.situacao = 'alugado' THEN 'alugados' END,
             CASE WHEN l.situacao = 'vendido' THEN 'ja_vendeu' END,
             CASE WHEN l.quer_vender THEN 'quer_vender' END,
             CASE WHEN l.tem_outro_imovel THEN 'tem_outro_imovel' END,
             CASE WHEN l.respondeu_em IS NOT NULL AND coalesce(l.etapa, '') <> 'concluido' AND l.fechado_em IS NULL THEN 'em_andamento' END,
             CASE WHEN l.ultimo_envio_em IS NOT NULL AND l.respondeu_em IS NULL THEN 'sem_resposta' END
           ], NULL) AS abas,
           right(regexp_replace(l.telefone, '\D', '', 'g'), 8) AS fim8
      FROM captacao_leads l
      LEFT JOIN imoveis i ON i.codigo::text = btrim(l.codigo)
     WHERE coalesce(l.telefone, '') <> '' AND nai_fone_br(l.telefone) IS NOT NULL
     ORDER BY nai_fone_br(l.telefone), l.ultimo_envio_em DESC NULLS LAST, l.id DESC
  ),
  -- 242: quem só existe na escolha à mão (contato do Tel, fora da campanha) também aparece
  so_manual AS (
    SELECT nai_fone_br(e.telefone) AS fone, NULL::text AS lid, NULL::text AS nome, NULL::text AS condominio,
           NULL::text AS codigo, NULL::text AS bairro, NULL::text AS tipo, NULL::bigint AS captacao_id,
           1 AS imoveis, '{}'::text[] AS abas, right(e.telefone, 8) AS fim8
      FROM captacao_etapa_manual e
     WHERE nai_fone_br(e.telefone) IS NOT NULL
       AND NOT EXISTS (SELECT 1 FROM base b WHERE b.fim8 = right(e.telefone, 8))
  ),
  tudo AS (SELECT * FROM base UNION ALL SELECT * FROM so_manual)
  SELECT t.fone, t.lid, t.nome, t.condominio, t.codigo, t.bairro, t.tipo, t.captacao_id, t.imoveis,
         CASE WHEN e.etapa IS NULL THEN t.abas ELSE ARRAY[e.etapa] END,
         e.etapa
    FROM tudo t
    LEFT JOIN captacao_etapa_manual e ON right(e.telefone, 8) = t.fim8
$function$;
REVOKE ALL ON FUNCTION crm_captacao_donos() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_donos() TO nay_disparo;
COMMIT;
