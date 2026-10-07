-- 307 (07/10/2026): a visita que o sistema velho JÁ ESTAVA CONFIRMANDO com o corretor termina com ele.
--
-- A 306 (11:53) passou toda conversa de corretor para a Nay nova. Às 11:50 a Nay velha tinha mandado à corretora de
-- final 0860 a confirmação da visita ao Plaza Del Rey (#1084, amanhã 14:30) e esperava o "sim" dela. Com a 306 esse
-- "sim" iria para o núcleo, que não sabe dessa confirmação: a visita ficaria em `confirmando` até expirar, sem
-- proprietário, sem Rayssa e sem etapa Visitas.
--
-- `confirmando` só existe em visita que o sistema velho abriu: a ponte do núcleo (302) cria e confirma na mesma
-- transação. É também o estado em que ficam as perguntas de horário que o Tel faz pelos comandos dele. Então: quem
-- tem visita em `confirmando` mexida nas últimas 24 h continua com a velha, que é quem ouve essa resposta. Hoje é
-- uma visita só. Confirmou, cancelou ou passou o prazo: volta para o núcleo sozinho.
BEGIN;

DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_core_atende(bigint,text)'::regprocedure);
  v_alvo text := '    -- ficha de cadastro de imóvel aberta com a secretária';
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '307: a linha da ficha de cadastro em nai_core_atende não aparece exatamente uma vez';
  END IF;
  EXECUTE replace(v_def, v_alvo,
       '    -- 307: a visita que o sistema velho já estava confirmando com ele (ou a pergunta de horário de um' || E'\n'
    || '    -- comando do Tel) termina com o velho: é ele quem espera esse "sim". Só `confirmando`, por 24 h.' || E'\n'
    || '    WHEN EXISTS (SELECT 1 FROM public.nai_visita v' || E'\n'
    || '                  WHERE v.corretor_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))' || E'\n'
    || '                    AND v.estado = ''confirmando'' AND v.atualizado_em > now() - interval ''24 hours'') THEN false' || E'\n'
    || v_alvo);
END
$patch$;

COMMIT;
