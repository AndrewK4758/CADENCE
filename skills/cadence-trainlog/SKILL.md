---
name: cadence-trainlog
description: Inspect, backfill, tag, verify, and export CADENCE turn logs stored outside git repositories into SFT, DPO, and RLVR open-weight training datasets with secret scrubbing and BTG client Chinese-wall enforcement
argument-hint: "<status|ingest|export|tag|verify> [options]"
allowed-tools: Read Bash
---

# CADENCE Turn Log & Training Dataset Pipeline

Every turn completed inside a CADENCE repository by Antigravity CLI or Claude Code is captured automatically on `Stop` by `.agents/hooks/cadence-turn-logger.sh` (`hooks/cadence-turn-logger.sh`), scrubbed of secrets/credentials, enriched with deterministic CADENCE gate outcomes (`certainty-gate`, `verify-spec`, `verify-facts`, `run-cadence-tests`, `doctor.sh`, `submission.md` review cycles), and written outside git repositories to `${CADENCE_TURN_LOG_DIR:-~/.local/share/cadence-turn-logs}` (`0700` dirs, `0600` files). Set `CADENCE_TURN_LOG=0` to disable capture.

## Commands

Resolve the CLI wrapper from `.agents/skills/cadence-trainlog/trainlog.sh` or `skills/cadence-trainlog/trainlog.sh`:

1. **Inspect captured repositories and gate outcomes:**
   ```bash
   skills/cadence-trainlog/trainlog.sh status
   ```

2. **Backfill historical sessions (Antigravity CLI, Claude Code, and Blitz) for CADENCE repos:**
   ```bash
   skills/cadence-trainlog/trainlog.sh ingest --source all
   ```
   Pass `--redact-env-file ~/.secrets.env` during explicit export/ingest if you want literal env secret values scrubbed in addition to built-in regex patterns (env values are never printed).

3. **Tag a repository's confidentiality / client scope:**
   ```bash
   skills/cadence-trainlog/trainlog.sh tag --repo <slug> --confidentiality public-eligible|private|client-restricted [--client-tag <name>]
   ```

4. **Export single-repo or client-isolated training JSONL (`sft`, `dpo`, `rlvr`):**
   ```bash
   skills/cadence-trainlog/trainlog.sh export --format sft --repo <slug> --only-verified --out ~/datasets/cadence-sft.jsonl
   skills/cadence-trainlog/trainlog.sh export --format dpo --repo <slug> --out ~/datasets/cadence-dpo.jsonl
   skills/cadence-trainlog/trainlog.sh export --format rlvr --repo <slug> --out ~/datasets/cadence-rlvr.jsonl
   ```
   Mixing `client-restricted` repos across different `client_tag`s or non-client repos fails closed with exit `2` (`CHINESE_WALL_VIOLATION`).

5. **Verify a generated dataset before model fine-tuning:**
   ```bash
   skills/cadence-trainlog/trainlog.sh verify --input ~/datasets/cadence-sft.jsonl
   ```
