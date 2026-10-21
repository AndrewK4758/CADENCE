# CADENCE Local Hardware Coprocessor Offload (`llama-swap`, LiteRT-LM & FastMCP)

This directory contains the complete local AI coprocessor infrastructure that powers CADENCE's automatic Step 0 semantic discovery (`local_semantic_embed`), build/test log compaction (`offload_log_triage`), and pre-commit/gate deep review (`offload_deep_review`) on `127.0.0.1:11434`.

---

## 1. Component Inventory

| Path | Installed Destination | Purpose |
| :--- | :--- | :--- |
| `llama-swap/llamaswap-server` | `~/.local/bin/llamaswap-server` | Global CLI entrypoint for `llama-swap` |
| `llama-swap/llamaswap-server.plugin.zsh` | `~/.config/llama-swap/llamaswap-server.plugin.zsh` | ZSH function & completions; auto-detects Dual-GPU (RTX 5080 eGPU + RTX 5070 Ti) vs. Single-GPU by NVIDIA UUID |
| `llama-swap/local-ai-offload-serve` | `~/.local/bin/local-ai-offload-serve` | Systemd `ExecStart` wrapper; waits for NVIDIA/eGPU initialization at boot and execs `llamaswap-server` |
| `llama-swap/llama-swap.egpu.yaml` | `~/.config/llama-swap/llama-swap.egpu.yaml` | Dual-GPU config: persistent `embedding` (`nomic-embed-text-v1.5.f16`) + warm `inference` (`Gemma 4 26B A4B IT + Vision`, 56/44 tensor split across 5080 + 5070 Ti, 96K ctx, `ttl: 0`) + `inference-12b` + `coder` + diffusion `image-*` models |
| `llama-swap/llama-swap.single.yaml` | `~/.config/llama-swap/llama-swap.single.yaml` | Single-GPU laptop fallback config: persistent `embedding` + warm `inference` (`Gemma 4 12B IT + Vision`, 32K ctx, `ttl: 0`) + diffusion `image-*` models |
| `systemd/local-ai-offload.service` | `~/.config/systemd/user/local-ai-offload.service` | Systemd user unit managing `local-ai-offload-serve` on `127.0.0.1:11434` |
| `mcp/antigravity-local-offload-mcp` | `~/.local/bin/antigravity-local-offload-mcp` | `uv`-powered FastMCP server exposing `local_semantic_embed`, `offload_log_triage`, and `offload_deep_review` |
| `mcp/schemas/*.json` | `~/.gemini/antigravity-cli/mcp/local-offload/*.json` | Lazy-loaded tool schemas required by Antigravity CLI |
| `mcp/mcp_config.example.json` | `~/.gemini/config/mcp_config.json` | Sanitized MCP server configuration template |
| `litert-lm/config.json` | `~/.litert-lm/config.json` | LiteRT-LM CPU/GPU thread configuration (`gemma-4-e2b`, `gemma3-1b-gpu-custom`) |
| `../hooks/antigravity-local-offload-hook` | `~/.local/bin/antigravity-local-offload-hook` | Global `PreInvocation` + `PostToolUse` lifecycle hook enforcing Step 0 discovery and log triage |
| `scripts/build-llama.sh` | *(run manually)* | Builds & installs `llama.cpp` (`llama-server`) with CUDA and Flash Attention (`-DGGML_CUDA=ON -DGGML_CUDA_FA=ON`) |
| `scripts/setup-egpu.sh` & `nvidia-powerd-egpu-fix.c` | *(optional, Arch/Linux eGPU)* | Configures Thunderbolt/USB4 eGPU PCIe Gen3 link cap, udev D0 power rules, KWin DRM isolation, and `nvidia-powerd` shim |

---

## 2. How `llamaswap-server` & GPU Auto-Detection Work

`llamaswap-server.plugin.zsh` queries `nvidia-smi --query-gpu=uuid,name --format=csv,noheader` at startup:
- **UUID-Based Pinning**: Instead of fragile PCI bus indices (`0`, `1`) that can flip on hotplug or reboot, `llamaswap-server` exports `IGPU_CUDA_DEVICE=<uuid>` and `EGPU_CUDA_DEVICE=<uuid>` into `llama-swap`.
- **Automatic Mode Selection**:
  - When an external GPU (`5080` or second GPU) is detected, it automatically selects `llama-swap.egpu.yaml` (Dual-GPU 26B A4B at 96K context).
  - When undocked (only internal GPU detected), it automatically selects `llama-swap.single.yaml` (Single-GPU 12B at 32K context).
