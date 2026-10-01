-- 255 (01/10/2026): "SOLICITAÇÃO DE VISITA", E A NAY É UMA SÓ.
-- Dois pedidos urgentes do Pedro:
--
-- 1. "a mensagem de confirmação de visita tá confundindo, a pessoa acha que a
--    visita está confirmada quando só é a solicitação de visita". O cabeçalho
--    dizia "Confirmação de visita" e a linha seguinte "Sua visita ao imóvel foi
--    agendada" -- nas duas o corretor lia visita FECHADA, quando aquilo é só o
--    pedido para ele conferir antes de sair. Texto novo, ditado por ele.
--
-- 2. "de maneira nenhuma ela deve mandar isso: 'quem cuida dela com você é a
--    Rayssa, da nossa equipe'. Nunca. A Nay é só uma."
--    Em três camadas, porque texto solto volta:
--      a) o texto pronto (nai_texto_corretor_confirmou) fala na primeira pessoa;
--      b) a conferência 12 da caixa já cortava a frase que citava o TEL para
--         corretor, proprietário e motoboy -- passa a cortar o nome do
--         aprovador também (hoje "Rayssa", lido de nai_config);
--      c) o prompt do corretor diz a regra (fora deste arquivo).
--    O fluxo NÃO muda: a visita continua indo para a equipe (197/199). O que
--    muda é que o corretor não ouve outro nome -- para ele existe a Nay.
--
-- As mensagens para a EQUIPE e para o TEL continuam com o nome dela: lá o nome
-- é necessário (é ela quem tem de agir).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION pg_temp.trocar(p_fn regprocedure, p_de text, p_para text, p_vezes int DEFAULT 1)
 RETURNS void LANGUAGE plpgsql AS $$
DECLARE d text := pg_get_functiondef(p_fn); n int := (length(d) - length(replace(d, p_de, ''))) / length(p_de);
BEGIN
  IF n <> p_vezes THEN RAISE EXCEPTION 'trocar em %: esperava % vez(es), achei % -- %', p_fn, p_vezes, n, left(p_de, 50); END IF;
  EXECUTE replace(d, p_de, p_para);
END $$;

-- 1 ---------------------------------------------- o texto do pedido de visita
CREATE OR REPLACE FUNCTION public.nai_texto_confirmar_visita(p_visita bigint)
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  SELECT '🏠 *Só para confirmar a solicitação de visita*' || E'\n\n'
      || 'Visita ao imóvel:' || E'\n\n'
      || '🔑 Código do imóvel: #' || v.codigo || E'\n'
      || '📅 Data: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'DD/MM') || ' (' || nai_dia_da_semana(v.quando) || ')' || E'\n'
      || '🕐 Horário: ' || to_char(v.quando AT TIME ZONE 'America/Manaus', 'HH24"h"MI') || E'\n\n'
      || 'Por favor, confirme se os dados estão corretos.'
    FROM nai_visita v WHERE v.id = p_visita;
$function$;
COMMENT ON FUNCTION nai_texto_confirmar_visita(bigint) IS
  '255: o PEDIDO de visita para o corretor conferir. Não diz "confirmada" nem "agendada": isso é depois, quando o proprietário aceita.';

-- 2 ------------------------------------------- a Nay responde na primeira pessoa
CREATE OR REPLACE FUNCTION public.nai_texto_corretor_confirmou()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  -- 255: sem nome de colega. O corretor fala com a Nay, e a Nay é uma só --
  -- quem cuida da visita por dentro é assunto nosso, não dele.
  SELECT CASE WHEN nai_cfg('visita_com_a_rayssa', 'sim') = 'sim'
    THEN 'Certo! Anotei a sua visita. Qualquer novidade sobre ela eu te aviso por aqui.'
    ELSE 'Certo! Vou ver esse horário com o proprietário e já te retorno.' END;
$function$;
COMMENT ON FUNCTION nai_texto_corretor_confirmou() IS
  '255: a Nay é uma só -- nunca cita o nome de quem cuida da visita por dentro';

-- a variável nova da conferência (âncora única: a primeira declaração)
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure,
$de$DECLARE
  t        nai_turno;$de$,
$para$DECLARE
  v_fora   text;
  t        nai_turno;$para$);

-- 3 -------------------------- a parede: o nome do aprovador não sai para fora
-- A conferência 12 já cortava a frase que citava o TEL. Agora o regex é
-- montado com o nome do aprovador junto, lido de nai_config -- trocar o nome
-- na configuração muda a parede sozinho, sem migração nova.
SELECT pg_temp.trocar('nai_conferir_resposta(bigint,text,jsonb,text,jsonb)'::regprocedure,
$de$  -- 12 ------------------------------------------------------ CITOU O TEL
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* '\mtel\M' THEN
    v_texto := nai_tirar_frase(v_texto, '\mtel\M');
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_o_tel_cortado';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'quem sobe para o Tel não conta para ninguém');$de$,
$para$  -- 12 ------------------------------------- CITOU O TEL OU QUEM CUIDA DA VISITA
  -- 255: a Nay é uma só. O nome de quem trata a visita por dentro (nai_config
  -- aprovador_visita_nome) sai da frase como o do Tel já saía.
  v_fora := '\m(tel|' || regexp_replace(lower(nai_cfg('aprovador_visita_nome', 'Rayssa')), '[^a-zà-ú]', '', 'g') || ')\M';
  IF t.papel IN ('corretor', 'proprietario', 'motoboy') AND v_texto ~* v_fora THEN
    v_texto := nai_tirar_frase(v_texto, v_fora);
    v_guarda := coalesce(v_guarda || '+', '') || 'citou_quem_e_de_dentro';
    PERFORM nai_anotar(p_turno, 12, 'citou_o_tel', 'cortou', 'nome de quem é de dentro não vai para fora');$para$);
COMMIT;
