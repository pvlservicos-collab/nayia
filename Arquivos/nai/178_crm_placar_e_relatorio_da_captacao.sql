-- 178 -- a barra da captação no CRM (Pedro, 29/09/2026: "quero outra linha
-- dessa lá em captação mostrando quantos contatados até agora no dia de hoje,
-- quantos disponíveis, quantos alugados, todos os status lá, e um botão enviar
-- relatório ao Tel").
--
-- crm_captacao_placar(): os números da barra. As etapas são as do funil do
-- CRM (a mesma regra de crm_captacao_funil, migração 172), para a barra bater
-- com as tags e o Pipeline.
--
-- crm_captacao_relatorio(): o MESMO texto do relatório das 18h (fluxo "Nay -
-- relatorio da captacao (18h)", NayRelatCaptac01, na VPS2), para o mesmo
-- número (captacao_config.telefone_relatorio). Diferenças, de propósito: diz
-- a hora ("até 12:50", porque sai no meio do dia) e sai também no fim de
-- semana -- quem apertou o botão quer o relatório. Sem telefone_relatorio,
-- telefone NULL e o CRM não manda. Só leitura: quem envia é o CRM, pela
-- linha da captação.

BEGIN;
SET LOCAL lock_timeout = '5s';

CREATE OR REPLACE FUNCTION crm_captacao_placar()
RETURNS TABLE(disparos_hoje int, falharam_hoje int, respostas_hoje int, pessoas_hoje int,
              nao_respondeu int, respondeu int, disponivel int, alugado int, vendido int, mandou_dados int,
              outro_imovel int, fila int, total int, sairam int, com_erro int, modo_teste boolean, pausada boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH agora AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS dia
  ), env AS (
    SELECT count(*) FILTER (WHERE m.status <> 'Falhou') AS ok,
           count(*) FILTER (WHERE m.status =  'Falhou') AS falhou
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), resp AS (
    SELECT count(*) AS msgs, count(DISTINCT m.lead_id) AS pessoas
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'recebida'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), etapa AS (
    SELECT CASE WHEN EXISTS (SELECT 1 FROM captacao_cadastro c WHERE c.lead_id = l.id AND c.estado = 'pronto') THEN 'dados'
                WHEN l.situacao = 'vendido' THEN 'vendido'
                WHEN l.situacao = 'alugado' THEN 'alugado'
                WHEN l.situacao = 'disponivel' THEN 'disponivel'
                WHEN l.respondeu_em IS NOT NULL THEN 'respondeu'
                ELSE 'nao' END AS e
      FROM captacao_leads l
     WHERE l.ultimo_envio_em IS NOT NULL
       AND coalesce(l.canal, '') <> 'oficial'
       AND coalesce(l.telefone, '') <> ''
  ), lead AS (
    SELECT count(*) AS total,
           count(*) FILTER (WHERE status = 'novo') AS fila,
           count(*) FILTER (WHERE tem_outro_imovel) AS outro,
           count(*) FILTER (WHERE opt_out) AS saiu,
           count(*) FILTER (WHERE status = 'erro') AS erro
      FROM captacao_leads
  )
  SELECT env.ok::int, env.falhou::int, resp.msgs::int, resp.pessoas::int,
         (SELECT count(*) FROM etapa WHERE e = 'nao')::int,
         (SELECT count(*) FROM etapa WHERE e = 'respondeu')::int,
         (SELECT count(*) FROM etapa WHERE e = 'disponivel')::int,
         (SELECT count(*) FROM etapa WHERE e = 'alugado')::int,
         (SELECT count(*) FROM etapa WHERE e = 'vendido')::int,
         (SELECT count(*) FROM etapa WHERE e = 'dados')::int,
         lead.outro::int, lead.fila::int, lead.total::int, lead.saiu::int, lead.erro::int,
         coalesce((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim') = 'sim',
         coalesce((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') = 'sim'
    FROM env, resp, lead
$$;

CREATE OR REPLACE FUNCTION crm_captacao_relatorio()
RETURNS TABLE(telefone text, mensagem text)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public SET jit = off AS $$
  WITH agora AS (
    SELECT (now() AT TIME ZONE 'America/Manaus')::date AS dia,
           to_char(now() AT TIME ZONE 'America/Manaus', 'HH24:MI') AS hora
  ), env AS (
    SELECT count(*) FILTER (WHERE m.status <> 'Falhou') AS ok,
           count(*) FILTER (WHERE m.status =  'Falhou') AS falhou
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'enviada' AND m.origem = 'disparo'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), resp AS (
    SELECT count(*) AS msgs, count(DISTINCT m.lead_id) AS pessoas
      FROM captacao_mensagens m, agora a
     WHERE m.direcao = 'recebida'
       AND (m.criada_em AT TIME ZONE 'America/Manaus')::date = a.dia
  ), lead AS (
    SELECT count(*)                                        AS total,
           count(*) FILTER (WHERE status = 'novo')         AS fila,
           count(*) FILTER (WHERE situacao = 'disponivel') AS disp,
           count(*) FILTER (WHERE situacao = 'alugado')    AS alug,
           count(*) FILTER (WHERE situacao = 'vendido')    AS vend,
           count(*) FILTER (WHERE tem_outro_imovel)        AS outro,
           count(*) FILTER (WHERE opt_out)                 AS saiu,
           count(*) FILTER (WHERE status = 'erro')         AS erro
      FROM captacao_leads
  ), cfg AS (
    SELECT nullif(btrim((SELECT valor FROM captacao_config WHERE chave = 'telefone_relatorio')), '') AS fone,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'modo_teste'), 'sim')       AS teste,
           coalesce((SELECT valor FROM captacao_config WHERE chave = 'captacao_pausada'), 'sim') AS pausada
  )
  SELECT cfg.fone,
    '📊 Captação — ' || to_char(a.dia, 'DD/MM') || ', até ' || a.hora
    || E'\n\n'
    || 'Disparos hoje: ' || env.ok
    || CASE WHEN env.falhou > 0 THEN '  ⚠️ ' || env.falhou || ' falharam' ELSE '' END
    || E'\n'
    || 'Respostas hoje: ' || resp.msgs
    || CASE WHEN resp.pessoas > 0 THEN ' (de ' || resp.pessoas || ' pessoas)' ELSE '' END
    || E'\n\n'
    || E'Descoberto até agora:\n'
    || '• disponíveis: ' || lead.disp || E'\n'
    || '• alugados: '    || lead.alug || E'\n'
    || '• já venderam: ' || lead.vend || E'\n'
    || '• com outro imóvel: ' || lead.outro
    || E'\n\n'
    || 'Fila: ' || lead.fila || ' de ' || lead.total || ' ainda não chamados'
    || CASE WHEN lead.saiu > 0 THEN E'\n' || lead.saiu || ' pediram para sair' ELSE '' END
    || CASE WHEN lead.erro > 0 THEN E'\n⚠️ ' || lead.erro || ' com erro de envio' ELSE '' END
    || CASE WHEN cfg.teste = 'sim'
            THEN E'\n\n🧪 MODO TESTE LIGADO — nenhum proprietário recebeu nada.'
            ELSE '' END
    || CASE WHEN cfg.pausada = 'sim'
            THEN E'\n\n⏸️ DISPARO PAUSADO.'
            ELSE '' END
    || CASE WHEN env.ok = 0 AND cfg.teste = 'nao' AND cfg.pausada = 'nao' AND lead.fila > 0
            THEN E'\n\n⚠️ NENHUM DISPARO HOJE com fila cheia e campanha ligada. Algo travou.'
            ELSE '' END
  FROM agora a, env, resp, lead, cfg
$$;

REVOKE ALL ON FUNCTION crm_captacao_placar(), crm_captacao_relatorio() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crm_captacao_placar(), crm_captacao_relatorio() TO nay_disparo;

COMMIT;
