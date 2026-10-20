-- 441 (Pedro, 20/10/2026): "vai lá nas mensagens modelo e encontra mensagens que possam servir para esse objetivo, para
-- donos: perguntar se tem algum imóvel para adicionar, estamos com uma demanda alta de imóveis e queremos saber se você
-- tem imóveis para vender; aprovadas como utilidade, e põe pra mim lá no site, modelos de mensagem, como uma categoria
-- com um título diferente".
-- Medido na Meta em 20/10 (Arquivos/whatsapp/listar_utilidade.js): dos 65 APROVADOS como Utilidade, NENHUM faz a pergunta
-- direto. Os que fazem (numero_novo_*, "demanda alta") estão pendentes e a Meta os pôs em Marketing; outro_imovel_04
-- ("possui outro imóvel disponível além do que já consta conosco?") está pendente como Utilidade e não entra até aprovar.
-- Entram os 22 aprovados como Utilidade que ABREM a conversa com o dono (situação do imóvel, perfil Proprietário /
-- Corretor, disponibilidade): ele responde, a janela de 24 h abre e a pergunta da demanda vai em texto livre.
-- Etiqueta com ★: a página WhatsApp › Mensagens mostra as etiquetas com ★ como CATEGORIA (no topo e num botão).
-- Só acrescenta (não tira etiqueta de ninguém); rodar de novo não duplica.
BEGIN;
INSERT INTO whats_modelo_nota (nome, idioma, etiquetas, atualizado_por)
SELECT v.nome, 'pt_BR', ARRAY['★ Donos · tem imóvel para vender? (Utilidade aprovada)']::text[], 'Claude (441, 20/10)'
  FROM (VALUES
    -- situação do imóvel cadastrado (o dono responde por botão e a conversa abre)
    ('situacao_imovel_cadastrado_1'), ('situacao_imovel_cadastrado_3'), ('situacao_imovel_cadastrado_4'),
    ('situacao_imovel_cadastrado_5'), ('situacao_imovel_cadastrado_6'),
    ('captacao_status_novo_numero_2'), ('captacao_status_novo_numero_3'),
    ('situacao_condominio_1'), ('situacao_condominio_2'), ('situacao_condominio_3'),
    ('confirmar_disponivel_09'), ('confirmar_disponivel_10'),
    -- disponibilidade, com cara de aviso de sistema
    ('sistema_aviso_01'), ('sistema_aviso_02'), ('sistema_aviso_03'), ('sistema_aviso_04'), ('sistema_aviso_05'),
    -- perfil do cadastro: quem toca em "Proprietário" (ou "Os dois") é o dono a quem perguntar
    ('l1_util_16'), ('l1_util_17'), ('l1_util_18'), ('l1_util_19'), ('l2_util_11')
  ) AS v(nome)
ON CONFLICT (nome, idioma) DO UPDATE SET
  etiquetas = (SELECT coalesce(array_agg(DISTINCT e ORDER BY e), '{}') FROM unnest(whats_modelo_nota.etiquetas || EXCLUDED.etiquetas) e),
  atualizado_por = EXCLUDED.atualizado_por, atualizado_em = now();
SELECT count(*) AS na_categoria FROM whats_modelo_nota WHERE '★ Donos · tem imóvel para vender? (Utilidade aprovada)' = ANY (etiquetas);
COMMIT;
