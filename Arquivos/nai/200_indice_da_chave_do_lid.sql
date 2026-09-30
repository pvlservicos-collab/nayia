-- 200 (30/09/2026): índice na chave do telefone de identidade_lid.
-- nai_contato_irmaos (chamada em todo turno, várias vezes por turno) calculava
-- nai_chave(telefone) nas 1.620 linhas de identidade_lid a cada chamada: 111 ms.
-- Com o índice, 4,5 ms. crm_parceria_marcas (as marcas das abas da Parceria no
-- CRM) caiu de 11,4 s para 0,86 s com os 136 telefones da linha -- estourava o
-- tempo do CRM e a aba Visitas ficava vazia. Não muda regra nenhuma.
-- CONCURRENTLY: não trava a tabela (não roda dentro de transação).
CREATE INDEX CONCURRENTLY IF NOT EXISTS identidade_lid_chave ON identidade_lid (nai_chave(telefone));
