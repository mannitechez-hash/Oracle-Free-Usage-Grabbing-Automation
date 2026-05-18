# OCI Always Free ARM Grabber

Automated retries to provision an Oracle Cloud **Always Free** `VM.Standard.A1.Flex` (Ampere) instance when capacity is available. Runs on **GitHub Actions** and sends a **Telegram** message only when a new instance is successfully created.

Inspired by [futchas/oracle-cloud-free-arm-instance](https://github.com/futchas/oracle-cloud-free-arm-instance), [heykapil/oci-free-arm-instance](https://github.com/heykapil/oci-free-arm-instance), and [mohankumarpaluru/oracle-freetier-instance-creation](https://github.com/mohankumarpaluru/oracle-freetier-instance-creation).

## Features

- Scheduled retry every **10 minutes** (plus manual runs)
- **Telegram alert only on new success** (not on "Out of host capacity" failures)
- Configurable **OCPU / RAM / boot volume** via GitHub Secrets
- **Auto-disables** the workflow after success to avoid duplicate VMs
- Pip cache for faster `oci-cli` installs

## GitHub Actions minutes

| Repo visibility | Guidance |
|-----------------|----------|
| **Public** | Standard GitHub-hosted runners are free for public repos — best for 24/7 cron |
| **Private** | ~2–3 min/run × ~4,320 runs/month exceeds the 2,000 free minutes — use a slower cron (`*/30` or hourly) or `workflow_dispatch` only |

To slow the schedule, edit `cron` in [`.github/workflows/oci-arm-grab.yml`](.github/workflows/oci-arm-grab.yml).

## Quick start

1. Push this repository to GitHub (public recommended for unlimited Actions minutes).
2. Complete the [OCI credentials checklist](#oci-credentials-checklist) below.
3. Add all [GitHub Secrets](#github-secrets).
4. Go to **Actions** → **OCI ARM Grab** → **Run workflow**.
5. When you get a Telegram message, SSH into the instance. The workflow disables itself automatically.

## OCI credentials checklist

Complete these in the OCI Console if you have not already.

### A. API authentication

1. Profile (top right) → **User Settings** → **API Keys** → **Add API Key** → **Generate API Key Pair**.
2. Download `oci_api_key.pem` (keep it safe).
3. Copy **fingerprint** from the configuration preview.
4. Copy **User OCID** from User Settings.
5. Copy **Tenancy OCID** from Profile → Tenancy (same value used for compartment on Always Free accounts).

### B. Region and networking

6. Note your **home region** identifier (e.g. `ap-tokyo-1`, `eu-frankfurt-1`).
7. Menu → **Networking** → **Virtual Cloud Networks** → your VCN → **Subnets** → public subnet → copy **OCID**.
8. Menu → **Compute** → **Instances** → **Create instance** → **Placement** → copy **Availability domain** name exactly (e.g. `Uocm:AP-TOKYO-1-AD-1`).
9. On the same wizard → **Image and shape** → **Change image** → pick **Canonical Ubuntu** (ARM) → copy image **OCID** (must match your region). Cancel the wizard afterward.

### C. SSH key

10. On your machine:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oci_arm -N ""
cat ~/.ssh/oci_arm.pub
```

Copy the full `ssh-ed25519 ...` line for GitHub Secrets.

### D. Telegram bot

11. Message [@BotFather](https://t.me/BotFather) → `/newbot` → save the **bot token**.
12. Message your bot, then open:

`https://api.telegram.org/bot<TOKEN>/getUpdates`

Copy your **chat id** from the JSON (`message.chat.id`).

## GitHub Secrets

Repository → **Settings** → **Secrets and variables** → **Actions** → **New repository secret**.

### OCI authentication

| Secret | Description |
|--------|-------------|
| `OCI_CLI_USER` | User OCID |
| `OCI_CLI_TENANCY` | Tenancy OCID |
| `OCI_COMPARTMENT_ID` | Compartment OCID (same as tenancy OCID for root compartment) |
| `OCI_CLI_FINGERPRINT` | API key fingerprint |
| `OCI_CLI_KEY_CONTENT` | Full PEM file (`-----BEGIN...` through `-----END...`) |
| `OCI_CLI_REGION` | Region identifier (e.g. `ap-tokyo-1`) |

### VM configuration

| Secret | Description | Default if omitted |
|--------|-------------|-------------------|
| `OCI_SUBNET_ID` | Public subnet OCID | — (required) |
| `OCI_AD_NAME` | Availability domain name | — (required) |
| `OCI_IMAGE_ID` | ARM-compatible image OCID in your region | — (required) |
| `SSH_PUBLIC_KEY` | SSH public key (single line) | — (required) |
| `OCI_DISPLAY_NAME` | Instance display name | `free-arm-1` |
| `OCI_OCPUS` | Flex OCPUs | `2` |
| `OCI_MEMORY_GB` | Flex memory (GB) | `12` |
| `OCI_BOOT_VOLUME_GB` | Boot volume size (GB, min 50) | `50` |

**Free tier limit:** up to **4 OCPUs** and **24 GB** RAM total across all A1 instances in the tenancy.

### Telegram (success notifications only)

| Secret | Description |
|--------|-------------|
| `TELEGRAM_BOT_TOKEN` | Bot token from BotFather |
| `TELEGRAM_CHAT_ID` | Your chat ID |

## How it works

```text
Every 10 min → install oci-cli → launch VM.Standard.A1.Flex
  → Out of capacity?  → log only, job fails quietly
  → Success?         → Telegram + disable workflow
```

Scripts:

- [`scripts/try_launch.sh`](scripts/try_launch.sh) — one launch attempt, idempotency check by display name
- [`scripts/notify_telegram.sh`](scripts/notify_telegram.sh) — sends Telegram on new instance only

## After success

1. Check Telegram for the instance OCID and SSH command (when public IP is ready).
2. Confirm the instance in OCI Console → **Compute** → **Instances**.
3. The workflow is **auto-disabled**. Re-enable from **Actions** only if you intentionally want another grab attempt.

Default SSH user for Oracle Linux / Ubuntu images: `opc` or `ubuntu` depending on the image.

## Security

- Never commit `.pem` files, `.env`, or OCIDs in the repository.
- Store credentials only in GitHub Secrets.
- Rotate API keys if exposed.
- Use IAM policies that limit API access to what compute/network need.

## Troubleshooting

| Symptom | What to check |
|---------|----------------|
| Auth errors in Actions log | `OCI_CLI_*` secrets, PEM newlines, fingerprint match |
| Always "Out of host capacity" | Normal; keep retrying or try a less busy region at signup |
| Wrong image errors | `OCI_IMAGE_ID` must be ARM-compatible and in your home region |
| No Telegram message | `TELEGRAM_*` secrets; notification runs only on **new** launch success |
| Workflow stopped running | Disabled after success, or repo inactive 60+ days (GitHub policy) |

## License

MIT — use at your own risk; comply with [Oracle Cloud terms](https://www.oracle.com/corporate/contracts/cloud-services/).
