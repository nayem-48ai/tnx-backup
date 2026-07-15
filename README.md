# 📦 TNx Backup Tool

A clean, menu-driven **Termux** tool to back up your Android device storage to **MEGA** (powered by [rclone](https://rclone.org)), with restore, incremental sync, retention, reporting and more.

> Android `/sdcard` → MEGA cloud → restore anywhere.

---

## ✨ Features

| Feature | Description |
|---|---|
| 📊 **Device scan** | Full storage overview + per-folder sizes + largest files. Exports **HTML & CSV** reports. |
| ☁️ **Full mirror backup** | Uploads exact folder structure (incl. hidden files) to MEGA. |
| 🔄 **Incremental backup** | `sync` mode — only changed/new files upload (fast, saves quota). |
| 🗜️ **Zip backup** | Packs selection into a single `.tar.gz` archive and uploads it. |
| ♻️ **Restore** | **Asks first**: restore *exact structure* or *download a zip*. Confirms target before writing. |
| 📁 **Selective profiles** | Pick what to back up: `full`, `photos`, `important`, or your own. |
| 🧹 **Clean cloud** | Delete a single archive, empty mirror/archives, or wipe all (double-confirm). |
| 📈 **Cloud status** | MEGA quota + list of existing backups & sizes. |
| ♻️ **Retention policy** | Keep N newest backups and/or delete older than N days (user-configurable). |
| 🔀 **Multi-remote** | Add several MEGA accounts; choose per backup or use as fallback. |
| 🔋 **Battery / Wi-Fi guard** | Blocks backup on low battery or mobile data (configurable, degrades gracefully). |
| 🕘 **History / manifest** | JSON log of every backup with time, size, status. |
| 🩺 **Self-test** | Health check: deps, storage, config, remotes, termux-api. |
| 🚦 **First-run wizard** | One-time guided setup (deps, storage permission, MEGA login). |
| 🎨 **Colored TUI** | Clean numbered menu with progress bars & completion summaries. |
| ⚙️ **Config file** | All behavior editable in `config/tnxbackup.conf`. |

### Backup scope (default)
- ✅ Everything in `/sdcard` **including hidden files**
- ✅ `Android/media/**` only
- ❌ Excludes `Android/data/` and `Android/obb/`

---

## 🚀 Installation — no install needed! (portable)

**You do NOT need to install rclone.** On first run the tool auto-downloads the correct
static **rclone** (and **jq**) binary for your CPU into its own `bin/` folder — no root,
no system packages, nothing global. You only need **internet + git + unzip**.

### One-liner (new user)
```bash
git clone https://github.com/nayem-48ai/tnx-backup && cd tnx-backup && ./tnxbackup.sh
```
That's the only command a new user needs — clone, enter the folder, and the tool
self-bootstraps (deps, `rclone`, MEGA setup) and opens the menu.

<details><summary>Step-by-step (same thing, expanded)</summary>

```bash
# 1. Grant storage access (Termux)
termux-setup-storage

# 2. Get the tool
git clone https://github.com/nayem-48ai/tnx-backup.git
cd tnx-backup
chmod +x tnxbackup.sh lib/*.sh

# 3. Run — it self-bootstraps everything else
./tnxbackup.sh
```
</details>

That's it. Anyone can clone and run on their own device with their own MEGA account.

### What it auto-fetches
- **On Termux:** the tool installs **`rclone`** via `pkg install rclone` (the cgo build,
  which uses the OS resolver and works even when `/etc/resolv.conf` is missing/unwritable
  — the static binary cannot resolve DNS there). `jq` is downloaded into `./bin`.
- **On desktop / PRoot / macOS:** it downloads the official **static rclone** (and `jq`)
  into its own `./bin/` folder — no root, no system packages.

| Tool | Why | Source |
|---|---|---|
| `rclone` | MEGA transfer engine | Termux: `pkg install rclone` · else: downloads.rclone.org (official static build, **includes MEGA**) |
| `jq` | JSON parsing (history/quota) | jqlang GitHub releases (into `./bin`) |

> ⚠️ Note: some distro package managers (e.g. Debian/Ubuntu `apt`) ship an rclone
> build **without** the MEGA backend — which is why, off Termux, this tool fetches the
> **official** static rclone itself so MEGA always works.

### Optional
- `pigz` — faster multi-core zip (falls back to `gzip` automatically if absent).
- **Termux:API** app + `pkg install termux-api` — enables battery/Wi-Fi guard & notifications (degrades gracefully without it).
- If `unzip`/`curl` are missing: `pkg install unzip curl` (Termux) or `apt install unzip curl`.

---

## 🧹 Delete / start fresh (uninstall)

To remove **everything** and return to a clean state (so you can set up as a brand-new user), run:

```bash
rm -rf ~/tnx-backup          # the tool, its ./bin, config, logs, reports
pkg uninstall -y rclone      # remove rclone (Termux) — skip if you use rclone elsewhere
rm -rf ~/.config/rclone      # your MEGA credentials / remote config
# optional: pkg uninstall -y jq   # only if you installed jq system-wide
```

This deletes all local config and saved MEGA credentials. To become a new user again, just re-run the one-liner:

```bash
git clone https://github.com/nayem-48ai/tnx-backup && cd tnx-backup && ./tnxbackup.sh
```

> 💡 This only removes the tool and its config **on this device**. Your files in MEGA
> stay in the cloud — re-adding the same MEGA account (menu **11**) will see them again.

---

## 🖐️ First run

The **first-run wizard** launches automatically and will:
1. Check/install dependencies
2. Ensure `/sdcard` is readable (`termux-setup-storage`)
3. Set up your MEGA account (email + password → stored in rclone config)
4. Run a quick connection test

You only do this once.

---

## 📋 Main menu

```
 1) Scan device (storage report + HTML/CSV)
 2) Full mirror backup
 3) Incremental backup (sync changes)
 4) Zip (archive) backup
 5) Restore (structure or zip)
 6) Cloud status & quota
 7) Clean MEGA cloud
 8) Backup history
 9) Settings
10) Self-test / health check
11) Setup / add MEGA account
 0) Exit
```

### Command-line (non-interactive)
```bash
./tnxbackup.sh scan          # generate scan report
./tnxbackup.sh backup        # full mirror backup
./tnxbackup.sh incremental   # sync changed files
./tnxbackup.sh zip           # archive backup
./tnxbackup.sh status        # cloud status
./tnxbackup.sh selftest      # health check
```

Great for **scheduling** with `termux-job-scheduler` or `cron`.

---

## ☁️ How it works

```
/sdcard ──(rclone + filters)──► MEGA:/TNxBackup/
                                   ├── mirror/     (exact structure)
                                   └── archives/   (dated .tar.gz files)
```

- **Mirror mode** uses `rclone copy` (additive) or `rclone sync` (incremental, mirrors deletions).
- **Zip mode** builds a `tar.gz` of the profile's file list, then uploads a single archive named `sdcard-<profile>-YYYYMMDD_HHMM.tar.gz`.
- **Filters** (`config/filters.txt` and `config/profiles/*.profile`) decide what's included. First match wins; `-` excludes, `+` includes.
- **Retention** runs automatically after each backup based on your settings.

---

## 🗂️ Project structure

```
tnx-backup/
├── tnxbackup.sh              # main entrypoint + menu
├── lib/
│   ├── common.sh             # colors, logging, helpers, history, config loader
│   ├── bootstrap.sh          # portable auto-download of rclone/jq (no install)
│   ├── config.sh             # first-run wizard, MEGA setup, self-test
│   ├── guard.sh              # battery / Wi-Fi guard
│   ├── scan.sh               # device scan + HTML/CSV reports
│   ├── backup.sh             # mirror / incremental / zip engine + profiles
│   ├── restore.sh            # restore (structure or zip)
│   ├── cloud.sh              # status, clean, retention, history
│   └── settings.sh           # config editor + multi-remote mgmt
├── config/
│   ├── tnxbackup.conf        # main configuration
│   ├── filters.txt           # default include/exclude rules
│   └── profiles/             # backup profiles
│       ├── full.profile
│       ├── photos.profile
│       └── important.profile
├── logs/                     # run logs + history.json
├── reports/                  # generated scan reports
└── README.md
```

---

## ⚙️ Configuration (`config/tnxbackup.conf`)

| Key | Meaning |
|---|---|
| `SOURCE_ROOT` | Folder to back up (default `/sdcard`) |
| `REMOTES` | rclone remote name(s), space-separated for multi-remote |
| `REMOTE_BASE` | Base folder in MEGA (default `TNxBackup`) |
| `DEFAULT_MODE` | `mirror` or `zip` |
| `DEFAULT_PROFILE` | Which profile to preselect |
| `RETENTION_KEEP` | Keep N newest archives (0 = keep all) |
| `RETENTION_DAYS` | Delete archives older than N days (0 = off) |
| `GUARD_ENABLE` | Enable battery/Wi-Fi guard |
| `GUARD_MIN_BATTERY` | Minimum battery % to run |
| `GUARD_REQUIRE_WIFI` | Only run on Wi-Fi |
| `RCLONE_TRANSFERS` / `RCLONE_CHECKERS` | Transfer tuning |
| `ZIP_COMPRESSOR` | `pigz` (fast, multi-core) or `gzip` |

### Custom profiles
Create `config/profiles/myprofile.profile` with rclone filter rules:
```
# DESC: My custom set
+ /DCIM/**
+ /Documents/**
- **
```

---

## 🔐 Notes on privacy

- Credentials are stored by **rclone** in its own config (obscured, not plain text).
- MEGA mirror mode is **not** client-side zero-knowledge encrypted by this tool. If you need that, configure an rclone `crypt` remote on top of MEGA.
- Change your MEGA password if you ever shared it during setup/testing.

---

## 🛠️ Troubleshooting

| Problem | Fix |
|---|---|
| `Missing required tools` | `pkg install rclone jq tar pigz coreutils` |
| `/sdcard not readable` | Run `termux-setup-storage`, accept the popup |
| Battery/Wi-Fi always "unknown" | Install `termux-api` app + `pkg install termux-api` |
| Remote offline | Re-run option **11** to reconfigure MEGA |
| Backup too big for MEGA free 20 GB | Use a smaller profile or add a 2nd remote |

---

## 📄 License
MIT — do whatever you like, no warranty.

*TNx Backup Tool v1.0*
