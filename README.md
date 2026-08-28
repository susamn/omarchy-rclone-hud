# Rclone Sync & Monitor Plugin for Omarchy

A universal [Rclone](https://rclone.org/) bar widget and interactive popup dashboard for Omarchy (`quickshell`).

Real-time monitoring of active sync processes, systemd & cron timers with a 24-hour projected schedule timeline, remote cloud storage quota gauges, and active FUSE mounts with 1-click controls.

---

## Highlights

- **Universal & Zero-Secret Discovery**:
  - Works out-of-the-box on any Linux machine running `rclone` and `systemd`/`cron`.
  - Never reads or exposes passwords, auth tokens, client secrets, or GPG keys.
- **Bar Widget Integration**:
  - Cloud icon (`󰅟`) in the desktop bar, matching the Network / Bluetooth / Audio widgets.
  - Switches to an active sync glyph (`󰑮`) with a pulsing corner **LED** whenever a data transfer (`sync` / `bisync` / `copy` / `move` / `check`) is running — a persistent `rclone mount` does **not** trip it.
  - The panel header carries the same LED: pulsing accent while syncing, dim when idle.
  - Tooltip showing the running transfer count, current throughput, or the next scheduled sync countdown.
- **Popup Dashboard** — same layout grammar as the MPD and Home Assistant panels: a compact header, text tabs, and thin-bordered cards on the panel fill.
  - **Overview**: a single **bandwidth** area chart of total rclone throughput (all processes, mounts included; sampled from `/proc/<pid>/io`); running transfer rows tagged with their kind (one-way sync / bi-directional / copy / move / check); a compact **mounts** summary that jumps to the Mounts tab; next-timer countdown with a **Sync now** button; and per-remote storage bars.
  - **Schedules**: discovered systemd (system + user) and cron timers — each tagged with its sync kind and scope — plus a 24-hour timeline ruler.
  - **Remotes**: configured remote cards with capacity bars (used / free / total / trash).
  - **Mounts**: active FUSE mounts with **Open folder** and **Unmount** actions.
  - **History**: recent sync runs read back from the systemd journal.

---

## File Structure

```
~/.config/omarchy/plugins/susamn.rclone/
├── manifest.json              # Plugin declaration, bar-widget kind, and settings schema
├── Panel.qml                  # Bar widget entry point & popup panel lifecycle
├── RcloneDashboard.qml        # Popup dashboard with multi-tab view & 24h timeline
├── Model.js                   # Pure JavaScript transformation & time helpers
├── scripts/
│   ├── status.py / status.sh  # Universal rclone, systemd, mount, and quota scraper
│   └── action.py / action.sh  # Sync triggers, folder opener, and unmount executor
├── tests/
│   ├── test_model.js          # JavaScript unit tests
│   └── test_status.py         # Python unit tests
├── VERSION                    # 1.0.0
├── LICENSE                    # MIT License
└── README.md                  # Documentation
```

---

## Installation & Enablement

In `~/.config/omarchy/shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [
        { "id": "susamn.rclone" }
      ]
    }
  }
}
```

Trigger a rescan:

```bash
omarchy-shell shell rescanPlugins
```

---

## License

MIT © [susamn](https://github.com/susamn)
