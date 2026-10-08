"""O que o serviço lê do ambiente (arquivo .env do servidor, fora do git)."""
import os

DATABASE_URL = os.environ.get("DATABASE_URL", "")
OPENAI_API_KEY = os.environ.get("OPENAI_API_KEY", "")
# o mesmo modelo do nó "GPT (captação)" do fluxo
MODELO = os.environ.get("CAPTACAO_MODELO", "gpt-6-luna")
# a resposta e o modelo (template) saem pelo CRM: é ele que tem o token da Meta e grava a conversa
CRM_URL = os.environ.get("CRM_URL", "https://crm.imobeasy.online").rstrip("/")
SEGREDO = os.environ.get("CAPTACAO_OFICIAL_SEGREDO", "")
# o modelo que abre a conversa pelo número oficial (Pedro, 08/10)
MODELO_DE_ABERTURA = os.environ.get("CAPTACAO_MODELO_ABERTURA", "situacao_imovel_cadastrado_1")
IDIOMA_DO_MODELO = os.environ.get("CAPTACAO_MODELO_IDIOMA", "pt_BR")
# o Tel recebe o aviso de escalada e de foto pela caixa da Nay; "nao" desliga tudo. O telefone de teste nunca avisa.
AVISAR_TEL = os.environ.get("CAPTACAO_AVISAR_TEL", "sim") == "sim"
# segundos de silêncio antes de responder (o "Janela de 20s" do fluxo)
SILENCIO_S = int(os.environ.get("CAPTACAO_SILENCIO_S", "20"))
BATIMENTO = os.environ.get("CAPTACAO_BATIMENTO", "/tmp/nay-captacao.batimento")
# a API do site, para entregar ao imóvel a foto que o dono mandou na conversa (a rota do card do CRM, com senha de máquina)
SITE_API_URL = os.environ.get("SITE_API_URL", "http://127.0.0.1:8092").rstrip("/")
FOTO_SEGREDO = os.environ.get("CAPTACAO_FOTO_SEGREDO", "")
# de quanto em quanto tempo as respostas dos donos vão para o cadastro (segundos)
CADASTRO_A_CADA_S = int(os.environ.get("CAPTACAO_CADASTRO_A_CADA_S", "300"))
