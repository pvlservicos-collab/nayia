-- Adiciona o gatilho "abandono_preco" (lead visitou a página de preço e não comprou) ao enum de funis de mensagens
ALTER TYPE "funnel_trigger" ADD VALUE 'abandono_preco';
