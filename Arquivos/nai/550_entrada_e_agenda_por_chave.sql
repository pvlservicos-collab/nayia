-- 550 (Pedro, 31/10/2026: "tire tudo do n8n quero tudo em python"). As chaves que passam cada parte do n8n para o
-- Python, uma de cada vez, e que voltam atrás na hora. Todas nascem em 'n8n': aplicada, nada muda.
--   nai_config.entrada          n8n | sombra | python   quem recebe a Parceria (a porta do nay-core, fork D)
--   nai_config.agenda_de        n8n | python            quem roda a agenda da Nay velha (nai_agenda_tick) e libera o
--                                                       que ela inicia (nay-publicador/agenda_nai.py)
--   captacao_config.entrada     n8n | sombra | python   quem recebe o 8595 (a porta do nay-core)
--   captacao_config.rotinas_de  n8n | python            o vigia do número e o relatório do dia (nay-captacao/rotinas.py)
--
-- As guardas ficam no BANCO, para os dois chamadores poderem rodar ao mesmo tempo sem mandar nada duas vezes:
--   nai_agenda_tick(p_quem)           só roda para quem é dono da agenda (o n8n chama sem argumento = 'n8n')
--   nai_liberar_saida(p_turno)        o embrulho de 1 argumento é SÓ do n8n ("Liberar saída"): sem turno (agenda) só
--                                     com agenda_de = n8n; com turno, só enquanto a entrada da Parceria não é python.
--                                     O Python chama a de 2 argumentos direto (como o enviador manual já faz).
--   captacao_vigiar(p_quem)           idem, com rotinas_de
--   captacao_relatorio_da_vez(p_quem) idem, com rotinas_de
-- O corpo das funções antigas não muda: elas são RENOMEADAS para *_rodar e o nome antigo vira a guarda.
BEGIN;
SET LOCAL lock_timeout = '5s';

INSERT INTO nai_config (chave, valor, descricao) VALUES
  ('entrada', 'n8n', '550: quem recebe a Parceria. n8n | sombra (a porta Python grava ao lado, para comparar) | python'),
  ('agenda_de', 'n8n', '550: quem roda a agenda da Nay velha (nai_agenda_tick) e libera o que ela inicia. n8n | python')
ON CONFLICT (chave) DO NOTHING;
INSERT INTO captacao_config (chave, valor, nota) VALUES
  ('entrada', 'n8n', '550: quem recebe o 8595. n8n | sombra | python'),
  ('rotinas_de', 'n8n', '550: quem roda o vigia do número e o relatório do dia. n8n | python (nay-captacao/rotinas.py)')
ON CONFLICT (chave) DO NOTHING;

-- a agenda da Nay velha
ALTER FUNCTION public.nai_agenda_tick() RENAME TO nai_agenda_tick_rodar;
CREATE FUNCTION public.nai_agenda_tick(p_quem text DEFAULT 'n8n')
 RETURNS integer
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 550: só o dono da agenda roda (o nó "Agenda da NAI" do n8n chama sem argumento)
  IF coalesce(nullif(btrim(nai_cfg('agenda_de', 'n8n')), ''), 'n8n') <> p_quem THEN
    RETURN 0;
  END IF;
  RETURN nai_agenda_tick_rodar();
END
$function$;

-- a liberação que o n8n faz depois da agenda e de cada turno
CREATE OR REPLACE FUNCTION public.nai_liberar_saida(p_turno bigint)
 RETURNS TABLE(id bigint, rota text, telefone text, chave_esperada text, corpo jsonb, codigo integer, papel text, redirecionado boolean)
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 301: o n8n ("Liberar saída") só entrega o que é da Nay; a entrega manual é do enviador_manual.py
  -- 550: e só enquanto a parte for dele -- sem turno é a agenda (agenda_de); com turno é a entrada da Parceria.
  -- A guarda vem ANTES de chamar: a liberação marca as linhas 'enviando', e linha marcada que ninguém manda se perde.
  IF (p_turno IS NULL AND coalesce(nullif(btrim(nai_cfg('agenda_de', 'n8n')), ''), 'n8n') <> 'n8n')
     OR (p_turno IS NOT NULL AND coalesce(nullif(btrim(nai_cfg('entrada', 'n8n')), ''), 'n8n') = 'python') THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM public.nai_liberar_saida(p_turno, false);
END
$function$;

-- o vigia e o relatório da captação
ALTER FUNCTION public.captacao_vigiar() RENAME TO captacao_vigiar_rodar;
CREATE FUNCTION public.captacao_vigiar(p_quem text DEFAULT 'n8n')
 RETURNS text
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'rotinas_de')), ''), 'n8n') <> p_quem THEN
    RETURN NULL;
  END IF;
  RETURN captacao_vigiar_rodar();
END
$function$;

ALTER FUNCTION public.captacao_relatorio_da_vez() RENAME TO captacao_relatorio_da_vez_rodar;
CREATE FUNCTION public.captacao_relatorio_da_vez(p_quem text DEFAULT 'n8n')
 RETURNS TABLE(phone text, message text, "delayMessage" integer)
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- o relatório marca o dia ao sair (_relatorio_dia): quem não é o dono nem chega a chamar
  IF coalesce(nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'rotinas_de')), ''), 'n8n') <> p_quem THEN
    RETURN;
  END IF;
  RETURN QUERY SELECT * FROM captacao_relatorio_da_vez_rodar();
END
$function$;

COMMIT;