- **Config Validation Before Swap**: Before stopping any running server, `llamaswap-server` runs `llama-swap -config <yaml> -validate` with all environment variables populated so a broken edit never takes down the active service.
- **Model Aliases**: Both `llama-swap.egpu.yaml` and `llama-swap.single.yaml` map all CADENCE and LiteRT model aliases (`inference`, `inference-dual`, `local-moe-hybrid`, `gemma-4-26b-a4b`, `gemma-4-12b`, `local-fast-cpu`, `gemma-4-e2b`, `litert`, `litert-gemma`) to the warm `inference` model (`ttl: 0`) so tool calls never trigger cold model swaps.

### CLI Usage

```bash
llamaswap-server --help               # Show options and detected GPU UUIDs
llamaswap-server                      # Run in foreground (auto-stops & restores systemd service on Ctrl-C)
llamaswap-server --egpu               # Force Dual-GPU config (llama-swap.egpu.yaml)
llamaswap-server --single             # Force Single-GPU config (llama-swap.single.yaml)
llamaswap-server --daemon             # Run in background (/tmp/llama-swap.log) and wait for readiness
llamaswap-server -m /path/to/models   # Override GGUF models directory
```

---

## 3. FastMCP Server (`antigravity-local-offload-mcp`)

The MCP server runs via `uv run --script ~/.local/bin/antigravity-local-offload-mcp` and exposes three tools backed by `http://127.0.0.1:11434/v1`:

1. **`local_semantic_embed(texts, query, top_k=5)`**:
   - Accepts file paths, directory paths, glob patterns, or inline text snippets.
   - Splits source files on AST/symbol boundaries (`def`, `class`, `fn`, `interface`, markdown headings) into ~48-line numbered slices with symbol maps and CHORD seam tags.
   - Embeds all chunks via `nomic-embed-text` (`POST /v1/embeddings`) and returns the top-$k$ pinned context slices ready for immediate execution.
2. **`offload_log_triage(log_text_or_command, model="inference")`**:
   - Accepts `"cmd:<shell command>"`, a log file path, or raw log text.
   - Writes the complete, unedited 1-indexed log to `/tmp/agy-last-triage.log` and `/tmp/agy-triage/<repo>/<pid>.log` (with symlink `/tmp/agy-triage/<repo>/latest.log`).
   - Fast-paths clean outputs (`<=30` lines, exit `0`, zero error signals) in `0 ms` without LLM overhead.
   - Compacts duplicate error/warning signals and delegates root-cause + `file:line` extraction to warm `inference`.
3. **`offload_deep_review(prompt, context_files, model="inference")`**:
   - Computes static ergonomics telemetry (line counts vs. `<400`-line ceiling, symbol index, CHORD seams) and ranks top semantic slices for large files.
   - Delegates an advisory CADENCE Engineering Pillar pre-review to warm `inference`.

---

## 4. Custom Lifecycle Hooks (`hooks/`)

Installed globally in `~/.gemini/config/hooks.json` and `~/.agents/hooks.json`:

- **`antigravity-local-offload-hook` (`PreInvocation` + `PostToolUse`)**:
  - On `PreInvocation` (`invocationNum == 1`), injects an ephemeral reminder instructing the agent to run Step 0 discovery (`local_semantic_embed` / `repo-scout`), log triage (`offload_log_triage` / `log-triage`), and pre-commit review (`offload_deep_review`).
  - On `PostToolUse` (`run_command` / `Bash`), detects test/build/gate commands or repeated `find`/`grep`/`rg` sweeps (`>=2`) and queues a targeted offload reminder for the next turn.
- **`tms-sync-reminder.sh` (`PostToolUse` on file edits)**:
  - Reminds the agent to keep `specs/{ticket-id}/metadata.yaml` and tracker status synchronized when specification artifacts change.
- **`tms-doc-sync-stop.sh` (`Stop`)**:
  - Verifies documentation and tracker synchronization before concluding a governed session.
