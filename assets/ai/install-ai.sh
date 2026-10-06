#!/bin/bash
# Install the verified AI payloads into the live filesystem.
set -euo pipefail

ASSETS=/tmp/aegisos-assets/ai
MODEL_ROOT=/usr/share/kettco/models
MODEL_MANIFEST="$MODEL_ROOT/manifests/registry.ollama.ai/huihui_ai/qwen3.5-abliterated/9b"
MODEL_SHA256=92a443adb124f5e805bbdee23fdb38fcd22a7bf00a1016b53f764e741369c600

test -s /tmp/chatgpt_amd64.deb
test -s /tmp/codex-linux-x64.tgz
test -s /tmp/ollama-linux-amd64.tar.zst
test -f "$MODEL_MANIFEST"
printf '%s  %s\n' "$MODEL_SHA256" "$MODEL_MANIFEST" | sha256sum -c -

# The official package installs its signed update repository and desktop entry
# in its maintainer script. No account or API key is supplied to the package.
apt-get install -y --no-install-recommends /tmp/chatgpt_amd64.deb

# Keep the complete native Codex layout together. The binary discovers its
# resources and bundled helpers relative to this vendor directory.
install -d /usr/lib/kettco-codex
tar -xzf /tmp/codex-linux-x64.tgz --strip-components=1 -C /usr/lib/kettco-codex package
test -x /usr/lib/kettco-codex/vendor/x86_64-unknown-linux-musl/bin/codex
ln -sfn /usr/lib/kettco-codex/vendor/x86_64-unknown-linux-musl/bin/codex /usr/local/bin/codex
/usr/local/bin/codex --version | grep -Fq 'codex-cli 0.160.1'

# Ollama's official archive contains the runtime and its CPU/GPU runner
# libraries. Preserve the archive layout so upgrades can replace it atomically.
install -d /usr/lib/ollama
tar --use-compress-program=zstd -xf /tmp/ollama-linux-amd64.tar.zst -C /usr/lib/ollama
ollama_binary=$(find /usr/lib/ollama -type f -name ollama -perm -0100 -print -quit)
test -n "$ollama_binary"
ln -sfn "$ollama_binary" /usr/local/bin/ollama
/usr/local/bin/ollama --version | grep -Fq '0.35.1'

# The model is public and read-only in the image. Verify its OCI blobs again at
# build time; the host fetcher already checked every digest before staging.
test -r "$MODEL_MANIFEST"
while IFS= read -r line; do
  digest_name=$(printf '%s\n' "$line" | sed -n 's/.*"digest":"sha256:\([0-9a-f]*\)".*/\1/p')
  [ -n "$digest_name" ] || continue
  blob="$MODEL_ROOT/blobs/sha256-$digest_name"
  test -s "$blob"
  printf '%s  %s\n' "$digest_name" "$blob" | sha256sum -c -
done < <(grep -o '"digest":"sha256:[0-9a-f]*"' "$MODEL_MANIFEST")
chmod -R a+rX,go-w "$MODEL_ROOT"

install -Dm0644 "$ASSETS/kettco-ollama.service" \
  /usr/lib/systemd/user/kettco-ollama.service
install -Dm0644 "$ASSETS/kettco-local-model.desktop" \
  /usr/share/applications/kettco-local-model.desktop
install -Dm0755 "$ASSETS/kettco-ai-status" /usr/local/bin/kettco-ai-status
systemctl --global enable kettco-ollama.service

rm -f /tmp/chatgpt_amd64.deb /tmp/codex-linux-x64.tgz /tmp/ollama-linux-amd64.tar.zst
