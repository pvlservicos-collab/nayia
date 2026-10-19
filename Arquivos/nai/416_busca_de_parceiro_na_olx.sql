-- 416: BUSCAR IMÓVEL DE PARCEIRO NA OLX (19/10/2026)
--
-- Pedro: "quando o lead fizer uma pergunta para nós que não [temos] o imóvel, a Nay vai continuar respondendo 'vou
-- verificar as opções que tenho aqui se estão disponíveis'. Uma vez que a Nay chegar nessa situação ela vai disparar uma
-- ordem de busca no sistema, que vai ligar nossa API de scrap ... fazer uma busca na OLX por um anúncio, usando o nosso
-- mesmo mecanismo de nota da aba Grupos; se o anúncio tiver uma correspondência maior do que 88 ... abrir o anúncio e
-- verificar o contato do corretor ou proprietário; ... Já falamos com ele? se sim ela vai achar o contato dele em um dos
-- nossos números e vai enviar uma pergunta com o nome do imóvel da OLX perguntando se está disponível; se estiver ela vai
-- enviar esse imóvel ao lead ... se não achar na nossa base esse contato ... ela vai mandar para o grupo Altarquia 'Achei
-- esse imóvel x que tem correspondência x para o cliente x, chamar na OLX pelo anúncio x' ... e ela vai aguardar uma
-- resposta humana nossa pelo número do cliente que pediu (não vai mandar mais nada pra ele)".
--
-- Quem faz: a Nay do WhatsApp da OLX (nay-olx/olx/whatsapp.py) abre a ordem quando a busca no nosso catálogo volta
-- vazia; o laço olx/parceiro.py (dentro do serviço nay-olx) pega a ordem, busca na OLX pelo Chrome escondido do Agente
-- OLX no PC do Pedro (a OLX barra servidor; túnel até 127.0.0.1:9304), dá a nota com o código da aba Grupos
-- (/root/nay-grupos: grupos.pontuar) e segue o caminho do contato conhecido ou do grupo.
--
-- Chave `busca_parceiro`: nao | teste | sim. Em TESTE, só abre ordem para o 1º número de `whatsapp_teste` (Pedro) e a pergunta
-- de disponibilidade vai para o primeiro número de teste (com "[teste: iria para ...]"), nunca para o anunciante.
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS privado.olx_busca_parceiro (
  id              bigserial PRIMARY KEY,
  lead            bigint NOT NULL REFERENCES privado.olx_lead_whatsapp(id) ON DELETE CASCADE,
  filtros         jsonb NOT NULL,
  estado          text NOT NULL DEFAULT 'pendente'
                  CHECK (estado IN ('pendente', 'buscando', 'sem_navegador', 'sem_resultado', 'perguntado', 'confirmado',
                                    'negado', 'sem_resposta', 'no_grupo', 'erro', 'cancelado')),
  teste           boolean NOT NULL DEFAULT false,
  tentativas      integer NOT NULL DEFAULT 0,
  candidatos      jsonb NOT NULL DEFAULT '[]'::jsonb,   -- os anúncios com a nota (os melhores primeiro)
  escolhido       jsonb,                                 -- o anúncio aberto: título, preço, link, fotos, anunciante
  nota            numeric(5,1),
  contato_tel     text,                                  -- o telefone do anunciante (da descrição ou da nossa base)
  contato_nome    text,
  linha           text CHECK (linha IN ('parceria', 'captacao')),
  pergunta_mid    text,
  perguntado_em   timestamptz,
  resposta_texto  text,
  resposta_em     timestamptz,
  erro            text,
  criado_em       timestamptz NOT NULL DEFAULT now(),
  atualizado_em   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS olx_busca_parceiro_estado ON privado.olx_busca_parceiro (estado, criado_em);
-- uma ordem aberta por cliente
CREATE UNIQUE INDEX IF NOT EXISTS olx_busca_parceiro_aberta ON privado.olx_busca_parceiro (lead)
  WHERE estado IN ('pendente', 'buscando', 'sem_navegador', 'perguntado');

INSERT INTO privado.olx_config (chave, valor, descricao) VALUES
  ('busca_parceiro', 'teste', '416: buscar imóvel de parceiro na OLX quando o catálogo não tem: nao | teste (só o 1º número de whatsapp_teste, o do Pedro; a pergunta vai a ele) | sim'),
  ('busca_parceiro_nota_min', '88', '416: nota mínima (a mesma conta da aba Grupos) para o anúncio da OLX valer'),
  ('busca_parceiro_espera_h', '4', '416: horas esperando o anunciante responder se o imóvel está disponível; depois vai ao grupo'),
  ('busca_parceiro_cdp', 'http://127.0.0.1:9304', '416: o Chrome do Agente OLX (PC do Pedro) visto do servidor, pelo túnel do navegador-olx.ps1'),
  ('busca_parceiro_sem_navegador_min', '15', '416: minutos esperando o Chrome do PC ligar; depois a ordem vai ao grupo')
ON CONFLICT (chave) DO NOTHING;

-- o painel (admin/CRM) lê daqui: as buscas dos últimos dias com o cliente
CREATE OR REPLACE FUNCTION public.crm_olx_buscas_parceiro(p_dias integer DEFAULT 7)
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public', 'privado', 'pg_temp' AS $function$
  SELECT coalesce(jsonb_agg(jsonb_build_object(
           'id', b.id, 'estado', b.estado, 'teste', b.teste, 'criado_em', b.criado_em, 'atualizado_em', b.atualizado_em,
           'cliente', coalesce(l.nome, ''), 'cliente_tel', l.telefone, 'filtros', b.filtros, 'nota', b.nota,
           'titulo', b.escolhido->>'titulo', 'link', b.escolhido->>'url', 'preco', b.escolhido->>'preco_texto',
           'anunciante', b.contato_nome, 'contato', b.contato_tel, 'linha', b.linha, 'resposta', b.resposta_texto,
           'candidatos', jsonb_array_length(b.candidatos), 'erro', b.erro) ORDER BY b.id DESC), '[]'::jsonb)
    FROM privado.olx_busca_parceiro b JOIN privado.olx_lead_whatsapp l ON l.id = b.lead
   WHERE b.criado_em > now() - make_interval(days => greatest(1, least(coalesce(p_dias, 7), 90)))
$function$;
COMMIT;
