#!/usr/bin/env python3
import os
import shutil
import subprocess
import sys

def main():
    if len(sys.argv) < 2:
        print("Usage: action.py <command> [args...]", file=sys.stderr)
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "sync":
        # Argument can be a systemd service or profile name
        target = sys.argv[2] if len(sys.argv) > 2 else ""
        if not target:
            sys.exit(1)

        # 1. Try systemd service if it has @ or ends in .service
        service_name = target if target.endswith(".service") else f"rclone-sync@{target}.service"
        res = subprocess.run(["systemctl", "start", service_name], check=False)
        if res.returncode == 0:
            print(f"Triggered systemd unit {service_name}")
            sys.exit(0)

        # 2. Try user systemd service
        res_user = subprocess.run(["systemctl", "--user", "start", service_name], check=False)
        if res_user.returncode == 0:
            print(f"Triggered user systemd unit {service_name}")
            sys.exit(0)

        # 3. Fallback to rclone-sync.sh script if available
        script_path = os.path.expanduser("~/workspace/services/rclone-sync.sh")
        if not os.path.isfile(script_path):
            script_path = "/usr/local/bin/rclone-sync.sh"
        
        if os.path.isfile(script_path):
            subprocess.Popen(["bash", script_path, target.replace("rclone-sync@", "").replace(".service", "")])
            print(f"Started {script_path} {target}")
            sys.exit(0)

    elif cmd == "unmount":
        target_dir = sys.argv[2] if len(sys.argv) > 2 else ""
        if target_dir and os.path.isdir(target_dir):
            res = subprocess.run(["fusermount", "-u", target_dir], check=False)
            if res.returncode == 0:
                print(f"Unmounted {target_dir}")
                sys.exit(0)
            else:
                subprocess.run(["umount", target_dir], check=False)

    elif cmd == "open_folder":
        folder = sys.argv[2] if len(sys.argv) > 2 else ""
        if folder and os.path.isdir(os.path.expanduser(folder)):
            subprocess.Popen(["xdg-open", os.path.expanduser(folder)])

if __name__ == "__main__":
    main()
