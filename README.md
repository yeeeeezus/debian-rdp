# Cloud RDP — Self-Redeploying Debian 13 GNOME Remote Desktop

A **real Debian 13 (trixie)** desktop with the **official GNOME 48 GUI**, served
through the browser via noVNC, with **continuous GitHub backup** of all user
work. Runs fully unprivileged (fakechroot) inside a sandbox that has no root,
no systemd and no ptrace.

**This is the PUBLIC repo (setup kit).** User files live in the PRIVATE repo
**`yeeeeezus/rdp-data`** — never commit data, tokens or passwords here.

---

## FOR THE AI AGENT — redeploy instructions

> The user gave you this repo name (`debian-rdp`) and a GitHub token.
> Goal: rebuild their complete remote desktop and restore their work.
> Everything runs WITHOUT root. One command does it all:

```bash
# 1. clone this repo (public - no token needed for the clone itself)
git clone https://github.com/yeeeeezus/debian-rdp.git /home/z/rdp-setup

# 2. bootstrap: builds the instance + restores user data from rdp-data
#    (~6-10 min: downloads ~1.4 GB of debs, extracts, fixes, restores, starts)
cd /home/z/rdp-setup
bash bootstrap.sh <THE-GITHUB-TOKEN>

# 3. verify (expect all OK lines):
/home/z/debian/bin/debian-status
```

`bootstrap.sh` handles everything end-to-end. What it does, in order
(each stage is also runnable alone from `deploy/`):

1. Authenticates the token, clones the **private data repo**
   (`rdp-data`) — user files, VAULT (tokens), VNC password.
2. `deploy/gnome-download.sh` — apt resolves the FULL closure of GNOME 48 +
   apps + VNC stack into `~/debian/debs` (unprivileged, empty-dpkg-status
   trick; self-healing against missing packages).
3. `deploy/gnome-extract.sh` — `dpkg -x` every deb into
   `/home/z/debian/sysroot`, then regenerates GLib schemas / mime / icon /
   desktop caches.
4. `deploy/gnome-setup.sh` — the critical fakechroot fixups (this part took
   the most debugging — do not skip any of it):
   - system users (**messagebus!**, polkitd, colord…) in `/etc/passwd`
   - `gnome-ldfix.sh`: ~1200 **RELATIVE** symlinks from non-default lib dirs
     (gvfs/, gnome-settings-daemon-48/, localsearch/, …) into
     `/usr/lib/x86_64-linux-gnu/` — ld.so opens bypass fakechroot
     translation, absolute targets break
   - system dconf db (mutter experimental-features OFF — scale-monitor
     breaks rendering on Xvnc; animations off; Debian ceratopsian wallpaper)
   - custom session `gnome-rdp.session` WITHOUT gsd-Power (UPower needs a
     setuid polkit helper → crash-loop → "Oh no!" failure dialog)
   - system dbus must run `--nofork` in background (`--fork` dies silently
     under fakechroot); socket: `/run/dbus/system_bus_socket`
   - VNC password restore (same password every rebuild → seamless reconnect)
5. `deploy/gnome-desktop-integration.sh` — VAULT folder, desktop launchers,
   terminal helpers, START-HERE guide.
6. User data restore from `rdp-data` → sysroot home; the token is written
   into the VAULT so the backup daemon self-heals.
7. Start + verify (`debian-status`, HTTP 200 + websocket 101 through the
   preview proxy).

### The two repos

| Repo | Visibility | Contents |
|---|---|---|
| `debian-rdp` (this) | **public** | setup scripts, config, noVNC page, Mininet kit, this runbook |
| `rdp-data` | **private** | `home/` (Desktop, Documents, Downloads, … incl. VAULT), `vnc/` (password + credentials) |

### Service ports

websockify serves noVNC on **0.0.0.0:3000**; the z.ai web preview proxies
**:81 → :3000 → VNC :5901**. The page auto-connects with the VNC password,
fits ANY screen perfectly (dynamic RFB resize follows the browser window
1:1 — phones too) and auto-reconnects.

### Continuous backup

The supervisor also babysits `rdp-save-daemon` (host-side): rsync user dirs
→ `rdp-data/home/`, git commit + push (10 s poll, 20 s debounce, 10-min
periodic, `/tmp/rdp-save-trigger` for instant saves). It reads
`GH_TOKEN`/`GH_USER` from `~/Desktop/VAULT/tokens.env` — if the user updates
the token there, the remote self-heals. If both repos ever need
re-creating after a reset: `deploy/gnome-runtime/rdp-repos-setup.sh <TOKEN>`.

### Known-good environment

Debian 13 host, user `z`, no sudo, 2 CPUs / 4 GB RAM / 10 GB disk, Caddy
preview proxy on :81. If the environment differs (e.g. real root available),
GNOME + tigervnc + novnc can be apt-installed natively and only the
fakechroot-specific steps change.

---

## FOR THE USER — how your desktop persists

| What | Where |
|---|---|
| Your files (Desktop, Documents, Pictures, Downloads…) | synced to **rdp-data** (private) every few minutes |
| Instant backup | double-click **Save Now** on the desktop (or run `save-now`) |
| Backup status | `save-status` in a terminal |
| Everything else (apps, OS config) | rebuilt automatically from **debian-rdp** (this repo) |

**Sessions are temporary — the repos are permanent.** Anything you keep in
Desktop/Documents/Pictures/Downloads/Music/Videos survives (tokens in the
VAULT too). Files dumped elsewhere (e.g. /tmp) do not.

To move to a new session: open a new chat and tell the agent:
> "Deploy my cloud RDP again — public repo **debian-rdp**, private data repo
> **rdp-data**, GitHub token is in my vault."

**Security notes**
- This repo is public on purpose — it contains **no secrets**. Never put
  tokens, passwords or personal files here.
- `rdp-data` is private and holds your VAULT (tokens). **Keep it private.**
- If a token ever leaks, rotate it and update the vault.

## What's inside the desktop

Official Debian 13 GNOME 48 (Adwaita, ceratopsian wallpaper, top bar +
Activities overview + dock), Firefox ESR, LibreOffice, Thunderbird, VLC,
GIMP, Remmina (for the Windows RDP container), Telegram Web launcher,
GitHub + Hugging Face launchers, terminal helpers (`vault`, `tg-send`,
`hf-test`, `gh-me`), Mininet SDN lab (userns + Linux bridges), Wireshark,
nmap, qbittorrent, FileZilla, GCC/Python, and more.
