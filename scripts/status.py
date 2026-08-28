#!/usr/bin/env python3
import json
import os
import re
import shutil
import subprocess
import time

# Operations that actually move file data and belong on the Overview
# "transfers" list / speed graph. A `mount` or `rcd` is a long-lived daemon,
# not a transfer, and must not churn the transfers card on every poll.
TRANSFER_OPS = {"sync", "bisync", "copy", "move", "check"}

def safe_run(cmd, timeout=5):
    try:
        res = subprocess.run(
            cmd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False
        )
        return res.stdout.strip()
    except Exception:
        return ""

def parse_size(bytes_val):
    if bytes_val is None:
        return "N/A"
    try:
        val = float(bytes_val)
    except (ValueError, TypeError):
        return "N/A"
    for unit in ["B", "KB", "MB", "GB", "TB", "PB"]:
        if val < 1024.0 or unit == "PB":
            return f"{val:.1f} {unit}" if unit != "B" else f"{int(val)} B"
        val /= 1024.0
    return f"{val:.1f} PB"

def _io_state_path():
    base = os.environ.get("XDG_RUNTIME_DIR") or "/tmp"
    return os.path.join(base, f"rclone-panel-io-{os.getuid()}.json")

def read_proc_io(pid):
    """Cumulative syscall byte counters for a pid, or None if unreadable
    (process gone, or owned by another user / more privileged)."""
    try:
        data = {}
        with open(f"/proc/{int(pid)}/io", "r", encoding="utf-8") as fh:
            for line in fh:
                if ":" in line:
                    key, val = line.split(":", 1)
                    data[key.strip()] = int(val.strip())
        return data
    except (OSError, ValueError):
        return None

def compute_speeds(processes):
    """Annotate each process with speed_bps / speed_formatted from the delta of
    rchar+wchar in /proc/<pid>/io between polls. A network transfer moves each
    byte through one read syscall and one write syscall, so half the summed
    delta approximates wire throughput. Previous samples live in a per-uid file
    in the runtime dir; dead pids fall out because only live pids are rewritten.
    """
    now = time.time()
    path = _io_state_path()

    prev = {}
    try:
        with open(path, "r", encoding="utf-8") as fh:
            loaded = json.load(fh)
            if isinstance(loaded, dict):
                prev = loaded
    except (OSError, ValueError):
        prev = {}

    new_state = {}
    for proc in processes:
        proc["speed_bps"] = 0
        proc["speed_formatted"] = "—"

        io = read_proc_io(proc.get("pid"))
        if not io:
            continue

        total = io.get("rchar", 0) + io.get("wchar", 0)
        key = str(proc.get("pid"))
        new_state[key] = {"t": now, "bytes": total}

        old = prev.get(key)
        if not old:
            continue
        dt = now - float(old.get("t", now))
        db = total - int(old.get("bytes", total))
        if dt > 0 and db > 0:
            bps = (db / dt) / 2.0
            proc["speed_bps"] = int(bps)
            proc["speed_formatted"] = parse_size(bps) + "/s"

    try:
        tmp = f"{path}.{os.getpid()}.tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(new_state, fh)
        os.replace(tmp, path)
    except OSError:
        pass

    return processes

def get_running_processes():
    processes = []
    ps_out = safe_run(["ps", "-eo", "pid,user,etime,%cpu,%mem,args", "--sort=-etime"], timeout=3)
    if not ps_out:
        return processes

    lines = ps_out.splitlines()
    if len(lines) <= 1:
        return processes

    for line in lines[1:]:
        parts = line.strip().split(None, 5)
        if len(parts) < 6:
            continue
        pid_str, user, etime, cpu, mem, cmd = parts
        
        if "rclone" not in cmd:
            continue
        if "status.py" in cmd or "grep" in cmd or "action.py" in cmd:
            continue

        cmd_tokens = cmd.split()
        rclone_idx = -1
        for i, token in enumerate(cmd_tokens):
            if token.endswith("rclone") or token == "rclone":
                rclone_idx = i
                break
        
        if rclone_idx == -1:
            continue

        args_after = cmd_tokens[rclone_idx + 1:]
        non_flag_args = [a for a in args_after if not a.startswith("-")]
        
        operation = "sync"
        source = ""
        destination = ""
        
        if non_flag_args:
            op_candidate = non_flag_args[0]
            if op_candidate in ["sync", "bisync", "copy", "move", "mount", "check", "delete", "cleanup"]:
                operation = op_candidate
                if len(non_flag_args) >= 3:
                    source = non_flag_args[1]
                    destination = non_flag_args[2]
                elif len(non_flag_args) == 2:
                    if operation == "mount":
                        source = non_flag_args[1]
                        destination = non_flag_args[2] if len(non_flag_args) > 2 else ""
                    else:
                        source = non_flag_args[1]
            elif op_candidate == "rcd":
                operation = "daemon"

        # Sanitize flags
        flags = [a for a in args_after if a.startswith("-") and not any(k in a.lower() for k in ["pass", "token", "key", "secret"])]

        processes.append({
            "pid": int(pid_str) if pid_str.isdigit() else pid_str,
            "user": user,
            "elapsed": etime,
            "cpu": cpu,
            "memory": mem,
            "operation": operation,
            "is_transfer": operation in TRANSFER_OPS,
            "source": source,
            "destination": destination,
            "flags": " ".join(flags[:4]),
            "command_preview": (operation.upper() + ": " + source + " → " + destination).strip() if (source or destination) else operation.upper()
        })
    return processes

