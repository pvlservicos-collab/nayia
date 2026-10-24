-- 482 -- O PV do Tel só recebe PERGUNTAS
--
-- Pedro, 24/10/2026: "o que é toda mensagem mandada para o Tel ... quero que pare de mandar coisas para ele no PV fora as
-- perguntas ... deixa só as perguntas por enquanto". Em 3 dias entraram no PV dele ~380 mensagens, 248 só da cobrança
-- "Ainda sem resposta, Pergunta N/N" (a fila de perguntas cobrava a mesma a cada 10 min), mais escaladas e avisos da
-- captação, avisos da Nay Parceria (corretor mandou imagem, pediu visita), acompanhante, "quem não está nos grupos", etc.
--
-- Um gatilho em cada caixa (nai_saida e core_saida): saída para o papel 'tel' que não é pergunta nasce 'bloqueado', com o
-- motivo "o Tel só recebe perguntas (482)": fica na tabela (nada se perde, dá para ver o que foi barrado), mas não sai.
-- Passam: pergunta_fila (a pergunta da fila), aviso_saida_pergunta (imóvel que saiu do ar: pede o SIM dele) e
-- secretaria_pergunta. Os avisos "Tel, o corretor X ... Para eu entregar a resposta a ele: DEVOLVER" já viram pergunta da
-- fila pelo gatilho da 391 (core_saida_pergunta_na_fila) e continuam assim.
-- A cobrança (pergunta_fila_cobranca) também é barrada, e o intervalo dela vai para 100000 min para a fila nem tentar.
-- Desligar: UPDATE nai_config SET valor = 'nao' WHERE chave = 'tel_so_perguntas'.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO nai_config (chave, valor) VALUES ('tel_so_perguntas', 'sim')
ON CONFLICT (chave) DO UPDATE SET valor = 'sim';
UPDATE nai_config SET valor = '100000' WHERE chave = 'pergunta_fila_cobrar_min';

CREATE OR REPLACE FUNCTION public.nai_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public'
AS $function$
BEGIN
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim'
     AND coalesce(NEW.motivo, '') NOT IN ('pergunta_fila', 'aviso_saida_pergunta', 'secretaria_pergunta') THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'nai_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;

CREATE OR REPLACE FUNCTION public.core_saida_tel_so_perguntas()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  -- tudo que a Nay nova manda ao Tel (aviso_tel) é aviso: a pergunta ao corretor já foi para a fila (391) e não passa aqui
  IF NEW.papel_destino = 'tel' AND NEW.estado = 'pendente'
     AND coalesce(nai_cfg('tel_so_perguntas', 'nao'), 'nao') = 'sim' THEN
    NEW.estado := 'bloqueado';
    NEW.bloqueio := 'o Tel só recebe perguntas (482)';
  END IF;
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'core_saida_tel_so_perguntas: %', SQLERRM;
  RETURN NEW;
END
$function$;

DROP TRIGGER IF EXISTS nai_saida_zzz_tel_so_perguntas ON public.nai_saida;
CREATE TRIGGER nai_saida_zzz_tel_so_perguntas BEFORE INSERT ON public.nai_saida
  FOR EACH ROW EXECUTE FUNCTION nai_saida_tel_so_perguntas();
DROP TRIGGER IF EXISTS core_saida_zzz_tel_so_perguntas ON public.core_saida;
CREATE TRIGGER core_saida_zzz_tel_so_perguntas BEFORE INSERT ON public.core_saida
  FOR EACH ROW EXECUTE FUNCTION core_saida_tel_so_perguntas();

COMMIT;
