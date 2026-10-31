-- 547 (Pedro, 31/10/2026: "corrije o resto", a revisão da Parceria de 30/10, tipo 4: "ficou de voltar e não voltou").
-- Três promessas ficaram sem dono:
--   1. "Recebi, Thiago! Já te respondo por aqui" depois de uma imagem (…6938 08:34, …1259 11:49). O aviso ao Tel foi
--      bloqueado pela 482 (o Tel só recebe perguntas) e, ao contrário da escalada, não ia ao CRM. Agora o aviso de mídia
--      bloqueado vai às Notificações do CRM (tipo 'midia', o caminho da 508).
--   2. A escalada sem resposta (…8345 Gaspar 09:29, …8383 Gilson 11:10): a notificação ficou sem ler e a conversa calada
--      por 24 h (escalacao_expira_horas). Agora nay_cobrar_escaladas() cobra a equipe nas Notificações depois de 30 min
--      sem ninguém responder (e de novo quando ele escreve mais, de 20 em 20 min), e a conversa volta à Nay em 2 h.
--      Roda pelo cron de 5 em 5 min (/etc/cron.d/nay-cobrar-escaladas).
--   3. O agente de revisão escreveu ao corretor "vou levar a sua proposta de R$ 2.000 ... (9047) ao proprietário e já te
--      respondo" (…6529 11:10) sem abrir dúvida nenhuma. Agora a correção do agente que promete levar algo ao
--      proprietário abre a dúvida (core_pendencia), que o nay-olx (duvidas.py, 512) acompanha até a resposta.
BEGIN;
SET LOCAL lock_timeout = '3s';

-- 1 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.core_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_m text[];
BEGIN
  -- tudo que a Nay nova manda ao Tel (aviso_tel) é aviso: a pergunta ao corretor já foi para a fila (391) e não passa aqui
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim' THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
    -- 547: o aviso de MÍDIA ("Tel, o corretor X (55...) mandou 1 imagem(ns)") não tinha outro caminho: vai ao CRM
    v_m := regexp_match(coalesce(NEW.texto, ''), '^Tel, o corretor (.{1,80}?) \((\d{10,15})\) mandou \d+ ');
    IF v_m IS NOT NULL THEN
      PERFORM nay_aviso_equipe('nay-core', 'midia', v_m[1] || ' mandou mídia (Parceria)', NEW.texto, v_m[2]);
      NEW.bloqueio := 'o Tel só recebe perguntas (482); a mídia foi às Notificações do CRM (547)';
    END IF;
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;

-- 2 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.nay_cobrar_escaladas()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'privado'
AS $function$
-- A conversa que o núcleo escalou (nai_core_escalou: humano_motivo 'duvida fora da base (nay-core): ...') e que ninguém
-- assumiu: a 1ª cobrança aos 30 min; depois, só quando ele escreve de novo, no máximo de 20 em 20 min. Quem responde
-- pelo celular ou pelo CRM troca a marca ("o Tel escreveu pelo celular") e a cobrança para.
DECLARE
  r       record;
  v_ult   timestamptz;
  v_novas text;
  v_orig  text;
  n       int := 0;
