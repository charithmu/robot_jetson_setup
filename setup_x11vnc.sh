#!/bin/bash

# ----------------------------
# X11VNC Autostart Setup Script (Jetson-safe)
# Works on freshly installed Jetson with autologin and HDMI
# Usage: ./setup-x11vnc-autostart.sh [optional_password]
# ----------------------------

set -e

# Get optional password from argument, or default to 'dronevnc'
VNC_PASS="${1:-dronevnc}"

echo "🔧 Installing x11vnc..."
sudo apt update
sudo apt install -y x11vnc

# Ensure ~/.vnc exists and set the password
echo "🔐 Configuring VNC password..."
mkdir -p "$HOME/.vnc"
x11vnc -storepasswd "$VNC_PASS" "$HOME/.vnc/passwd"
chmod 600 "$HOME/.vnc/passwd"

# Create a reliable launcher script
echo "🛠️ Creating x11vnc startup script..."
mkdir -p "$HOME/bin"
cat << 'EOF' > "$HOME/bin/start-x11vnc.sh"
#!/bin/bash

# Wait for X display :0 (requires HDMI connected + GUI session)
MAX_WAIT=60
COUNT=0
while ! xdpyinfo -display :0 >/dev/null 2>&1; do
  echo "⏳ Waiting for X display :0 to become available..."
  sleep 2
  COUNT=$((COUNT+2))
  if [ "$COUNT" -ge "$MAX_WAIT" ]; then
    echo "❌ Timeout waiting for X display :0"
    exit 1
  fi
done

# Start x11vnc
echo "🚀 Starting x11vnc on :0"
exec /usr/bin/x11vnc \
  -auth guess \
  -forever \
  -loop \
  -noxdamage \
  -repeat \
  -rfbauth "$HOME/.vnc/passwd" \
  -rfbport 5900 \
  -shared \
  -display :0 \
  -ncache 10 \
  -ncache_cr
EOF

chmod +x "$HOME/bin/start-x11vnc.sh"

# Create the user systemd service
echo "📦 Creating systemd user service..."
mkdir -p "$HOME/.config/systemd/user"
cat << EOF > "$HOME/.config/systemd/user/x11vnc.service"
[Unit]
Description=Start x11vnc on user login and HDMI availability
After=graphical-session.target

[Service]
Type=simple
ExecStart=%h/bin/start-x11vnc.sh
Restart=on-failure

[Install]
WantedBy=default.target
EOF

# Enable and start the service
echo "🔁 Enabling systemd user service..."
systemctl --user daemon-reexec
systemctl --user daemon-reload
systemctl --user enable x11vnc.service
systemctl --user start x11vnc.service

# Enable user lingering to support auto-login systems
echo "🔓 Enabling lingering for $USER..."
sudo loginctl enable-linger "$USER"

echo "✅ All done!"
echo "   VNC server will auto-start after login and HDMI is active."
echo "   Connect via <jetson-ip>:5900 using password: '$VNC_PASS'"