def get_configured_remotes():
    remotes = []
    if not shutil.which("rclone"):
        return remotes

    out = safe_run(["rclone", "listremotes", "--long"], timeout=4)
    if not out:
        return remotes

    for line in out.splitlines():
        line = line.strip()
        if not line:
            continue
        parts = line.split(None, 1)
        name = parts[0].rstrip(":")
        rtype = parts[1] if len(parts) > 1 else "generic"

        provider_name = rtype.capitalize()
        icon = "󰅟"
        rtype_lower = rtype.lower()
        if "drive" in rtype_lower:
            icon = "󰊭"
            provider_name = "Google Drive"
        elif "dropbox" in rtype_lower:
            icon = "󰇮"
            provider_name = "Dropbox"
        elif "onedrive" in rtype_lower:
            icon = "󰏊"
            provider_name = "OneDrive"
        elif "s3" in rtype_lower:
            icon = "󰸏"
            provider_name = "Amazon S3"
        elif "sftp" in rtype_lower or "ftp" in rtype_lower:
            icon = "󰒋"
            provider_name = "SFTP/Server"
        elif "box" in rtype_lower:
            icon = "󰌨"
            provider_name = "Box"
        elif "pcloud" in rtype_lower:
            icon = "󰉍"
            provider_name = "pCloud"
        elif "webdav" in rtype_lower:
            icon = "󰖟"
            provider_name = "WebDAV"

        about_data = None
        about_out = safe_run(["rclone", "about", f"{name}:", "--json"], timeout=4)
        if about_out:
            try:
                about_data = json.loads(about_out)
            except Exception:
                about_data = None

        total_bytes = about_data.get("total") if about_data else None
        used_bytes = about_data.get("used") if about_data else None
        free_bytes = about_data.get("free") if about_data else None
        trash_bytes = about_data.get("trashed") if about_data else None

        used_percent = 0.0
        if total_bytes and used_bytes and total_bytes > 0:
            used_percent = round((float(used_bytes) / float(total_bytes)) * 100.0, 1)

        remotes.append({
            "name": name,
            "type": rtype,
            "provider": provider_name,
            "icon": icon,
            "has_quota": about_data is not None,
            "total_bytes": total_bytes,
            "total_formatted": parse_size(total_bytes),
            "used_bytes": used_bytes,
            "used_formatted": parse_size(used_bytes),
            "free_bytes": free_bytes,
            "free_formatted": parse_size(free_bytes),
            "trash_bytes": trash_bytes,
            "trash_formatted": parse_size(trash_bytes) if trash_bytes else "0 B",
            "used_percent": used_percent
        })
    return remotes

def get_fuse_mounts():
    mounts = []
    out = safe_run(["findmnt", "-t", "fuse.rclone", "-o", "TARGET,SOURCE,FSTYPE,OPTIONS", "-J"], timeout=3)
    if not out:
        return mounts
    try:
        data = json.loads(out)
        fs_list = data.get("filesystems", [])
        for fs in fs_list:
            target = fs.get("target", "")
            source = fs.get("source", "")
            options = fs.get("options", "")
            remote = source.split(":")[0] if ":" in source else source
            mounts.append({
                "target": target,
                "source": source,
                "remote": remote,
                "options": options,
                "active": True
            })
    except Exception:
        pass
    return mounts

# systemd's JSON output uses UINT64_MAX (and occasionally INT64_MAX) as an
# "unset" sentinel for timer next/last fields rather than 0 or null. Treat any
# absurdly large value as "no timestamp" so it never becomes a bogus timer far
# in the future.
_USEC_SENTINELS = (2 ** 64 - 1, 2 ** 63 - 1)
_MAX_PLAUSIBLE_USEC = 4102444800 * 1000000  # year 2100 in microseconds


