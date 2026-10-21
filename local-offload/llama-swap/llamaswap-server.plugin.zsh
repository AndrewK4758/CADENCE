#!/usr/bin/env zsh
# ==============================================================================
# llamaswap-server.plugin.zsh
#
# ZSH wrapper and completion for llama-swap: one address (default :11434) that
# serves every BTG + local offload model by name and starts/stops the servers:
#   embedding      nomic-embed-text v1.5 on the CPU (llama-server, 32K/4 slots = 8K/slot, always loaded)
#   inference      Gemma 4 26B A4B + vision tensor-split 56/44 across RTX 5080 + RTX 5070 Ti at 96K ctx (or 12B on single GPU; ttl: 0, aliases: inference-dual, litert, local-moe-hybrid)
#   inference-12b  Gemma 4 12B + vision on RTX 5080 eGPU (32K ctx)
#   image          FLUX.2 klein / Z-Image / Qwen-Image (stable-diffusion.cpp sd-server)
#
# Configurations:
#   ~/projects/scripts/btg/llama-swap.egpu.yaml    Two GPUs (RTX 5080 eGPU + RTX 5070 Ti)
#   ~/projects/scripts/btg/llama-swap.single.yaml  One GPU (Internal RTX 5070 Ti laptop fallback)
#   apis/website/api/llama-swap.production.yaml    Production two-GPU server config
# Never listen on 8080 (another project's container uses it).
# ==============================================================================

