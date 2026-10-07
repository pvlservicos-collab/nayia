-- 304 (07/10/2026): a instrução da equipe pelo CRM passa a ser da Nay NOVA (nay-core).
--
-- Pedro, 07/10: "construa sim, quero a nay nova em tudo relacionado a novas conversas, incluindo isso, a nay antiga
-- será desativada futuramente para isso, não deixe nada faltando".
--
-- A 303 (de hoje cedo) era a ponte: corretor com instrução valendo ficava com a Nay velha, a única que lia a
-- instrução. Agora o núcleo lê e executa (nay-core, commits fa3fdc8 e a1ba0a8, migração 026 dele): o modelo
-- traduz a instrução num plano e a Nay de sempre faz, uma vez só, marcando em `core_instrucao_feita`. Provado
-- sobre as 15 instruções reais de 30/09 a 02/10 (`scripts/prova_instrucoes.py` no nay-core, só leitura).
--
-- 1. `nai_core_atende`: sai o WHEN da 303. O corretor com instrução segue a regra de todo mundo: vai para o
--    núcleo, menos quando fala de visita, tem visita em andamento, ficha de cadastro aberta ou mídia.
-- 2. `nai_instrucao_texto` (o cabeçalho da Nay velha): a instrução que o núcleo já executou não aparece mais.
--    Sem isso, um turno que ainda cai na velha (visita, mídia) faria a instrução de novo nas 48 h dela.
--    O caminho contrário já está no núcleo: ele não executa a instrução depois de a velha ter respondido um
--    turno do corretor com ela na frente (nay-core, nay/instrucao/repo.py).
BEGIN;

DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_core_atende(bigint,text)'::regprocedure);
  v_alvo text :=
       '    -- 303: instrução da equipe valendo (CRM, "instruir a Nay", 235): quem a lê é a Nay velha' || E'\n'
    || '    WHEN EXISTS (SELECT 1 FROM public.nai_instrucao i' || E'\n'
    || '                  WHERE i.contato_id = ANY (coalesce(public.nai_contato_irmaos(p_contato), ARRAY[p_contato]))' || E'\n'
    || '                    AND i.valido_ate > now()) THEN false' || E'\n';
  v_novo text;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '304: o WHEN da 303 em nai_core_atende não aparece exatamente uma vez';
  END IF;
  v_novo := replace(v_def, v_alvo,
       '    -- 304: a instrução da equipe (CRM) é lida e executada pelo núcleo (nay-core, nay/instrucao/):' || E'\n'
    || '    -- o corretor com instrução valendo segue a regra de todo mundo' || E'\n');
  EXECUTE v_novo;
END
$patch$;

DO $patch$
DECLARE
  v_def  text := pg_get_functiondef('public.nai_instrucao_texto(bigint)'::regprocedure);
  v_alvo text := '     AND i.valido_ate > now()';
  v_novo text;
BEGIN
  IF (length(v_def) - length(replace(v_def, v_alvo, ''))) / length(v_alvo) <> 1 THEN
    RAISE EXCEPTION '304: a linha da validade em nai_instrucao_texto não aparece exatamente uma vez';
  END IF;
  v_novo := replace(v_def, v_alvo, v_alvo || E'\n'
    || '     -- 304: a que o núcleo novo já executou não volta para o agente velho' || E'\n'
    || '     AND NOT EXISTS (SELECT 1 FROM core_instrucao_feita f WHERE f.instrucao_id = i.id)');
  EXECUTE v_novo;
END
$patch$;

COMMIT;
