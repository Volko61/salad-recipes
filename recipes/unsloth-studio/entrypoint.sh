#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Entrypoint SaladCloud pour Unsloth Studio
# ---------------------------------------------------------------------------
# Variables d'environnement (a definir dans le container group SaladCloud) :
#   UNSLOTH_PASSWORD  mot de passe admin du Studio          (defaut: change-me-please)
#   STUDIO_PORT       port web interne                       (defaut: 8080)
#   EXPOSE_MODE       "cloudflare" -> URL publique *.trycloudflare.com (dans les logs)
#                     "gateway"    -> ecoute sur '::' (IPv6/dual-stack), a exposer
#                                     via SaladCloud Container Gateway
#                     (defaut: cloudflare)
#   HF_TOKEN          (optionnel) login Hugging Face -> push/pull de modeles
# ---------------------------------------------------------------------------
set -euo pipefail

PASS="${UNSLOTH_PASSWORD:-change-me-please}"
PORT="${STUDIO_PORT:-8080}"
MODE="${EXPOSE_MODE:-cloudflare}"
UNS="/root/.unsloth/studio/unsloth_studio/bin/unsloth"

# Definition NON-INTERACTIVE du mot de passe admin (evite le prompt "New
# password:" qui bloque un conteneur headless). Studio lit cette variable au
# 1er demarrage ; ensuite l'utilisateur peut le changer dans l'UI.
export UNSLOTH_STUDIO_PASSWORD="${PASS}"

# Moteur GGUF (llama.cpp) sur GPU :
#  - llama-server n'a pas de rpath vers ses propres libs (libllama-server-impl.so,
#    libggml*.so) -> il faut son dossier de libs sur le path.
#  - la build CUDA (libggml-cuda.so) a besoin des libs runtime CUDA de torch
#    (libcudart, libcublas, libnvrtc) -> on ajoute aussi ces dossiers.
_NVLIB="/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages/nvidia"
export LD_LIBRARY_PATH="/root/.unsloth/llama.cpp/build/bin:${_NVLIB}/cuda_runtime/lib:${_NVLIB}/cublas/lib:${_NVLIB}/cuda_nvrtc/lib:${LD_LIBRARY_PATH:-}"

# GGUF accelere GPU : l'image embarque un llama.cpp CPU (build sans GPU au CI).
# Au 1er boot (GPU reel present -> resolution correcte, download GitHub OK depuis
# Salad) on installe la build CUDA prebuilt d'Unsloth.
# IMPORTANT : l'installeur, lance sur un dossier existant, le SUPPRIME parfois
# sans reinstaller (1er passage) -> on installe dans un dossier TEMPORAIRE, et on
# ne remplace le llama.cpp CPU (qui sert le GGUF en attendant) que si la build
# CUDA est validee (swap atomique). Aucune fenetre "runtime not installed".
_STUDIO_PY="/root/.unsloth/studio/unsloth_studio/bin/python"
_LC_INSTALLER="/root/.unsloth/studio/unsloth_studio/lib/python3.13/site-packages/studio/install_llama_prebuilt.py"
_LC_DIR="/root/.unsloth/llama.cpp"
_LC_TMP="/root/.unsloth/llama.cpp.cuda"
if [ -x "${_STUDIO_PY}" ] && [ -f "${_LC_INSTALLER}" ]; then
  echo "[entrypoint] Installation llama.cpp CUDA (GGUF GPU) en tache de fond..."
  (
    ok=0
    for attempt in 1 2 3; do
      rm -rf "${_LC_TMP}"
      if "${_STUDIO_PY}" "${_LC_INSTALLER}" --install-dir "${_LC_TMP}" \
           && [ -f "${_LC_TMP}/build/bin/libggml-cuda.so" ]; then
        ok=1; break
      fi
      echo "[entrypoint] tentative ${attempt} echouee, retry..."; sleep 5
    done
    if [ "${ok}" = "1" ]; then
      rm -rf "${_LC_DIR}" && mv "${_LC_TMP}" "${_LC_DIR}"
      ldconfig 2>/dev/null || true
      echo "[entrypoint] llama.cpp CUDA pret (GGUF accelere GPU)."
    else
      rm -rf "${_LC_TMP}"
      echo "[entrypoint] install llama.cpp CUDA echouee -> GGUF reste en CPU."
    fi
  ) > /root/llama_cuda_install.log 2>&1 &
fi

# Login HF optionnel (permet de sauvegarder tes LoRA hors de la box)
if [ -n "${HF_TOKEN:-}" ]; then
  echo "[entrypoint] Login Hugging Face..."
  /root/.unsloth/studio/unsloth_studio/bin/huggingface-cli login --token "${HF_TOKEN}" || \
    echo "[entrypoint] (login HF ignore)"
fi

# Diagnostic GPU (le "no GPU backend available" vient-il du conteneur ou de Studio ?)
echo "[entrypoint] GPU check (nvidia-smi):"
nvidia-smi -L 2>&1 | head -2 || echo "[entrypoint]   nvidia-smi indisponible (pas de GPU expose au conteneur ?)"

# Options reseau selon le mode d'exposition
if [ "${MODE}" = "gateway" ]; then
  # --secure (tunnel Cloudflare) echoue depuis un conteneur SaladCloud (sortie
  # cloudflared bloquee) -> on utilise --no-secure.
  # IMPORTANT: le SaladCloud Container Gateway route en IPv6 -> il faut ecouter
  # sur '::' (dual-stack), sinon 503. (0.0.0.0 = IPv4 seul = injoignable.)
  HOST_BIND="${STUDIO_HOST:-::}"
  NET_OPTS=(--no-secure -H "${HOST_BIND}" -p "${PORT}")
  echo "[entrypoint] Mode gateway : Studio ecoute sur [${HOST_BIND}]:${PORT} (--no-secure, IPv6)"
  echo "[entrypoint] -> expose via SaladCloud Container Gateway (port ${PORT})."
else
  NET_OPTS=(-p "${PORT}" --secure)
  echo "[entrypoint] Mode cloudflare : l'URL *.trycloudflare.com apparaitra ci-dessous."
  echo "[entrypoint]   (NB: --secure echoue souvent sur SaladCloud -> prefere EXPOSE_MODE=gateway)"
fi

echo "[entrypoint] Lancement d'Unsloth Studio (mot de passe via UNSLOTH_STUDIO_PASSWORD)..."
exec "${UNS}" studio "${NET_OPTS[@]}"
