#!/usr/bin/env bash
set -euo pipefail

# Attempt one OCI VM.Standard.A1.Flex launch. Exits 0 only on success.
# Writes: success, instance_id, public_ip, already_existed to GITHUB_OUTPUT (if set).

REQUIRED_VARS=(
  OCI_COMPARTMENT_ID
  OCI_SUBNET_ID
  OCI_IMAGE_ID
  OCI_AD_NAME
  SSH_PUBLIC_KEY_PATH
)

OCI_OCPUS="${OCI_OCPUS:-2}"
OCI_MEMORY_GB="${OCI_MEMORY_GB:-12}"
OCI_BOOT_VOLUME_GB="${OCI_BOOT_VOLUME_GB:-50}"
OCI_DISPLAY_NAME="${OCI_DISPLAY_NAME:-free-arm-1}"

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"
LOG_FILE="${RUNNER_TEMP:-/tmp}/launch.log"

write_output() {
  local key="$1"
  local value="$2"
  if [[ "$OUTPUT_FILE" != "/dev/null" ]]; then
    {
      echo "${key}=${value}"
    } >>"$OUTPUT_FILE"
  fi
}

mark_success() {
  local instance_id="$1"
  local public_ip="${2:-}"
  local already_existed="${3:-false}"
  write_output "success" "true"
  write_output "instance_id" "$instance_id"
  write_output "public_ip" "$public_ip"
  write_output "already_existed" "$already_existed"
  echo "SUCCESS: instance_id=${instance_id} public_ip=${public_ip:-pending}"
  exit 0
}

mark_failure() {
  write_output "success" "false"
  exit 1
}

find_existing_instance() {
  oci compute instance list \
    --compartment-id "$OCI_COMPARTMENT_ID" \
    --display-name "$OCI_DISPLAY_NAME" \
    --all \
    --output json 2>/dev/null | jq -r '
      .data[]
      | select(."lifecycle-state" == "RUNNING" or ."lifecycle-state" == "PROVISIONING")
      | .id
    ' | head -n1
}

get_public_ip() {
  local instance_id="$1"
  local vnic_id
  vnic_id="$(oci compute vnic-attachment list \
    --compartment-id "$OCI_COMPARTMENT_ID" \
    --instance-id "$instance_id" \
    --query 'data[0]."vnic-id"' \
    --raw-output 2>/dev/null || true)"

  if [[ -z "$vnic_id" || "$vnic_id" == "null" ]]; then
    echo ""
    return
  fi

  oci network vnic get \
    --vnic-id "$vnic_id" \
    --query 'data."public-ip"' \
    --raw-output 2>/dev/null || echo ""
}

wait_for_public_ip() {
  local instance_id="$1"
  local ip=""
  local attempt

  for attempt in $(seq 1 12); do
    ip="$(get_public_ip "$instance_id")"
    if [[ -n "$ip" && "$ip" != "null" ]]; then
      echo "$ip"
      return 0
    fi
    sleep 10
  done

  echo ""
}

existing_id="$(find_existing_instance)"
if [[ -n "$existing_id" && "$existing_id" != "null" && "$existing_id" != "None" ]]; then
  echo "Instance already exists with display name '${OCI_DISPLAY_NAME}': ${existing_id}"
  public_ip="$(get_public_ip "$existing_id")"
  mark_success "$existing_id" "$public_ip" "true"
fi

shape_config="{\"ocpus\":${OCI_OCPUS},\"memoryInGBs\":${OCI_MEMORY_GB}}"

set +e
oci compute instance launch \
  --compartment-id "$OCI_COMPARTMENT_ID" \
  --availability-domain "$OCI_AD_NAME" \
  --shape "VM.Standard.A1.Flex" \
  --shape-config "$shape_config" \
  --subnet-id "$OCI_SUBNET_ID" \
  --image-id "$OCI_IMAGE_ID" \
  --ssh-authorized-keys-file "$SSH_PUBLIC_KEY_PATH" \
  --assign-public-ip true \
  --display-name "$OCI_DISPLAY_NAME" \
  --boot-volume-size-in-gbs "$OCI_BOOT_VOLUME_GB" \
  2>&1 | tee "$LOG_FILE"
launch_exit=${PIPESTATUS[0]}
set -e

launch_output="$(cat "$LOG_FILE")"

if [[ $launch_exit -eq 0 ]]; then
  instance_id="$(echo "$launch_output" | jq -r '.data.id // empty' 2>/dev/null || true)"
  if [[ -z "$instance_id" ]]; then
    instance_id="$(echo "$launch_output" | grep -oE 'ocid1\.instance\.[^"[:space:]]+' | head -n1 || true)"
  fi
  if [[ -n "$instance_id" ]]; then
    echo "Launch succeeded. Waiting for public IP..."
    public_ip="$(wait_for_public_ip "$instance_id")"
    mark_success "$instance_id" "$public_ip" "false"
  fi
fi

if echo "$launch_output" | grep -qiE 'Out of host capacity|OutOfHostCapacity'; then
  echo "Out of host capacity (expected). Will retry on next scheduled run."
  mark_failure
fi

if echo "$launch_output" | grep -qiE 'LimitExceeded|Service limit'; then
  echo "Service limit reached. Check if an instance already exists in the tenancy."
  # Re-check in case limit is from duplicate name attempt
  existing_id="$(find_existing_instance)"
  if [[ -n "$existing_id" && "$existing_id" != "null" && "$existing_id" != "None" ]]; then
    public_ip="$(get_public_ip "$existing_id")"
    mark_success "$existing_id" "$public_ip" "true"
  fi
  mark_failure
fi

echo "Launch failed. Last output:"
echo "$launch_output"
mark_failure
