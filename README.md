OCI Always Free ARM Grabber

Automated retries to provision two Oracle Cloud Always Free VM.Standard.A1.Flex (Ampere) instances when capacity is available. Default size per instance: 2 OCPU / 12 GB RAM / 100 GB boot (4 OCPU / 24 GB total — the free tier maximum). Runs on GitHub Actions and sends Telegram only when a new instance is created.

Inspired by futchas/oracle-cloud-free-arm-instance, heykapil/oci-free-arm-instance, and mohankumarpaluru/oracle-freetier-instance-creation.

Features





Scheduled retry every 10 minutes (plus manual runs)



Telegram alert only on new success (not on "Out of host capacity" failures)



Configurable OCPU / RAM / boot volume via GitHub Secrets



Provisions free-arm-1 and free-arm-2 (one launch attempt per workflow run)



Auto-disables the workflow after both instances exist



Pip cache for faster oci-cli installs

GitHub Actions minutes







Repo visibility



Guidance





Public



Standard GitHub-hosted runners are free for public repos — best for 24/7 cron





Private



~2–3 min/run × ~4,320 runs/month exceeds the 2,000 free minutes — use a slower cron (*/30 or hourly) or workflow_dispatch only

To slow the schedule, edit cron in [.github/workflows/oci-arm-grab.yml](.github/workflows/oci-arm-grab.yml).

Quick start





Push this repository to GitHub (public recommended for unlimited Actions minutes).



Complete the OCI credentials checklist below.



Add all GitHub Secrets.



Go to Actions → OCI ARM Grab → Run workflow.



You may get up to two Telegram messages (one per instance). When both exist, the workflow disables itself automatically.

OCI credentials checklist

Complete these in the OCI Console if you have not already.

A. API authentication





Profile (top right) → User Settings → API Keys → Add API Key → Generate API Key Pair.



Download oci_api_key.pem (keep it safe).



Copy fingerprint from the configuration preview.



Copy User OCID from User Settings.



Copy Tenancy OCID from Profile → Tenancy (same value used for compartment on Always Free accounts).

B. Region and networking





Note your home region identifier (e.g. ap-tokyo-1, eu-frankfurt-1).



Menu → Networking → Virtual Cloud Networks → your VCN → Subnets → public subnet → copy OCID.



Menu → Compute → Instances → Create instance → Placement → copy Availability domain name exactly (e.g. Uocm:AP-TOKYO-1-AD-1).



On the same wizard → Image and shape → Change image → pick Canonical Ubuntu (ARM) → copy image OCID (must match your region). Cancel the wizard afterward.

C. SSH key





On your machine:

ssh-keygen -t ed25519 -f ~/.ssh/oci_arm -N ""
cat ~/.ssh/oci_arm.pub

Copy the full ssh-ed25519 ... line for GitHub Secrets.

D. Telegram bot





Message @BotFather → /newbot → save the bot token.



Message your bot, then open:

https://api.telegram.org/bot<TOKEN>/getUpdates

Copy your chat id from the JSON (message.chat.id).

GitHub Secrets

Repository → Settings → Secrets and variables → Actions → New repository secret.

OCI authentication







Secret



Description





OCI_CLI_USER



User OCID





OCI_CLI_TENANCY



Tenancy OCID





OCI_COMPARTMENT_ID



Compartment OCID (same as tenancy OCID for root compartment)





OCI_CLI_FINGERPRINT



API key fingerprint





OCI_CLI_KEY_CONTENT



Full PEM file (-----BEGIN... through -----END...)





OCI_CLI_REGION



Region identifier (e.g. ap-tokyo-1)

VM configuration







Secret



Description



Default if omitted





OCI_SUBNET_ID



Public subnet OCID



— (required)





OCI_AD_NAME



Availability domain name



— (required)





OCI_IMAGE_ID



ARM-compatible image OCID in your region



— (required)





SSH_PUBLIC_KEY



SSH public key (single line)



— (required)





OCI_INSTANCE_NAMES



Comma-separated display names



free-arm-1,free-arm-2

Sizing is fixed in the workflow (no secrets needed): 2 OCPU, 12 GB RAM, 100 GB boot per instance. Optional override: set secrets OCI_OCPUS, OCI_MEMORY_GB, OCI_BOOT_VOLUME_GB and add them to the workflow env block if you change [oci-arm-grab.yml](.github/workflows/oci-arm-grab.yml).

Free tier limit: up to 4 OCPUs and 24 GB RAM total across all A1 instances — two instances at 2/12 each uses the full allowance.

Telegram (success notifications only)







Secret



Description





TELEGRAM_BOT_TOKEN



Bot token from BotFather





TELEGRAM_CHAT_ID



Your chat ID

How it works

Every 10 min → install oci-cli → check free-arm-1 & free-arm-2
  → Both exist?     → disable workflow (no Telegram)
  → One missing?    → try launch (2 OCPU / 12 GB / 100 GB)
  → New instance?   → Telegram (1/2 or 2/2 progress)
  → Out of capacity → log only, retry later

Scripts:





[scripts/try_launch.sh](scripts/try_launch.sh) — one launch attempt, idempotency check by display name



[scripts/notify_telegram.sh](scripts/notify_telegram.sh) — sends Telegram on new instance only

After success





Check Telegram for the instance OCID and SSH command (when public IP is ready).



Confirm the instance in OCI Console → Compute → Instances.



The workflow is auto-disabled once both instances exist. Re-enable from Actions only if you intentionally want another grab attempt.

Default SSH user for Oracle Linux / Ubuntu images: opc or ubuntu depending on the image.

Security





Never commit .pem files, .env, or OCIDs in the repository.



Store credentials only in GitHub Secrets.



Rotate API keys if exposed.



Use IAM policies that limit API access to what compute/network need.

Troubleshooting







Symptom



What to check





Auth errors in Actions log



OCI_CLI_* secrets, PEM newlines, fingerprint match





Always "Out of host capacity"



Normal; keep retrying or try a less busy region at signup





Wrong image errors



OCI_IMAGE_ID must be ARM-compatible and in your home region





No Telegram message



TELEGRAM_* secrets; notification runs only on new launch success





Workflow stopped running



Disabled after success, or repo inactive 60+ days (GitHub policy)

License

MIT — use at your own risk; comply with Oracle Cloud terms.
