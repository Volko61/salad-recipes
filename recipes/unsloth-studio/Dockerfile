# ---------------------------------------------------------------------------
# Unsloth Studio - SaladCloud Recipe
# ---------------------------------------------------------------------------
# Image auto-suffisante : Unsloth Studio (+ PyTorch/CUDA) est installe AU BUILD.
# Au demarrage sur SaladCloud, le conteneur lance Studio et publie une URL.
# Comme SaladCloud relance toujours cette meme image, plus besoin de reinstaller
# quoi que ce soit apres une reallocation.
#
# GPU requis : NVIDIA Blackwell/Ada (ex. RTX 5090/4090). Les wheels PyTorch
# embarquent CUDA, on part donc d'un simple Ubuntu 24.04 ; SaladCloud fournit le
# driver NVIDIA a l'execution.
# ---------------------------------------------------------------------------
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# Dependances systeme (cmake + libcurl : moteur GGUF d'Unsloth ; expect : saisie
# non-interactive du mot de passe ; tmux/git : confort + install).
RUN apt-get update && apt-get install -y --no-install-recommends \
        curl git ca-certificates build-essential cmake libcurl4-openssl-dev \
        python3 python3-venv python3-pip expect tmux \
    && rm -rf /var/lib/apt/lists/*

# --- Installation d'Unsloth Studio au build (bake torch CUDA + unsloth) ------
# PROBLEME : le build tourne sur un runner sans GPU -> install.sh detecte "pas de
# GPU" et installe PyTorch **CPU** (torch.cuda indisponible au runtime = erreur
# "no GPU backend available"). SOLUTION : on simule un GPU via un faux nvidia-smi
# le temps de l'install, pour qu'install.sh prenne la stack **CUDA** (torch cu130
# + torchao GPU). Le vrai driver NVIDIA est fourni par SaladCloud a l'execution.
ENV UNSLOTH_SKIP_AUTOSTART=1
RUN printf '#!/bin/sh\necho "GPU 0: NVIDIA GeForce RTX 4090 (UUID: GPU-00000000-0000-0000-0000-000000000000)"\nexit 0\n' \
        > /usr/local/bin/nvidia-smi \
    && chmod +x /usr/local/bin/nvidia-smi \
    && curl -fsSL https://unsloth.ai/install.sh | sh \
    && rm -f /usr/local/bin/nvidia-smi

# Ceinture + bretelles : si torch est malgre tout en CPU, forcer la variante CUDA
# (meme version) depuis l'index cu130. Le driver SaladCloud est CUDA 13.x.
RUN set -e; \
    PIP=/root/.unsloth/studio/unsloth_studio/bin/pip; \
    PY=/root/.unsloth/studio/unsloth_studio/bin/python; \
    if $PY -c "import torch,sys; sys.exit(0 if torch.version.cuda else 1)"; then \
        echo "torch CUDA OK: $($PY -c 'import torch;print(torch.__version__)')"; \
    else \
        TV=$($PY -c "import torch;print(torch.__version__.split('+')[0])"); \
        echo "torch CPU detecte ($TV) -> reinstall cu130"; \
        $PIP install --no-cache-dir --force-reinstall "torch==$TV" \
            --index-url https://download.pytorch.org/whl/cu130; \
    fi

# --- Correctif inference : retirer flash_attn -> Unsloth bascule sur sdpa ----
# Sinon crash sur certains modeles (Nemotron, Gemma-3...) :
#   "static cache is not compatible with attn_implementation==flash_attention_2"
RUN /root/.unsloth/studio/unsloth_studio/bin/pip uninstall -y flash_attn flash-attn || true

ENV PATH="/root/.unsloth/studio/unsloth_studio/bin:${PATH}"

# Cache Hugging Face sur un chemin stable (montable en volume persistant Salad)
ENV HF_HOME=/root/.cache/huggingface

# Defauts adaptes a SaladCloud Container Gateway (URL stable, pas de Cloudflare) :
# Studio ecoute sur 0.0.0.0:8080, le Gateway expose ce port publiquement.
ENV EXPOSE_MODE=gateway
ENV STUDIO_PORT=8080

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Port web de Studio (utilise si tu exposes via SaladCloud Container Gateway)
EXPOSE 8080

ENTRYPOINT ["/entrypoint.sh"]
