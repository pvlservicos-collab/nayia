CREATE OR REPLACE FUNCTION public.mensagens_espera_a_rajada()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
BEGIN
  -- 147: A MAIS NOVA TAMBEM ESPERA. A conta excluia a propria mensagem
  -- (`m2.id <> NEW.id`): a execucao de uma antiga segurava as antigas e deixava
  -- a MAIS NOVA sair sozinha, antes da hora. Taysa, 28/09 11:19: "Semi
  -- mobiliado" e "?!" viraram turnos proprios, cada um com a sua resposta.
  -- Agora nenhuma sai enquanto qualquer uma dele -- ela inclusive -- for mais
  -- nova que a janela; quem junta tudo e a execucao da ultima.
  -- A janela e por pessoa: 20 s para todo mundo, e a dos testes internos a parte.
  IF OLD.status = 'Recebido' AND NEW.status = 'Processando'
     AND NEW.fluxo = 'nai' AND NEW.direcao = 'recebida'
     AND EXISTS (SELECT 1 FROM mensagens m2
                  WHERE m2.telefone = NEW.telefone AND m2.fluxo = 'nai' AND m2.direcao = 'recebida'
                    AND m2.status = 'Recebido'
                    AND m2.criada_em > now() - make_interval(secs => greatest(nai_janela_segundos(NEW.telefone) - 1, 1))) THEN
    RETURN NULL;   -- ainda tem mensagem dele dentro da janela: quem junta e a execucao da ultima
  END IF;
  RETURN NEW;
END;
$function$;
