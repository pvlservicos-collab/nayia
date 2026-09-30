"""Chama o provedor com timeout de LLM_TIMEOUT_S e LLM_RETENTATIVAS; circuit breaker; se
falhar, o turno cai no fallback conservador (template de esclarecimento ou escalação),
nunca em geração livre. Grava entrada e saída no trace e, em teste, reproduz fixtures.
"""
