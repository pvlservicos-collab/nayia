-- 375: LEMBRETES DA EQUIPE no sininho do admin do site
--
-- Pedro, 15/10/2026: "existe hoje um lembrete de aviso para o lead; quero um lembrete de aviso pra nós: ele nos avisa no
-- site, em um menu de notificação, ao entrar pela primeira vez lá em cima, até eu ir lá e clicar em feito; em um dia
-- específico e um texto que eu escrevo".
--
-- Um lembrete = um texto + um dia. Do dia em diante (hora de Manaus) ele fica no sininho do topo do admin, contando,
-- até alguém clicar em Feito. Antes do dia, aparece em "Próximos". Ninguém é avisado por WhatsApp: é só o sininho.
-- As funções são a porta (SECURITY DEFINER); o papel do site não toca a tabela.

BEGIN;

CREATE TABLE IF NOT EXISTS privado.lembrete_equipe (
  id        bigserial PRIMARY KEY,
  texto     text NOT NULL CHECK (length(btrim(texto)) BETWEEN 1 AND 1000),
  dia       date NOT NULL,
  criado_em timestamptz NOT NULL DEFAULT now(),
  feito_em  timestamptz,
  apagado_em timestamptz
);
CREATE INDEX IF NOT EXISTS lembrete_equipe_aberto ON privado.lembrete_equipe (dia) WHERE feito_em IS NULL AND apagado_em IS NULL;
COMMENT ON TABLE privado.lembrete_equipe IS '375: lembrete da equipe no sininho do admin do site (texto + dia, até clicar em Feito).';

CREATE OR REPLACE FUNCTION public.site_lembretes()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
  WITH hoje AS (SELECT (now() AT TIME ZONE 'America/Manaus')::date AS d),
  vivos AS (SELECT l.* FROM privado.lembrete_equipe l WHERE l.apagado_em IS NULL)
  SELECT jsonb_build_object(
    'hoje', (SELECT d FROM hoje),
    -- do dia em diante e ainda sem "feito": é o que acende o sininho
    'agora', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia,
                                                           'atrasado', v.dia < (SELECT d FROM hoje)) ORDER BY v.dia, v.id)
                         FROM vivos v WHERE v.feito_em IS NULL AND v.dia <= (SELECT d FROM hoje)), '[]'::jsonb),
    'proximos', coalesce((SELECT jsonb_agg(jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia) ORDER BY v.dia, v.id)
                            FROM vivos v WHERE v.feito_em IS NULL AND v.dia > (SELECT d FROM hoje)), '[]'::jsonb),
    'feitos', coalesce((SELECT jsonb_agg(x.j ORDER BY x.feito_em DESC) FROM (
                          SELECT v.feito_em, jsonb_build_object('id', v.id, 'texto', v.texto, 'dia', v.dia, 'feito_em', v.feito_em) AS j
                            FROM vivos v WHERE v.feito_em > now() - interval '7 days' ORDER BY v.feito_em DESC LIMIT 10) x), '[]'::jsonb))
$function$;

CREATE OR REPLACE FUNCTION public.site_lembrete_criar(p_texto text, p_dia date)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
DECLARE v_texto text := btrim(coalesce(p_texto, '')); v_id bigint;
BEGIN
  IF v_texto = '' THEN RETURN jsonb_build_object('erro', 'Escreva o lembrete.'); END IF;
  IF length(v_texto) > 1000 THEN RETURN jsonb_build_object('erro', 'O lembrete passou de 1.000 caracteres.'); END IF;
  IF p_dia IS NULL THEN RETURN jsonb_build_object('erro', 'Escolha o dia.'); END IF;
  INSERT INTO privado.lembrete_equipe (texto, dia) VALUES (v_texto, p_dia) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'id', v_id);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_lembrete_feito(p_id bigint, p_feito boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  -- p_feito = false desfaz (o "ops, cliquei sem querer")
  UPDATE privado.lembrete_equipe SET feito_em = CASE WHEN p_feito THEN now() END
   WHERE id = p_id AND apagado_em IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse lembrete.'); END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;

CREATE OR REPLACE FUNCTION public.site_lembrete_apagar(p_id bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
BEGIN
  -- não some do banco: fica marcado como apagado
  UPDATE privado.lembrete_equipe SET apagado_em = now() WHERE id = p_id AND apagado_em IS NULL;
  IF NOT FOUND THEN RETURN jsonb_build_object('erro', 'Não achei esse lembrete.'); END IF;
  RETURN jsonb_build_object('ok', true);
END
$function$;

REVOKE ALL ON FUNCTION public.site_lembretes(), public.site_lembrete_criar(text, date), public.site_lembrete_feito(bigint, boolean),
                       public.site_lembrete_apagar(bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.site_lembretes(), public.site_lembrete_criar(text, date), public.site_lembrete_feito(bigint, boolean),
                          public.site_lembrete_apagar(bigint) TO nay_site_escrita;

COMMIT;
