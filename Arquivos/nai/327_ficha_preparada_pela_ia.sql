-- 327 -- A ficha que o dono ditou, já analisada e posta nos campos certos do cadastro
--
-- Pedro, 09/10/2026, no Cadastro rápido: "se o dono mandou as fotos elas já têm que aparecer lá, o mais automático
-- possível para eu só aprovar; analisa as informações e põe elas nos campos certinhos".
--
-- A ficha guarda o que ele disse nas palavras dele ("Três suítes", "Garagem 4 carros", "Lote 392, Rua 14, Nº 405").
-- O serviço nay-captacao (captacao/preparar.py, de 5 em 5 minutos) lê a ficha e a conversa, pede ao modelo os campos
-- do cadastro (tipo, condomínio, endereço, quartos, valores, mobília, características, um texto de anúncio) e guarda
-- aqui. O Cadastro rápido abre a tela de cadastro já preenchida com isso, mostra as fotos que ele mandou, e o botão
-- verde cadastra e aprova num clique.
--
-- Nada é criado em `imoveis` sem a pessoa clicar: uma ficha pode ser imóvel alugado, obra que não acabou ou
-- duplicata de outra ficha (o modelo avisa em `pronto_para_anunciar`, `observacao` e `duplicado_de`).
BEGIN;
SET LOCAL lock_timeout = '3s';

CREATE TABLE IF NOT EXISTS public.captacao_ficha_campos (
  ficha_id             bigint PRIMARY KEY REFERENCES captacao_cadastro(id) ON DELETE CASCADE,
  campos               jsonb NOT NULL DEFAULT '{}'::jsonb,
  observacao           text,
  pronto               boolean,
  duplicado_de         bigint,
  ficha_atualizada_em  timestamptz,
  analisado_em         timestamptz NOT NULL DEFAULT now(),
  modelo               text
);
COMMENT ON TABLE public.captacao_ficha_campos IS
  '327: a ficha da conversa analisada pelo modelo (nay-captacao/captacao/preparar.py): os campos do cadastro prontos para a tela de Cadastro rápido.';
GRANT SELECT ON public.captacao_ficha_campos TO nay_leitura;

-- o que a tela precisa da ficha: os campos analisados, as fotos que ele mandou, o condomínio do cadastro e o dono
CREATE OR REPLACE FUNCTION public.site_ficha_preparada(p_ficha bigint)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT jsonb_build_object(
    'ficha', c.id, 'estado', c.estado, 'dados', c.dados,
    'campos', a.campos, 'observacao', a.observacao, 'pronto', a.pronto, 'duplicado_de', a.duplicado_de,
    'analisado_em', a.analisado_em,
    'fotos', coalesce((SELECT jsonb_agg(t.u ORDER BY t.o) FROM jsonb_array_elements_text(
                         CASE WHEN jsonb_typeof(c.fotos) = 'array' THEN c.fotos ELSE '[]'::jsonb END) WITH ORDINALITY t(u, o)
                        WHERE t.u ~ '^https?://'), '[]'::jsonb),
    'condominio', (SELECT jsonb_build_object('id', co.id, 'nome', co.nome, 'bairro', co.bairro) FROM condominios co
                    WHERE nullif(btrim(coalesce(a.campos->>'condominio', c.dados->>'condominio')), '') IS NOT NULL
                      AND lower(nay_sem_acento(co.nome)) = lower(nay_sem_acento(btrim(coalesce(a.campos->>'condominio', c.dados->>'condominio'))))
                    LIMIT 1),
    'dono', jsonb_build_object('nome', l.nome, 'telefone', l.telefone, 'tratamento', l.tratamento))
    FROM captacao_cadastro c
    LEFT JOIN captacao_ficha_campos a ON a.ficha_id = c.id
    LEFT JOIN captacao_leads l ON l.id = c.lead_id
   WHERE c.id = p_ficha;
$function$;
GRANT EXECUTE ON FUNCTION public.site_ficha_preparada(bigint) TO nay_site_escrita;

COMMIT;