def sanitize_usec(value):
    try:
        v = int(value)
    except (ValueError, TypeError):
        return 0
    if v <= 0 or v in _USEC_SENTINELS or v > _MAX_PLAUSIBLE_USEC:
        return 0
    return v


def format_relative_time(epoch_us, now_s):
    if not epoch_us or epoch_us <= 0:
        return "N/A"
    epoch_s = float(epoch_us) / 1000000.0
    diff = epoch_s - now_s
    
    if abs(diff) < 60:
        return "just now" if diff < 0 else "in <1m"
    
    past = diff < 0
    diff = abs(diff)
    
    minutes = int(diff // 60)
    hours = int(diff // 3600)
    days = int(diff // 86400)
    
    if days > 0:
        text = f"{days}d {hours % 24}h"
    elif hours > 0:
        text = f"{hours}h {minutes % 60}m"
    else:
        text = f"{minutes}m"
        
    return f"{text} ago" if past else f"in {text}"

def enrich_from_profile(profile_name):
    # Optional non-secret path enrichment if a profile file exists on the system
    home = os.path.expanduser("~")
    possible_paths = [
        os.path.join(home, ".config", "rclone-sync-profiles", f"{profile_name}.conf"),
        os.path.join(home, "dotfiles", ".config", "rclone-sync-profiles", f"{profile_name}.conf")
    ]
    for p in possible_paths:
        if os.path.isfile(p):
            try:
                local_path, remote, remote_path, sync_type, direction = "", "", "", "sync", ""
                with open(p, "r", encoding="utf-8") as f:
                    for line in f:
                        line = line.strip()
                        if line.startswith("LOCAL_PATH="):
                            local_path = line.split("=", 1)[1].strip("\"'")
                        elif line.startswith("REMOTE="):
                            remote = line.split("=", 1)[1].strip("\"'")
                        elif line.startswith("REMOTE_PATH="):
                            remote_path = line.split("=", 1)[1].strip("\"'")
                        elif line.startswith("SYNC_TYPE="):
                            sync_type = line.split("=", 1)[1].strip("\"'")
                        elif line.startswith("DIRECTION="):
                            direction = line.split("=", 1)[1].strip("\"'")
                
                full_remote = f"{remote}:{remote_path}" if remote else remote_path
                return {
                    "local_path": local_path,
                    "remote_path": full_remote,
                    "sync_type": sync_type,
                    "direction": direction
                }
            except Exception:
                pass
    return None

def get_scheduled_timers():
    timers_found = []
    now_s = time.time()
    
    for is_user in [False, True]:
        scope_flag = ["--user"] if is_user else []
        cmd = ["systemctl"] + scope_flag + ["list-timers", "--output=json"]
        out = safe_run(cmd, timeout=3)
        if not out:
            continue
            
        try:
            timer_entries = json.loads(out)
        except Exception:
            continue
            
        for t in timer_entries:
            unit = t.get("unit", "")
            activates = t.get("activates", "")
            if not unit or not activates:
                continue
                
            show_cmd = ["systemctl"] + scope_flag + ["show", activates, "--property=ExecStart,Description,ActiveState,SubState,Result"]
            show_out = safe_run(show_cmd, timeout=2)
            
            props = {}
            for line in show_out.splitlines():
                if "=" in line:
                    k, v = line.split("=", 1)
                    props[k.strip()] = v.strip()
                    
            exec_start = props.get("ExecStart", "")
            desc = props.get("Description", "")
            active_state = props.get("ActiveState", "inactive")
            sub_state = props.get("SubState", "dead")
            
            is_rclone = (
                "rclone" in unit.lower() or 
                "rclone" in activates.lower() or 
                "rclone" in exec_start.lower() or 
                "rclone" in desc.lower()
            )
            
            if not is_rclone:
                continue
                
            profile_name = ""
            if "@" in activates:
                match = re.search(r"@([^.]+)\.", activates)
                if match:
                    profile_name = match.group(1)

            local_path = ""
            remote_path = ""
            direction = ""
            sync_type = "sync"
            
            if "rclone" in exec_start:
                argv_match = re.search(r"argv\[\]=([^;]+)", exec_start)
                if argv_match:
                    argv_str = argv_match.group(1).strip()
                    tokens = argv_str.split()
                    non_flags = [x for x in tokens if not x.startswith("-") and x != "rclone" and not x.endswith("/rclone")]
                    if len(non_flags) >= 3:
                        sync_type = non_flags[0]
                        local_path = non_flags[1]
                        remote_path = non_flags[2]

            # Optional fallback enrichment if profile exists
            if profile_name and (not local_path or not remote_path):
                enriched = enrich_from_profile(profile_name)
                if enriched:
                    local_path = enriched.get("local_path", local_path)
                    remote_path = enriched.get("remote_path", remote_path)
                    sync_type = enriched.get("sync_type", sync_type)
                    direction = enriched.get("direction", direction)

            next_us = sanitize_usec(t.get("next", 0))
            last_us = sanitize_usec(t.get("last", 0))

            next_hour = -1.0
            if next_us and next_us > 0:
                lt = time.localtime(float(next_us) / 1000000.0)
                next_hour = round(lt.tm_hour + lt.tm_min / 60.0, 2)

            timers_found.append({
                "timer_unit": unit,
                "service_unit": activates,
                "profile": profile_name or unit.replace(".timer", ""),
                "description": desc or unit,
                "scope": "user" if is_user else "system",
                "active_state": active_state,
                "sub_state": sub_state,
                "is_running": active_state == "active" or sub_state == "running",
                "next_epoch_us": next_us,
                "next_formatted": format_relative_time(next_us, now_s),
                "next_hour": next_hour,
                "last_epoch_us": last_us,
                "last_formatted": format_relative_time(last_us, now_s),
                "local_path": local_path,
                "remote_path": remote_path,
                "direction": direction,
                "sync_type": sync_type
            })

    # Also scan crontab for rclone entries
    crontab_out = safe_run(["crontab", "-l"], timeout=2)
    if crontab_out:
        for line in crontab_out.splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "rclone" not in line:
                continue
            parts = line.split(None, 5)
            if len(parts) >= 6:
                schedule = " ".join(parts[:5])
                cmd = parts[5]
                timers_found.append({
                    "timer_unit": f"cron: {schedule}",
                    "service_unit": "crontab",
                    "profile": "cron-rclone",
                    "description": f"Cron: {cmd[:40]}...",
                    "scope": "cron",
                    "active_state": "active",
                    "sub_state": "cron",
                    "is_running": False,
                    "next_epoch_us": 0,
                    "next_formatted": schedule,
                    "next_hour": -1.0,
                    "last_epoch_us": 0,
                    "last_formatted": "N/A",
                    "local_path": "",
                    "remote_path": "",
                    "direction": "",
                    "sync_type": "cron"
                })

    timers_found.sort(key=lambda x: x["next_epoch_us"] if x["next_epoch_us"] > 0 else float("inf"))
    return timers_found

def get_sync_history():
    history = []
    out = safe_run(["journalctl", "-u", "rclone-sync@*", "-n", "40", "--no-pager"], timeout=3)
    if not out:
        return history
    
    lines = out.splitlines()
    seen = set()
    for line in lines:
        if "Deactivated successfully" in line or "Finished Rclone Sync Service" in line:
            m = re.search(r"rclone-sync@([^.]+)\.service", line)
            time_str = " ".join(line.split()[:3])
            profile = m.group(1) if m else "sync"
            key = f"{time_str}_{profile}_success"
            if key not in seen:
                seen.add(key)
                history.append({
                    "time": time_str,
                    "profile": profile,
                    "status": "success",
                    "message": "Completed successfully"
                })
        elif "Failed with result" in line or "failed" in line.lower():
            m = re.search(r"rclone-sync@([^.]+)\.service", line)
            time_str = " ".join(line.split()[:3])
            profile = m.group(1) if m else "sync"
            key = f"{time_str}_{profile}_error"
            if key not in seen:
                seen.add(key)
                history.append({
                    "time": time_str,
                    "profile": profile,
                    "status": "error",
                    "message": line.split(":", 1)[-1].strip() if ":" in line else line
                })
    return history[-12:]

def main():
    has_rclone = shutil.which("rclone") is not None
    processes = compute_speeds(get_running_processes())
    remotes = get_configured_remotes()
    mounts = get_fuse_mounts()
    timers = get_scheduled_timers()
    history = get_sync_history()
    
    next_timer = None
    for t in timers:
        if t.get("next_epoch_us", 0) > 0:
            next_timer = t
            break

    transfers = [p for p in processes if p.get("is_transfer")]
    is_sync_running = len(transfers) > 0
    
    payload = {
        "installed": has_rclone,
        "is_sync_running": is_sync_running,
        "active_processes_count": len(processes),
        "total_speed_bps": sum(int(p.get("speed_bps", 0)) for p in transfers),
        "processes": processes,
        "remotes_count": len(remotes),
        "remotes": remotes,
        "mounts_count": len(mounts),
        "mounts": mounts,
        "timers_count": len(timers),
        "timers": timers,
        "next_timer": next_timer,
        "history": history,
        "timestamp": int(time.time())
    }
    
    print(json.dumps(payload))

if __name__ == "__main__":
    main()
