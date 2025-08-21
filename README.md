## README.md

# Elastic Artifacts Downloader

A single Bash script that builds and maintains a local mirror of Elastic artifacts:

* **Products covered:** `elastic-agent`, Beats (`filebeat`, `metricbeat`, `winlogbeat`, etc.), `apm-server`, `fleet-server`, `cloudbeat`, `endpoint-security` (dev), and Profiler (`pf-*`).
* **Platforms:** Linux (`linux-x86_64`, `.tar.gz`) and Windows (`windows-x86_64`, `.zip`).
* **Versions scanned:** Starting from **8.15.0** and **9.0.0** upward, plus **Endpoint artifacts** (manifests) starting at **8.0.0** and **9.0.0**.
* **Integrity:** SHA-512 checksum verification for every downloaded binary.
* **Logging:** Structured JSON lines to `/var/log/elastic-artifacts-downloader.log`.
* **Repo layout:** Files stored under `/var/www/repo/elastic-artifacts/…` ready to be served over HTTP.

---

## Why this exists

Keeping air-gapped or bandwidth-sensitive environments stocked with the right Elastic artifacts can be tedious. This script:

* Finds the **latest Elastic version** automatically (or uses a version you pass).
* Walks patch/minor/major versions to pull **all available builds**.
* Verifies downloads via **SHA-512** and skips files already present.
* Mirrors **Endpoint artifacts** by reading the manifest and fetching each referenced file.

---

## What gets downloaded

**Products map → path segment on artifacts site:**

```
apm-server            -> apm-server
auditbeat             -> beats/auditbeat
elastic-agent         -> beats/elastic-agent
filebeat              -> beats/filebeat
heartbeat             -> beats/heartbeat
metricbeat            -> beats/metricbeat
osquerybeat           -> beats/osquerybeat
packetbeat            -> beats/packetbeat
cloudbeat             -> cloudbeat
endpoint-security     -> endpoint-dev
fleet-server          -> fleet-server
winlogbeat            -> beats/winlogbeat
pf-host-agent         -> prodfiler
pf-elastic-collector  -> prodfiler
pf-elastic-symbolizer -> prodfiler
```

**Endpoint artifacts (Elastic Security):**

* Pulls `artifacts-<version>.zip` manifest from `artifacts.security.elastic.co`, then downloads each `relative_url` listed inside.

---

## Requirements

* Bash (tested on GNU bash 4+)
* `curl`, `wget`
* `jq` (for Endpoint manifest parsing)
* `zcat` (for reading zipped manifests)
* `sha512sum` (coreutils)
* Network access to:

  * `https://artifacts.elastic.co/downloads/*`
  * `https://artifacts.security.elastic.co/*`
  * `https://www.elastic.co/guide/en/elasticsearch/reference/current/es-release-notes.html`
* Write access to:

  * `/var/www/repo/elastic-artifacts/`
  * `/var/log/elastic-artifacts-downloader.log`

> If you want a different repo/log location, edit `local_repo_path` and `log_file` in the script.

---


**What the run does:**

1. If no argument is given, scrapes Elastic release notes to determine a **latest baseline version**.
2. For each product, attempts downloads for:

   * Linux: `<product>-<version>-linux-x86_64.tar.gz`
   * Windows: `<product>-<version>-windows-x86_64.zip`
3. Downloads `.sha512` and `.asc` alongside the file and **verifies SHA-512**.
4. Walks versions: increments **patch**, then **minor**, then **major** until no more versions are found.
5. Processes **Endpoint artifact manifests** for majors **8** and **9**, iterating patch/minor accordingly.
6. Fixes permissions for the Endpoint mirror subtree.

---

## Directory layout

```
/var/www/repo/elastic-artifacts/
└── beats/
    ├── filebeat/
    │   ├── filebeat-9.0.0-linux-x86_64.tar.gz
    │   ├── filebeat-9.0.0-linux-x86_64.tar.gz.sha512
    │   ├── filebeat-9.0.0-linux-x86_64.tar.gz.asc
    │   └── ...
    └── winlogbeat/
        └── winlogbeat-9.0.0-windows-x86_64.zip
└── apm-server/
└── fleet-server/
└── cloudbeat/
└── endpoint-dev/
└── prodfiler/
└── downloads/
    └── endpoint/
        └── manifest/
            ├── artifacts-8.12.0.zip
            └── ...
└── .downloads/
    └── endpoint/… (files resolved from manifest; the script uses `/.<relative_url>` paths)
```

> Note: Endpoint artifacts are saved under dot-prefixed paths that mirror their `relative_url` structure. This preserves hierarchy and makes it easy to serve as-is.

---

## Logging

* Logs are JSON lines (timestamp + message) to `/var/log/elastic-artifacts-downloader.log`, e.g.:

```json
{"ts":"2025-08-21 10:42:02","message":"Downloading filebeat version 9.0.0 for linux-x86_64 from https://artifacts.elastic.co/downloads/beats/filebeat/filebeat-9.0.0-linux-x86_64.tar.gz"}
{"ts":"2025-08-21 10:42:04","message":"SHA512 checksum verification passed for /var/www/repo/elastic-artifacts/beats/filebeat/filebeat-9.0.0-linux-x86_64.tar.gz"}
```

---

## Scheduling (cron/systemd)

**Cron:**

```bash
# Run nightly at 02:30
echo '30 2 * * * root /usr/local/bin/elastic-artifacts-downloader.sh >> /var/log/elastic-artifacts-downloader.log 2>&1' | sudo tee /etc/cron.d/elastic-artifacts
```

---

## Security & integrity notes

* **Checksum**: The script verifies `.sha512` for every binary. It **does not** verify the GPG signature (`.asc`). If you require signature validation, extend the script to import Elastic’s signing key and run `gpg --verify`.
* **Permissions**: Script ends with `chmod -R a+rx` on the Endpoint subtree. Adjust to your security policy.
* **Paths**: Defaults assume `/var/www/repo/elastic-artifacts/` and root access. Change to suit your environment.

---

## Troubleshooting

* **Empty files removed**: If a download yields a zero-byte file, the script deletes it and logs the failure.
* **Skipping existing files**: Already-present files (non-empty) are not re-downloaded.
* **“Version not available” logs**: Normal when the script probes patch/minor boundaries.
* **Missing tools**: Ensure `jq`, `zcat`, `curl`, `wget`, and `sha512sum` are installed and in `PATH`.

---

## FAQ

**Q: Can I mirror ARM or other architectures?**
A: Out of the box, it targets `linux-x86_64` and `windows-x86_64`. You can add more by expanding `linux_arch`/`windows_arch` and the `package_types` logic.

**Q: Can I change the mirror root?**
A: Yes—edit `local_repo_path` at the top of the script.

**Q: Will it re-download files every run?**
A: No—if a file exists and is non-empty, it’s skipped.

---

## Contributing

Issues and PRs welcome. Please include:

* OS/distro and Bash version
* Script log excerpt
* Exact command used and expected vs. actual result

---

## Disclaimer

This project is community-maintained and not affiliated with Elastic. Verify artifacts and signatures according to your organization’s security policy.
