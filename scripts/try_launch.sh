#!/usr/bin/env bash
set -euo pipefail

# Provision two VM.Standard.A1.Flex instances (default: free-arm-1, free-arm-2).
# Each run: skips existing instances; launches the first missing name (2 OCPU / 12 GB / 100 GB each).

REQUIRED_VARS=(
  OCI_COMPARTMENT_ID
  OCI_SUBNET_ID
  OCI_IMAGE_ID
  OCI_AD_NAME
  SSH_PUBLIC_KEY_PATH
)

OCI_OCPUS="${OCI_OCPUS:-2}"
OCI_MEMORY_GB="${OCI_MEMORY_GB:-12}"
OCI_BOOT_VOLUME_GB="${OCI_BOOT_VOLUME_GB:-100}"
OCI_INSTANCE_NAMES="${OCI_INSTANCE_NAMES:-free-arm-1,free-arm-2}"

LAUNCH_RESULT=""
LAUNCH_DISPLAY_NAME=""
LAUNCH_INSTANCE_ID=""
LAUNCH_PUBLIC_IP=""

for var in "${REQUIRED_VARS[@]}"; do
  if [[ -z "${!var:-}" ]]; then
    echo "Missing required environment variable: $var" >&2
    exit 1
  fi
done

OUTPUT_FILE="${GITHUB_OUTPUT:-/dev/null}"
LOG_FILE="${RUNNER_TEMP:-/tmp}/launch.log"
shape_config="{\"ocpus\":${OCI_OCPUS},\"memoryInGBs\":${OCI_MEMORY_GB}}"

write_output() {
  local key="$1"
  local value="$2"
  if [[ "$OUTPUT_FILE" != "/dev/null" ]]; then
    echo "${key}=${value}" >>"$OUTPUT_FILE"
  fi
}

find_existing_instance() {
  local display_name="$1"
  oci compute instance list \
    --compartment-id "$OCI_COMPARTMENT_ID" \
    --display-name "$display_name" \
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

parse_instance_id_from_launch() {
  local launch_output="$1"
  local instance_id
  instance_id="$(echo "$launch_output" | jq -r '.data.id // empty' 2>/dev/null || true)"
  if [[ -z "$instance_id" ]]; then
    instance_id="$(echo "$launch_output" | grep -oE 'ocid1\.instance\.[^"[:space:]]+' | head -n1 || true)"
  fi
  echo "$instance_id"
}

# Sets LAUNCH_RESULT to: created | exists | capacity | failed
launch_one_instance() {
  local display_name="$1"
  LAUNCH_RESULT=""
  LAUNCH_DISPLAY_NAME="$display_name"
  LAUNCH_INSTANCE_ID=""
  LAUNCH_PUBLIC_IP=""

  echo "Attempting launch: ${display_name} (${OCI_OCPUS} OCPU, ${OCI_MEMORY_GB} GB RAM, ${OCI_BOOT_VOLUME_GB} GB boot)"

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
    --display-name "$display_name" \
    --boot-volume-size-in-gbs "$OCI_BOOT_VOLUME_GB" \
    2>&1 | tee "$LOG_FILE"
  local launch_exit=${PIPESTATUS[0]}
  set -e

  local launch_output
  launch_output="$(cat "$LOG_FILE")"

  if [[ $launch_exit -eq 0 ]]; then
    local instance_id
    instance_id="$(parse_instance_id_from_launch "$launch_output")"
    if [[ -n "$instance_id" ]]; then
      echo "Launch succeeded for ${display_name}. Waiting for public IP..."
      LAUNCH_RESULT="created"
      LAUNCH_INSTANCE_ID="$instance_id"
      LAUNCH_PUBLIC_IP="$(wait_for_public_ip "$instance_id")"
      return 0
    fi
  fi

  if echo "$launch_output" | grep -qiE 'Out of host capacity|OutOfHostCapacity'; then
    echo "Out of host capacity for ${display_name}."
    LAUNCH_RESULT="capacity"
    return 2
  fi

  if echo "$launch_output" | grep -qiE 'LimitExceeded|Service limit'; then
    echo "Service limit reached for ${display_name}."
    local existing_id
    existing_id="$(find_existing_instance "$display_name")"
    if [[ -n "$existing_id" && "$existing_id" != "null" && "$existing_id" != "None" ]]; then
      LAUNCH_RESULT="exists"
      LAUNCH_INSTANCE_ID="$existing_id"
      LAUNCH_PUBLIC_IP="$(get_public_ip "$existing_id")"
      return 0
    fi
    LAUNCH_RESULT="failed"
    return 3
  fi

  echo "Launch failed for ${display_name}:"
  echo "$launch_output"
  LAUNCH_RESULT="failed"
  return 1
}