# ------------------------------------------------------------------------------
# 1. Main llamaswap-server Wrapper Function
# ------------------------------------------------------------------------------
function llamaswap-server() {
    # Resolve binary location (prioritize ~/.local/bin/llama-swap)
    local binary="$HOME/.local/bin/llama-swap"
    if [[ ! -x "$binary" ]]; then
        binary="$(whence -p llama-swap 2>/dev/null)"
    fi
    if [[ -z "$binary" || ! -x "$binary" ]]; then
        echo -e "\033[1;31mError:\033[0m llama-swap binary not found at ~/.local/bin/llama-swap or on PATH" >&2
        echo "  Releases: https://github.com/mostlygeek/llama-swap/releases (v256+)" >&2
        return 1
    fi

    local plugin_dir="${0:A:h}"
    local repo="$HOME/projects/btg/btg/internal"
    local egpu_config="$HOME/projects/scripts/btg/llama-swap.egpu.yaml"
    [[ -f "$egpu_config" ]] || egpu_config="$HOME/.config/llama-swap/llama-swap.egpu.yaml"
    [[ -f "$egpu_config" ]] || egpu_config="$plugin_dir/llama-swap.egpu.yaml"

    local single_config="$HOME/projects/scripts/btg/llama-swap.single.yaml"
    [[ -f "$single_config" ]] || single_config="$HOME/.config/llama-swap/llama-swap.single.yaml"
    [[ -f "$single_config" ]] || single_config="$plugin_dir/llama-swap.single.yaml"

    local prod_config="$repo/apis/website/api/llama-swap.production.yaml"
    local models_dir="$HOME/.ollama/models/symlinks"
    local sd_bin="$HOME/stable-diffusion.cpp/build/bin/sd-server"
    local litert_bin="$HOME/.local/bin/litert-lm"
    local litert_config="$HOME/.litert-lm/config.json"
    local listen_ip="127.0.0.1"
    local port=11434
    local watch="on"
    local daemon="off"

    # Auto-detect GPUs by UUID so PCI bus renumbering never swaps GPU assignments
    local igpu_uuid=""
    local egpu_uuid=""
    local gpu_count=0
    if whence -p nvidia-smi >/dev/null 2>&1; then
        local line uuid name
        while IFS=',' read -r uuid name; do
            uuid="${uuid// /}"
            name="${name## }"
            [[ -z "$uuid" ]] && continue
            (( gpu_count++ ))
            if [[ "$name" == *"5080"* ]]; then
                egpu_uuid="$uuid"
            elif [[ "$name" == *"5070"* ]]; then
                igpu_uuid="$uuid"
            elif [[ -z "$igpu_uuid" ]]; then
                igpu_uuid="$uuid"
            else
                egpu_uuid="$uuid"
            fi
        done < <(nvidia-smi --query-gpu=uuid,name --format=csv,noheader 2>/dev/null)
    fi

    # Default config selection: auto-enable dual-GPU + LiteRT when eGPU is present
    local config="$single_config"
    if [[ -n "$egpu_uuid" && -f "$egpu_config" ]]; then
        config="$egpu_config"
    fi

    # Parse arguments using zparseopts associative array
    local -A opts
    zparseopts -E -D -A opts \
        h -help \
        d -daemon \
        c: -config: \
        -egpu -dual \
        -single \
        -production \
        m: -models: \
        s: -sd-server: \
        -litert: \
        -litert-config: \
        l: -listen-ip: -host: \
        P: -port: \
        w: -watch:

    # Show Help
    if [[ -v "opts[-h]" || -v "opts[--help]" ]]; then
        echo -e "\033[1;36mllamaswap-server\033[0m - llama-swap for BTG + Dual-GPU (5080 eGPU + 5070 Ti) + LiteRT-LM"
        echo -e "\033[1;33mUsage:\033[0m llamaswap-server [OPTIONS] [EXTRA_ARGS...]"
        echo ""
        echo -e "\033[1;33mOptions:\033[0m"
        echo -e "  \033[1;32m-c, --config <file>\033[0m          llama-swap config (default: auto-detects eGPU vs single GPU)"
        echo -e "  \033[1;32m--egpu, --dual\033[0m               Force dual-GPU + LiteRT config (llama-swap.egpu.yaml)"
        echo -e "  \033[1;32m--single\033[0m                     Force single-GPU laptop config (llama-swap.yaml)"
        echo -e "  \033[1;32m--production\033[0m                 Use the repo's llama-swap.production.yaml"
        echo -e "  \033[1;32m-d, --daemon\033[0m                 Run in background (/tmp/llama-swap.log) and wait for readiness"
        echo -e "  \033[1;32m-m, --models <dir>\033[0m           Folder holding GGUF/safetensors models (default: ~/.ollama/models/symlinks)"
        echo -e "  \033[1;32m-s, --sd-server <path>\033[0m       stable-diffusion.cpp sd-server binary"
        echo -e "  \033[1;32m--litert <path>\033[0m              litert-lm binary (default: ~/.local/bin/litert-lm)"
        echo -e "  \033[1;32m--litert-config <file>\033[0m       litert-lm config.json (default: ~/.litert-lm/config.json)"
        echo -e "  \033[1;32m-l, --listen-ip, --host <ip>\033[0m Address to bind (default: 127.0.0.1, use 0.0.0.0 for LAN/VPN)"
        echo -e "  \033[1;32m-P, --port <port>\033[0m            Port to listen on (default: 11434; never 8080)"
        echo -e "  \033[1;32m-w, --watch <on|off>\033[0m         Reload when the config file changes (default: on)"
        echo -e "  \033[1;32m-h, --help\033[0m                   Show this help message"
        echo ""
        echo -e "\033[1;33mDetected GPUs:\033[0m"
        echo "  Internal GPU (5070 Ti): ${igpu_uuid:-not detected}"
        echo "  External eGPU (5080):   ${egpu_uuid:-not connected (will use single-GPU fallback)}"
        echo ""
        echo -e "\033[1;33mWhile running:\033[0m"
        echo "  curl -s http://127.0.0.1:11434/running                    what is loaded"
        echo "  curl -s -X POST http://127.0.0.1:11434/api/models/unload   unload everything"
        echo "  http://127.0.0.1:11434/ui                                  web UI and logs"
        return 0
    fi

    # Override defaults if provided
    [[ -v "opts[-d]" || -v "opts[--daemon]" ]] && daemon="on"
    [[ -v "opts[--egpu]" || -v "opts[--dual]" ]] && config="$egpu_config"
    [[ -v "opts[--single]" ]] && config="$single_config"
    [[ -v "opts[--production]" ]] && config="$prod_config"
    [[ -n "${opts[-c]}" ]] && config="${opts[-c]}"
    [[ -n "${opts[--config]}" ]] && config="${opts[--config]}"

    [[ -n "${opts[-m]}" ]] && models_dir="${opts[-m]}"
    [[ -n "${opts[--models]}" ]] && models_dir="${opts[--models]}"

    [[ -n "${opts[-s]}" ]] && sd_bin="${opts[-s]}"
    [[ -n "${opts[--sd-server]}" ]] && sd_bin="${opts[--sd-server]}"

    [[ -n "${opts[--litert]}" ]] && litert_bin="${opts[--litert]}"
    [[ -n "${opts[--litert-config]}" ]] && litert_config="${opts[--litert-config]}"

    [[ -n "${opts[-l]}" ]] && listen_ip="${opts[-l]}"
    [[ -n "${opts[--listen-ip]}" ]] && listen_ip="${opts[--listen-ip]}"
    [[ -n "${opts[--host]}" ]] && listen_ip="${opts[--host]}"

    [[ -n "${opts[-P]}" ]] && port="${opts[-P]}"
    [[ -n "${opts[--port]}" ]] && port="${opts[--port]}"

    [[ -n "${opts[-w]}" ]] && watch="${opts[-w]}"
    [[ -n "${opts[--watch]}" ]] && watch="${opts[--watch]}"

    # Expand a leading ~ in paths
    config="${config/#\~/$HOME}"
    models_dir="${models_dir/#\~/$HOME}"
    sd_bin="${sd_bin/#\~/$HOME}"
    litert_bin="${litert_bin/#\~/$HOME}"
    litert_config="${litert_config/#\~/$HOME}"

    # Fallback CUDA device identifiers if --egpu is used for validation when eGPU is unplugged
    local igpu_dev="${igpu_uuid:-0}"
    local egpu_dev="${egpu_uuid:-$igpu_dev}"

    if [[ "$port" == "8080" ]]; then
        echo -e "\033[1;31mError:\033[0m port 8080 belongs to another project's container; pick another port" >&2
        return 1
    fi
    if [[ ! -f "$config" ]]; then
        echo -e "\033[1;31mError:\033[0m config not found: $config" >&2
        return 1
    fi
    if [[ ! -d "$models_dir" ]]; then
        echo -e "\033[1;31mError:\033[0m models folder not found: $models_dir" >&2
        return 1
    fi
    if [[ ! -x "$sd_bin" ]]; then
        echo -e "\033[1;33mWarning:\033[0m sd-server not found at $sd_bin: the image model will not start" >&2
    fi

    # Validate before stopping anything that is running
    if ! LLM_MODELS_DIR="$models_dir" SD_SERVER_BIN="$sd_bin" LITERT_BIN="$litert_bin" LITERT_CONFIG="$litert_config" IGPU_CUDA_DEVICE="$igpu_dev" EGPU_CUDA_DEVICE="$egpu_dev" "$binary" -config "$config" -validate >/dev/null; then
        echo -e "\033[1;31mError:\033[0m llama-swap rejected $config:" >&2
        LLM_MODELS_DIR="$models_dir" SD_SERVER_BIN="$sd_bin" LITERT_BIN="$litert_bin" LITERT_CONFIG="$litert_config" IGPU_CUDA_DEVICE="$igpu_dev" EGPU_CUDA_DEVICE="$egpu_dev" "$binary" -config "$config" -validate >&2
        return 1
    fi

    local is_systemd_service=0
    if [[ -n "${INVOCATION_ID:-}" || "${LLAMASWAP_SYSTEMD_SERVICE:-0}" == "1" ]]; then
        is_systemd_service=1
    fi

    local restore_service_on_exit=0
    if (( ! is_systemd_service )); then
        # Stop a running llama-swap (it stops its own servers), local-ai-offload.service,
        # and any stand-alone llama-server / sd-server to free VRAM
        if systemctl --user is-active --quiet local-ai-offload.service 2>/dev/null; then
            echo -e "\033[1;33mStopping local-ai-offload.service for manual llamaswap-server session...\033[0m"
            systemctl --user stop local-ai-offload.service 2>/dev/null || true
            restore_service_on_exit=1
        fi
        if pgrep -x "llama-swap" > /dev/null; then
            echo -e "\033[1;33mStopping the running llama-swap...\033[0m"
            pkill -TERM -x llama-swap
            for _ in {1..20}; do pgrep -x llama-swap > /dev/null || break; sleep 0.5; done
            pgrep -x llama-swap > /dev/null && pkill -KILL -x llama-swap
        fi
        if pgrep -x "llama-server" > /dev/null || pgrep -x "sd-server" > /dev/null; then
            echo -e "\033[1;33mStopping stand-alone llama-server / sd-server to free VRAM...\033[0m"
            pkill -TERM -x llama-server 2>/dev/null
            pkill -TERM -x sd-server 2>/dev/null
            sleep 2
            pkill -KILL -x llama-server 2>/dev/null
            pkill -KILL -x sd-server 2>/dev/null
        fi
    fi

    local -a cmd_args
    cmd_args=(-config "$config" -listen "${listen_ip}:${port}")
    [[ "$watch" == "on" || "$watch" == "true" || "$watch" == "1" ]] && cmd_args+=(-watch-config)

    echo -e "\033[1;32mStarting llama-swap...\033[0m"
    echo -e "  \033[1mBinary:\033[0m     $binary"
    echo -e "  \033[1mConfig:\033[0m     $config"
    echo -e "  \033[1mModels:\033[0m     $models_dir"
    echo -e "  \033[1mSD server:\033[0m  $sd_bin"
    echo -e "  \033[1miGPU (5070):\033[0m $igpu_dev"
    echo -e "  \033[1meGPU (5080):\033[0m ${egpu_uuid:-not connected (using single-GPU fallback on $igpu_dev)}"
    echo -e "  \033[1mEndpoint:\033[0m   http://${listen_ip}:${port} (UI: /ui)"
    echo -e "  \033[1mWatch:\033[0m      $watch"

    if (( is_systemd_service )); then
        exec env \
            LLM_MODELS_DIR="$models_dir" \
            SD_SERVER_BIN="$sd_bin" \
            LITERT_BIN="$litert_bin" \
            LITERT_CONFIG="$litert_config" \
            IGPU_CUDA_DEVICE="$igpu_dev" \
            EGPU_CUDA_DEVICE="$egpu_dev" \
            "$binary" "${cmd_args[@]}" "$@"
    fi

    if [[ "$daemon" == "on" ]]; then
        nohup env \
            LLM_MODELS_DIR="$models_dir" \
            SD_SERVER_BIN="$sd_bin" \
            LITERT_BIN="$litert_bin" \
            LITERT_CONFIG="$litert_config" \
            IGPU_CUDA_DEVICE="$igpu_dev" \
            EGPU_CUDA_DEVICE="$egpu_dev" \
            "$binary" "${cmd_args[@]}" "$@" >/tmp/llama-swap.log 2>&1 &!
        for _ in {1..30}; do
            curl -sf "http://127.0.0.1:${port}/running" >/dev/null 2>&1 && break
            sleep 0.2
        done
        echo -e "  \033[1mDaemon Log:\033[0m /tmp/llama-swap.log"
        return 0
    fi

    # Execute llama-swap in foreground and restore systemd user service if it was active before
    LLM_MODELS_DIR="$models_dir" \
    SD_SERVER_BIN="$sd_bin" \
    LITERT_BIN="$litert_bin" \
    LITERT_CONFIG="$litert_config" \
    IGPU_CUDA_DEVICE="$igpu_dev" \
    EGPU_CUDA_DEVICE="$egpu_dev" \
    "$binary" "${cmd_args[@]}" "$@"
    local exit_code=$?

    if (( restore_service_on_exit )); then
        echo -e "\033[1;36mRestoring local-ai-offload.service in background...\033[0m"
        systemctl --user start local-ai-offload.service 2>/dev/null || true
    fi
    return $exit_code
}

