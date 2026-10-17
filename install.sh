#!/bin/sh
# Builds owe-autostop and starts it with launchd at each login.
set -eu

label="io.github.ayush-gzip.owe-autostop"
dir="$HOME/.local/share/owe-autostop"
plist="$HOME/Library/LaunchAgents/$label.plist"
log="$HOME/Library/Logs/owe-autostop.log"

mkdir -p "$dir" "$HOME/Library/LaunchAgents"
swiftc -O "$(dirname "$0")/owe-autostop.swift" -o "$dir/owe-autostop"

cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
        <string>$dir/owe-autostop</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>$log</string>
    <key>StandardErrorPath</key>
    <string>$log</string>
</dict>
</plist>
EOF

launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$plist"
echo "owe-autostop is running. Log: $log"
