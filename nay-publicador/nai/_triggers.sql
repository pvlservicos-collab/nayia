-- OS TRIGGERS DA NAI. Sem estas tres linhas, restaurar as funcoes deste
-- diretorio nao religa nada: funcao existe e trigger nao dispara.
--
-- `nai_saida_validar` e o porteiro da fila de saida -- nada vai para o
-- WhatsApp sem passar por ele. Foi nele o bug de 30/09 que deixou a agenda
-- seis horas morta.

CREATE TRIGGER nai_saida_imutavel BEFORE UPDATE ON public.nai_saida FOR EACH ROW EXECUTE FUNCTION nai_saida_imutavel();
CREATE TRIGGER nai_saida_validar BEFORE INSERT ON public.nai_saida FOR EACH ROW EXECUTE FUNCTION nai_saida_validar();
CREATE TRIGGER nai_turno_pergunta_corretor AFTER INSERT ON public.nai_turno FOR EACH ROW WHEN ((new.porta = 'fora da lista: perguntou de imovel, perguntar ao Tel'::text)) EXECUTE FUNCTION nai_perguntar_se_e_corretor();