# ------------------------------------------------------------------------------
# 2. ZSH Completion Definition
# ------------------------------------------------------------------------------
function _llamaswap-server() {
    local -a opts
    opts=(
        '(-c --config --egpu --dual --single --production)'{-c,--config}'[llama-swap config file]:file:_files -g "*.y(a|)ml"'
        '(-c --config --single --production)'{--egpu,--dual}'[Force dual-GPU (RTX 5080 eGPU + RTX 5070 Ti) + LiteRT config]'
        '(-c --config --egpu --dual --production)--single[Force single-GPU laptop config]'
        '(-c --config --egpu --dual --single)--production[Use the repo llama-swap.production.yaml]'
        '(-m --models)'{-m,--models}'[Folder holding the model files]:directory:_directories'
        '(-s --sd-server)'{-s,--sd-server}'[stable-diffusion.cpp sd-server binary]:file:_files'
        '--litert[litert-lm binary]:file:_files'
        '--litert-config[litert-lm config.json file]:file:_files -g "*.json"'
        '(-l --listen-ip --host)'{-l,--listen-ip,--host}'[Address to bind (default 127.0.0.1)]:ip:(127.0.0.1 0.0.0.0)'
        '(-P --port)'{-P,--port}'[Port to listen on (default 11434)]:port:(11434 11437 11438)'
        '(-w --watch)'{-w,--watch}'[Reload when the config changes (default on)]:status:(on off)'
        '(-h --help)'{-h,--help}'[Show help message]'
        '*:extra options:_files'
    )
    _arguments -s -S $opts
}

# ------------------------------------------------------------------------------
# 3. Register Completion
# ------------------------------------------------------------------------------
if (( $+functions[compdef] )); then
    compdef _llamaswap-server llamaswap-server
fi
