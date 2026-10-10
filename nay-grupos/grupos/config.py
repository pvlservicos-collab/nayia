"""O que o serviço lê do ambiente (arquivo .env do servidor, fora do git)."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
MODELO = os.environ.get("GRUPOS_MODELO", "gpt-6-luna")
# as regras de negócio (pesos, cortes, modo) moram num arquivo que se edita sem mexer no código
ARQUIVO_DE_REGRAS = os.environ.get("GRUPOS_REGRAS", os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json"))
CICLO_S = int(os.environ.get("GRUPOS_CICLO_S", "10"))
POR_CICLO = int(os.environ.get("GRUPOS_POR_CICLO", "40"))            # mensagens lidas pela IA a cada passada
AO_MESMO_TEMPO = int(os.environ.get("GRUPOS_AO_MESMO_TEMPO", "8"))   # chamadas à IA em paralelo
REPONTUAR_A_CADA_S = int(os.environ.get("GRUPOS_REPONTUAR_A_CADA_S", "600"))
BATIMENTO = os.environ.get("GRUPOS_BATIMENTO", "/tmp/nay-grupos.batimento")
