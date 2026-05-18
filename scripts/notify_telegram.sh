#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${TELEGRAM_BOT_TOKEN:-}" || -z "${TELEGRAM_CHAT_ID:-}" ]]; then
  echo "TELEGRAM_BOT_TOKEN and TELEGRAM_CHAT_ID must be set." >&2
  exit 1
fi

if [[ -z "${INSTANCE_ID:-}" ]]; then
  echo "INSTANCE_ID must be set for notification." >&2
  exit 1
fi

REGION="${OCI_CLI_REGION:-unknown}"
DISPLAY_NAME="${OCI_DISPLAY_NAME:-unknown}"
OCPUS="${OCI_OCPUS:-?}"
MEMORY_GB="${OCI_MEMORY_GB:-?}"
PUBLIC_IP="${PUBLIC_IP:-}"
ALREADY_EXISTED="${ALREADY_EXISTED:-false}"

if [[ "$ALREADY_EXISTED" == "true" ]]; then
  headline="OCI ARM instance already exists"
else
  headline="OCI ARM instance created"
fi

ssh_line="Public IP not ready yet. Check OCI Console → Compute → Instances."
if [[ -n "$PUBLIC_IP" && "$PUBLIC_IP" != "null" ]]; then
  ssh_line="SSH: ssh opc@${PUBLIC_IP}"
fi

message="${headline}

Name: ${DISPLAY_NAME}
Region: ${REGION}
OCID: ${INSTANCE_ID}
OCPUs/RAM: ${OCPUS}/${MEMORY_GB} GB
${ssh_line}

Disable the GitHub workflow if you have not already (auto-disable runs on success)."

payload="$(jq -n \
  --arg chat_id "$TELEGRAM_CHAT_ID" \
  --arg text "$message" \
  '{chat_id: $chat_id, text: $text, disable_web_page_preview: true}')"

http_code="$(curl -sS -o /tmp/telegram_response.json -w "%{http_code}" \
  -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -H "Content-Type: application/json" \
  -d "$payload")"

if [[ "$http_code" != "200" ]]; then
  echo "Telegram API returned HTTP ${http_code}" >&2
  cat /tmp/telegram_response.json >&2
  exit 1
fi

echo "Telegram notification sent."