BEGIN
  FOR r IN
    SELECT c.chave, c.humano_assumiu_em AS desde, c.humano_motivo,
           coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(c.nome_whatsapp), ''), 'Corretor') AS nome
      FROM nai_contato c
     WHERE c.humano_motivo LIKE 'duvida fora da base (nay-core)%'
       AND c.chave ~ '^\d{10,15}$'
       AND c.humano_assumiu_em < now() - interval '30 minutes'
       AND c.humano_assumiu_em > now() - make_interval(hours => greatest(nai_cfg_int('escalacao_expira_horas', 24), 1))
  LOOP
    SELECT max(a.criado_em) INTO v_ult FROM aviso_equipe a
     WHERE a.fonte = 'nay-core-cobranca' AND right(a.telefone, 8) = right(r.chave, 8) AND a.criado_em > r.desde;
    SELECT string_agg(to_char(m.criada_em AT TIME ZONE 'America/Manaus', 'HH24:MI') || ' "' || left(btrim(m.texto), 300) || '"',
                      E'\n' ORDER BY m.criada_em)
      INTO v_novas
      FROM mensagens m
     WHERE m.direcao = 'recebida' AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(r.chave, 8)
       AND m.criada_em > coalesce(v_ult, r.desde) AND btrim(coalesce(m.texto, '')) <> ''
       AND lower(unaccent(btrim(m.texto))) !~ '^\W*(ok|okay|blz|beleza|obrigad[oa]|valeu|vlw|certo|sim|show|top|perfeito|combinado|ta bom|tudo bem)\W*$';
    IF v_ult IS NOT NULL AND (v_novas IS NULL OR v_ult > now() - interval '20 minutes') THEN
      CONTINUE;
    END IF;
    SELECT a.texto INTO v_orig FROM aviso_equipe a
     WHERE a.fonte = 'nay-core' AND a.tipo = 'escalada' AND right(a.telefone, 8) = right(r.chave, 8)
       AND a.criado_em BETWEEN r.desde - interval '5 minutes' AND r.desde + interval '5 minutes'
     ORDER BY a.id DESC LIMIT 1;
    PERFORM nay_aviso_equipe('nay-core-cobranca', 'escalada',
      r.nome || ' ainda espera a equipe (Parceria)',
      'Ninguém respondeu ' || r.nome || ' desde ' || to_char(r.desde AT TIME ZONE 'America/Manaus', 'HH24:MI')
      || ' (' || replace(r.humano_motivo, 'duvida fora da base (nay-core): ', '') || '). A Nay está calada nessa conversa até '
      || to_char((r.desde + make_interval(hours => greatest(nai_cfg_int('escalacao_expira_horas', 24), 1))) AT TIME ZONE 'America/Manaus', 'HH24:MI')
      || '.' || coalesce(E'\nEle escreveu depois:\n' || v_novas, '') || coalesce(E'\n\nO aviso: ' || v_orig, ''),
      r.chave);
    n := n + 1;
  END LOOP;
  RETURN n;
END
$function$;
REVOKE ALL ON FUNCTION public.nay_cobrar_escaladas() FROM PUBLIC;

-- o silêncio da escalada: 24 h -> 2 h (vale para a marca 'duvida fora da base' e 'midia', nai_tel_com_a_conversa)
UPDATE nai_config SET valor = '2', atualizado_em = now(),
       descricao = coalesce(descricao || ' | ', '') || '547 (31/10): 24 -> 2, com cobrança da equipe aos 30 min'
 WHERE chave = 'escalacao_expira_horas' AND valor = '24';

-- 3 ─────────────────────────────────────────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.core_saida_promessa_do_agente()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  s   text;
  v_c integer;
BEGIN
  IF NEW.motivo IS DISTINCT FROM 'correcao_do_agente' OR NEW.papel_destino <> 'turno' OR NEW.tipo <> 'texto' THEN
    RETURN NEW;
  END IF;
  s := lower(unaccent(coalesce(NEW.texto, '')));
  -- "vou levar a sua proposta ao proprietário", "vou confirmar com o dono", "vou perguntar ao proprietário"
  -- (o "R$ 2.000" tem ponto: a frase só termina em ! ? ou quebra de linha)
  IF s !~ '\m(vou|vamos|irei)\M[^!?\n]{0,60}\m(levar|passar|confirmar|consultar|perguntar|verificar|checar|falar|ver)\M[^!?\n]{0,80}\m(proprietari[oa]s?|don[oa]s?)\M' THEN
    RETURN NEW;
  END IF;
  v_c := coalesce(NEW.codigo, (regexp_match(s, '(?:codigo|cod\.?|#)\s*(\d{3,5})'))[1]::int);
  IF EXISTS (SELECT 1 FROM core_pendencia p WHERE p.chave = NEW.chave_destino AND p.criado_em > now() - interval '2 hours'
                AND coalesce(p.codigo, 0) = coalesce(v_c, 0)) THEN
    RETURN NEW;                                   -- o agente (ou a Nay) já abriu a dúvida
  END IF;
  INSERT INTO core_pendencia (turno_id, chave, codigo, pergunta, faltou)
  VALUES (NEW.turno_id, NEW.chave_destino, v_c,
          'O agente prometeu ao corretor levar ao proprietário: "' || left(btrim(NEW.texto), 600) || '"',
          ARRAY['promessa do agente (547)']);
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_promessa_do_agente: %', SQLERRM;   -- a mensagem do agente sai de qualquer jeito
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS core_saida_promessa_do_agente ON public.core_saida;
CREATE TRIGGER core_saida_promessa_do_agente AFTER INSERT ON public.core_saida
  FOR EACH ROW EXECUTE FUNCTION core_saida_promessa_do_agente();

COMMIT;
