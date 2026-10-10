-- 342 -- Captação: quem já recebeu mensagem nossa entra na lista de "não disparar" (só follow-up daqui para a frente)
--
-- Pedro, 10/10/2026, ao pedir a lista dos contratos a vencer em agosto, setembro e outubro: "só lembra de colocar em
-- blacklist todos que já receberam, esses não receberão novas msgs a não ser follow up".
--
-- `captacao_nao_disparar` é a lista que o disparo do modelo oficial pula (317). Só `captacao_py_fila_do_disparo` a
-- lê: o lembrete (follow-up) e a conversa com quem responde NÃO passam por ela, então continuam como estão.
--
-- Entra quem já recebeu qualquer mensagem da captação, por qualquer número: a abertura antiga pela Z-API, o modelo
-- oficial (`captacao_motor`) ou resposta da Nay. Em 10/10 são 343 dos 365 leads. Os outros 22 já estão parados por
-- outra parede (7 corretores, 12 com quem o Tel escreveu pelo celular, 3 sem WhatsApp) e ficam como estão.
--
-- A fila de hoje não muda (está em 0): isto é a garantia de que nenhuma lista nova, retomada ou mudança de status
-- devolve essas pessoas ao disparo.
BEGIN;
SET LOCAL lock_timeout = '3s';

INSERT INTO captacao_nao_disparar (telefone_chave, motivo)
SELECT l.telefone_chave, 'já recebeu mensagem da captação (até 10/10/2026): só follow-up'
  FROM captacao_leads l
 WHERE coalesce(l.telefone_chave, '') <> ''
   AND (l.ultimo_envio_em IS NOT NULL
        OR EXISTS (SELECT 1 FROM captacao_motor mt WHERE mt.lead_id = l.id)
        OR EXISTS (SELECT 1 FROM captacao_mensagens m
                    WHERE nay_fone_chave(m.telefone) = l.telefone_chave AND m.direcao = 'enviada' AND m.status <> 'Falhou'))
ON CONFLICT (telefone_chave) DO NOTHING;

COMMIT;
