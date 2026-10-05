-- 291a (05/10/2026): A PAREDE DA 291. Pedro: "ela mandou 2 vezes para o mesmo proprietário, isso
-- nunca pode acontecer".
--
-- O disparo da captação pega quem está com `status IN ('novo', 'erro')` (o SQL mora no fluxo do
-- n8n da VPS2, nó "Pegar lead novo"). Quem já recebeu mensagem nossa só recebe a abertura de novo
-- se alguém puser a pessoa de volta num desses dois status: foi o que a fila refeita de 28/09 fez
-- com 109 donos, e é o que o "destravar" do próprio fluxo faria se um envio fosse gravado e o
-- `ultimo_envio_em` não.
--
-- A parede: um lead que JÁ RECEBEU mensagem nossa por esse número (qualquer origem, menos a que
-- falhou) nunca volta para 'novo' nem para 'erro'. A tentativa não dá erro (erro deixaria o lead
-- preso e pararia a fila, como em 29/09): o status fica como estava; se vinha de 'reservado', vira
-- 'respondendo' (a pessoa já escreveu) ou 'enviado'. Quem nunca recebeu nada passa normalmente.
--
-- Para chamar alguém de novo DE PROPÓSITO (uma retomada com outro texto), o caminho é uma coluna
-- ou uma tabela própria de retomada, não o status 'novo': é assim que a abertura não se repete.
--
-- Arquivo curto e só de esquema, com trava de 3 s, como manda a regra do DDL no banco vivo.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE OR REPLACE FUNCTION public.captacao_ja_chamado_nao_volta()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status IN ('novo', 'erro') AND OLD.status IS DISTINCT FROM NEW.status
     AND EXISTS (SELECT 1 FROM captacao_mensagens m
                  WHERE m.lead_id = NEW.id AND m.direcao = 'enviada'
                    AND coalesce(m.status, '') <> 'Falhou') THEN
    -- quem já estava num status de "chamado" fica onde estava; quem vinha de 'reservado' ganha o seu
    NEW.status := CASE WHEN OLD.status IN ('enviado', 'respondendo', 'concluido', 'sem_whatsapp') THEN OLD.status
                       WHEN EXISTS (SELECT 1 FROM captacao_mensagens m
                                     WHERE m.lead_id = NEW.id AND m.direcao = 'recebida')
                       THEN 'respondendo' ELSE 'enviado' END;
  END IF;
  RETURN NEW;
END $function$;

DROP TRIGGER IF EXISTS captacao_ja_chamado_nao_volta ON public.captacao_leads;
CREATE TRIGGER captacao_ja_chamado_nao_volta
  BEFORE UPDATE OF status ON public.captacao_leads
  FOR EACH ROW EXECUTE FUNCTION public.captacao_ja_chamado_nao_volta();

COMMIT;
