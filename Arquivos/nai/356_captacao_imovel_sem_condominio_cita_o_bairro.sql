-- 356 -- Captação: "o imóvel no Casa" -- quando o condomínio do cadastro é só o TIPO, a frase cita o bairro
--
-- 12/10/2026, a conversa que o Tel repassou (final 1676): "É para atualizar o valor atual da locação do imóvel no Casa."
-- No cadastro, casa de rua tem "Casa" no campo do condomínio (e prédio inteiro tem "Prédio", apartamento de rua tem
-- "Apartamento em Via Pública"). A 353 montou `imovel_desc` como a rota de importação monta ("no " + condomínio), e
-- esses saíram "no Casa", "no Prédio". A 343 já tratava "Condomínio não identificado" assim: cita o bairro.
--
-- Vale para os leads que ainda estão em conversa ou na fila; quem já concluiu fica como está (é histórico).
-- A outra metade da queixa (pedir "o valor para locação" de imóvel que anunciamos à VENDA) é do serviço:
-- nay-captacao/captacao/venda.py, no ar em 12/10 19:23.
BEGIN;
SET LOCAL lock_timeout = '3s';

UPDATE captacao_leads l
   SET imovel_desc = 'no bairro ' || btrim(l.bairro), atualizado_em = now()
 WHERE coalesce(btrim(l.bairro), '') <> ''
   AND l.status IN ('novo', 'enviado', 'respondendo', 'erro')
   AND l.imovel_desc = 'no ' || btrim(l.condominio)
   AND (lower(btrim(l.condominio)) = lower(btrim(coalesce(l.tipo_imovel, '')))
        OR btrim(l.condominio) ~* '^(casa|sobrado|pr[eé]dio|terreno|lote|sala|galp[aã]o|apartamento|loja|ponto comercial|s[ií]tio|ch[aá]cara|kitnet)( (em|de) (via p[uú]blica|rua))?$');

COMMIT;
