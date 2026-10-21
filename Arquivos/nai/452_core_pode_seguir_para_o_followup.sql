-- 452 (21/10/2026): a ponte que diz ao núcleo novo (nay-core) se ele pode MANDAR SOZINHO uma mensagem a um corretor.
-- Pedro, 21/10: "um followup após a confirmação da visita se o corretor não responder que confirmou" e "followup
-- depois se o corretor disser que vai falar com o cliente pela visita mas não falou de verdade umas 1 hr depois:
-- 'E aí, seu cliente confirmou?'". O núcleo só responde o que a porta (nai_abrir_turno) entrega; o follow-up não
-- tem mensagem chegando, então não passa pela porta. Esta função faz as mesmas perguntas que a porta faria,
-- sem gravar nada: NULL = pode mandar; senão, o motivo de não mandar.
--   modo da NAI desligado/teste, pausa geral (PARAR), Tel com a conversa, gente da equipe escreveu há pouco,
--   visita/fechamento/proprietário com a Rayssa, e o que nai_core_atende devolve ao velho (equipe, visita que o
--   velho está confirmando, cadastro aberto, canário, contato de teste).
-- Desfazer: DROP FUNCTION public.nai_core_pode_seguir(text);
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.nai_core_pode_seguir(p_chave text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_contato bigint;
  v_irmaos  bigint[];
  v_rayssa  text;
BEGIN
  IF nai_cfg('modo', 'desligado') <> 'todos' THEN RETURN 'nai_desligada'; END IF;
  IF nai_cfg('pausada', 'sim') <> 'nao' THEN RETURN 'pausada'; END IF;
  SELECT id INTO v_contato FROM nai_contato WHERE chave = p_chave ORDER BY id LIMIT 1;
  IF v_contato IS NULL THEN RETURN 'sem_contato'; END IF;
  v_irmaos := coalesce(nai_contato_irmaos(v_contato), ARRAY[v_contato]);
  IF nai_tel_com_a_conversa(v_contato) THEN RETURN 'tel_assumiu'; END IF;
  IF nai_gente_escreveu_ha_pouco(v_irmaos) THEN RETURN 'gente_escreveu'; END IF;
  v_rayssa := nai_com_a_rayssa(v_contato, 'corretor');
  IF v_rayssa IS NOT NULL THEN RETURN v_rayssa; END IF;
  IF NOT nai_core_atende(v_contato, '') THEN RETURN 'nao_e_do_core'; END IF;
  RETURN NULL;
END $function$;

COMMENT ON FUNCTION public.nai_core_pode_seguir(text) IS
  '452: NULL = o nay-core pode mandar o follow-up a esta chave agora; senão o motivo (as mesmas portas de nai_abrir_turno).';
REVOKE ALL ON FUNCTION public.nai_core_pode_seguir(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nai_core_pode_seguir(text) TO nay_core;

COMMIT;