INSTANCE_NAMES=()
while IFS=',' read -ra _parts; do
  for part in "${_parts[@]}"; do
    part="$(echo "$part" | xargs)"
    [[ -n "$part" ]] && INSTANCE_NAMES+=("$part")
  done
done <<<"$OCI_INSTANCE_NAMES"

if [[ ${#INSTANCE_NAMES[@]} -eq 0 ]]; then
  echo "OCI_INSTANCE_NAMES is empty." >&2
  exit 1
fi

existing_count=0
missing_names=()

for name in "${INSTANCE_NAMES[@]}"; do
  existing_id="$(find_existing_instance "$name")"
  if [[ -n "$existing_id" && "$existing_id" != "null" && "$existing_id" != "None" ]]; then
    echo "Already provisioned: ${name} (${existing_id})"
    existing_count=$((existing_count + 1))
  else
    missing_names+=("$name")
  fi
done

target_count=${#INSTANCE_NAMES[@]}
write_output "instances_existing" "$existing_count"
write_output "instances_target" "$target_count"

if [[ ${#missing_names[@]} -eq 0 ]]; then
  write_output "success" "true"
  write_output "all_complete" "true"
  write_output "new_instance_created" "false"
  echo "All ${target_count} instance(s) already exist. Nothing to launch."
  exit 0
fi

echo "Missing ${#missing_names[@]} of ${target_count} instance(s). Trying: ${missing_names[0]}"

set +e
launch_one_instance "${missing_names[0]}"
launch_rc=$?
set -e

new_count=$existing_count
if [[ "$LAUNCH_RESULT" == "created" || "$LAUNCH_RESULT" == "exists" ]]; then
  new_count=$((existing_count + 1))
fi

all_complete="false"
[[ $new_count -ge $target_count ]] && all_complete="true"

case "$LAUNCH_RESULT" in
  created)
    write_output "success" "true"
    write_output "all_complete" "$all_complete"
    write_output "new_instance_created" "true"
    write_output "instance_id" "$LAUNCH_INSTANCE_ID"
    write_output "public_ip" "$LAUNCH_PUBLIC_IP"
    write_output "display_name" "$LAUNCH_DISPLAY_NAME"
    write_output "instances_existing" "$new_count"
    echo "Created ${LAUNCH_DISPLAY_NAME}. Progress: ${new_count}/${target_count}"
    exit 0
    ;;
  exists)
    write_output "success" "true"
    write_output "all_complete" "$all_complete"
    write_output "new_instance_created" "false"
    write_output "instance_id" "$LAUNCH_INSTANCE_ID"
    write_output "display_name" "$LAUNCH_DISPLAY_NAME"
    write_output "instances_existing" "$new_count"
    echo "Instance ${LAUNCH_DISPLAY_NAME} already exists. Progress: ${new_count}/${target_count}"
    exit 0
    ;;
  capacity)
    write_output "success" "false"
    write_output "all_complete" "false"
    write_output "new_instance_created" "false"
    write_output "instances_existing" "$existing_count"
    exit 1
    ;;
  *)
    write_output "success" "false"
    write_output "all_complete" "false"
    write_output "new_instance_created" "false"
    write_output "instances_existing" "$existing_count"
    exit 1
    ;;
esac
