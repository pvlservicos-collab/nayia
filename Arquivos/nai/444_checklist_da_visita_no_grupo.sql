-- 444: O CHECKLIST DA VISITA NO GRUPO ALTARQUIA (Pedro, 20/10/2026: "põe aí uma opção dela avisar lá no grupo Altarquia
-- Imobeasy quando ela não conseguir falar com o proprietário, e um checklist de visita agendada mostrando se ela falou com
-- todos, só nome de imóvel, aí uma lista marcada com o que ela conseguiu falar (v) proprietário (v) corretor (v) motoboy";
-- perguntado: o checklist vai no grupo, a Nay avisa o motoboy (443), e o proprietário sem resposta em 1 hora vira aviso).
--
-- Quem escreve no grupo é o nay-olx (olx/visitas_parceria.py, pelo mesmo caminho do aviso do grupo da equipe). Aqui:
--   privado.visitas_parceria_situacao()   cada visita que a Nay passou à Rayssa (evento com_a_rayssa) nos últimos 3 dias:
--                                         o nome do imóvel, o dia, o corretor, e o que saiu e o que voltou do proprietário
--                                         e do motoboy (nai_saida + mensagens recebidas depois)
--   privado.visitas_parceria_sem_visita() o "Anotei a sua visita" da Nay nova que não virou visita (a ponte falhou): o
--                                         proprietário não foi chamado
--   privado.visita_parceria_grupo         o que já foi para o grupo de cada visita (o checklist sai de novo quando muda)
--   privado.visita_ponte_aviso            o "anotei" que já foi avisado
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.visita_parceria_grupo (
  visita_id              bigint PRIMARY KEY,
  assinatura             text,
  checklist_em           timestamptz,
  alerta_dono_em         timestamptz,
  alerta_sem_resposta_em timestamptz,
  atualizado_em          timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS privado.visita_ponte_aviso (
  core_saida_id bigint PRIMARY KEY,
  avisado_em    timestamptz NOT NULL DEFAULT now()
);

-- "só nome de imóvel": o condomínio; o "condomínio" que é só o tipo ("Casa", 75 no cadastro) vira o tipo e o bairro
CREATE OR REPLACE FUNCTION privado.nome_do_imovel(p_codigo integer) RETURNS text
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  SELECT coalesce(CASE WHEN nai_condominio_ok(i.condominio_nome) !~* '^\s*(casa|apartamento|apto|sala|loja|terreno|lote|kitnet|flat|cobertura|im[oó]vel|condom[ií]nio|pr[eé]dio|galp[aã]o)\M'
                       THEN nai_condominio_ok(i.condominio_nome) END,
                  btrim(coalesce(nullif(btrim(i.tipo), ''), 'Imóvel') || coalesce(' no ' || nullif(btrim(i.bairro), ''), '')))
    FROM imoveis i WHERE i.codigo = p_codigo
$f$;

CREATE OR REPLACE FUNCTION privado.visitas_parceria_situacao()
RETURNS TABLE (visita_id bigint, codigo integer, imovel text, quando timestamptz, corretor text,
               dono_nome text, dono text, dono_enviado_em timestamptz, dono_respondeu boolean,
               moto_nome text, moto text, moto_respondeu boolean, criada_em timestamptz)
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  SELECT v.id, v.codigo,
         privado.nome_do_imovel(v.codigo) AS imovel,
         v.quando,
         coalesce(nullif(btrim(c.nome_completo), ''), nullif(btrim(c.nome_whatsapp), ''), 'corretor') AS corretor,
         coalesce(v.proprietario_nome, d.nome) AS dono_nome,
         -- o proprietário: enviado | pendente | bloqueado: o motivo | sem: o motivo do cadastro
         CASE WHEN sp.estado = 'enviado' THEN 'enviado'
              WHEN sp.estado IN ('pendente', 'enviando') THEN 'pendente'
              WHEN sp.estado IS NOT NULL THEN 'bloqueado: ' || coalesce(sp.bloqueio, sp.estado)
              ELSE 'sem: ' || CASE d.motivo WHEN 'sem_telefone' THEN 'sem telefone no cadastro'
                                            WHEN 'tratar_com_outra_pessoa' THEN 'o cadastro diz para tratar com outra pessoa'
                                            WHEN 'dois_donos' THEN 'o imóvel tem dois proprietários no cadastro'
                                            WHEN 'sem_cadastro' THEN 'imóvel sem proprietário cadastrado'
                                            ELSE 'o telefone do proprietário é o do próprio corretor' END END AS dono,
         sp.enviado_em AS dono_enviado_em,
         EXISTS (SELECT 1 FROM mensagens m JOIN nai_contato k ON k.id = v.proprietario_id
                  WHERE m.direcao = 'recebida' AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(k.chave, 8)
                    AND m.criada_em > coalesce(sp.enviado_em, sp.criado_em)) AS dono_respondeu,
         mo.nome AS moto_nome,
         CASE WHEN sm.estado = 'enviado' THEN 'enviado'
              WHEN sm.estado IN ('pendente', 'enviando') THEN 'pendente'
              WHEN sm.estado IS NOT NULL THEN 'bloqueado: ' || coalesce(sm.bloqueio, sm.estado)
              ELSE 'sem: a Nay não avisou' END AS moto,
         EXISTS (SELECT 1 FROM mensagens m JOIN nai_contato k ON k.id = v.motoboy_id
                  WHERE m.direcao = 'recebida' AND right(regexp_replace(m.telefone, '\D', '', 'g'), 8) = right(k.chave, 8)
                    AND m.criada_em > coalesce(sm.enviado_em, sm.criado_em)) AS moto_respondeu,
         e.quando AS criada_em
    FROM nai_visita v
    JOIN LATERAL (SELECT min(x.quando) AS quando FROM nai_visita_evento x
                   WHERE x.visita_id = v.id AND x.tipo = 'com_a_rayssa') e ON e.quando IS NOT NULL
    LEFT JOIN imoveis i ON i.codigo = v.codigo
    LEFT JOIN nai_contato c ON c.id = v.corretor_id
    LEFT JOIN LATERAL (SELECT * FROM nai_proprietario_do_imovel(v.codigo)) d ON true
    LEFT JOIN LATERAL (SELECT s.estado, s.bloqueio, s.criado_em, s.enviado_em FROM nai_saida s
                        WHERE s.visita_id = v.id AND s.papel_destino = 'proprietario' ORDER BY s.id LIMIT 1) sp ON true
    LEFT JOIN LATERAL (SELECT s.estado, s.bloqueio, s.criado_em, s.enviado_em FROM nai_saida s
                        WHERE s.visita_id = v.id AND s.papel_destino = 'motoboy' ORDER BY s.id LIMIT 1) sm ON true
    LEFT JOIN LATERAL (SELECT coalesce(nullif(btrim(k.nome_completo), ''), k.nome_whatsapp) AS nome FROM nai_contato k
                        WHERE k.id = v.motoboy_id) mo ON true
   WHERE e.quando > now() - interval '3 days'
     AND v.estado NOT IN ('cancelada')
     AND (v.quando IS NULL OR v.quando > now() - interval '3 hours')
$f$;

CREATE OR REPLACE FUNCTION privado.visitas_parceria_sem_visita()
RETURNS TABLE (core_saida_id bigint, codigo integer, imovel text, corretor text, telefone text, quando timestamptz)
LANGUAGE sql STABLE SET search_path TO 'public', 'privado' AS $f$
  SELECT s.id, s.codigo,
         privado.nome_do_imovel(s.codigo),
         coalesce(nullif(btrim(k.nome_completo), ''), nullif(btrim(k.nome_whatsapp), ''), 'corretor'), s.chave_destino,
         s.enviado_em
    FROM core_saida s
    LEFT JOIN imoveis i ON i.codigo = s.codigo
    LEFT JOIN LATERAL (SELECT * FROM nai_contato k WHERE right(k.chave, 8) = right(s.chave_destino, 8)
                        ORDER BY k.id LIMIT 1) k ON true
   WHERE s.estado = 'enviado' AND s.texto ILIKE '%anotei a sua visita%'
     AND s.enviado_em > now() - interval '2 days' AND s.enviado_em < now() - interval '10 minutes'
     AND NOT EXISTS (SELECT 1 FROM privado.visita_ponte_aviso a WHERE a.core_saida_id = s.id)
     AND NOT EXISTS (SELECT 1 FROM nai_visita v JOIN nai_contato c ON c.id = v.corretor_id
                      WHERE right(c.chave, 8) = right(s.chave_destino, 8)
                        AND (s.codigo IS NULL OR v.codigo = s.codigo)
                        AND v.criado_em BETWEEN s.enviado_em - interval '1 hour' AND s.enviado_em + interval '1 hour')
$f$;

-- as chaves do nay-olx (privado.olx_config): ligar/desligar e o tempo sem resposta do proprietário
INSERT INTO privado.olx_config (chave, valor) VALUES
  ('visitas_parceria_grupo', 'sim'),
  ('visita_dono_sem_resposta_min', '60')
ON CONFLICT (chave) DO NOTHING;
-- as visitas que já estão andando não ganham checklist de agora para trás: só as que nascerem daqui em diante
INSERT INTO privado.visita_parceria_grupo (visita_id, assinatura, checklist_em, alerta_dono_em, alerta_sem_resposta_em)
SELECT s.visita_id, 'antes da 444', now(), now(), now() FROM privado.visitas_parceria_situacao() s
ON CONFLICT (visita_id) DO NOTHING;
INSERT INTO privado.visita_ponte_aviso (core_saida_id)
SELECT s.id FROM core_saida s WHERE s.estado = 'enviado' AND s.texto ILIKE '%anotei a sua visita%'
   AND s.enviado_em > now() - interval '2 days'
ON CONFLICT DO NOTHING;
COMMIT;
