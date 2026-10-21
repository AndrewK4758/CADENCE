#!/usr/bin/env bash

echo "Downloading Gemma-4-E2B (Q4_K_M) from Hugging Face..."
wget -O ~/.ollama/models/symlinks/gemma-4-E2B-it.Q4_K_M.gguf "https://huggingface.co/prithivMLmods/gemma-4-E2B-it-GGUF/resolve/main/gemma-4-E2B-it.Q4_K_M.gguf"
echo "Download complete! You can now run: llamacpp-server -m gemma-4-E2B-it.Q4_K_M.gguf"
