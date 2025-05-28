#!/bin/bash

# Check for root privileges
if [ "$(id -u)" != "0" ]; then
    echo "❌ This script must be run with sudo"
    exit 1
fi

# Configurations
DEFAULT_UART_DEV="ttyTCU0"
UART_DEV="${2:-$DEFAULT_UART_DEV}"  # Use second argument if provided, else use default
EXTLINUX_CONF="/boot/extlinux/extlinux.conf"
BACKUP_WITH_UART="$EXTLINUX_CONF.with_uart.bak"
BACKUP_WITHOUT_UART="$EXTLINUX_CONF.without_uart.bak"
UART_CONSOLE="console=$UART_DEV,115200n8"
MODE=$1


check_prerequisites() {
    if [ ! -f "$EXTLINUX_CONF" ]; then
        echo "❌ Error: $EXTLINUX_CONF not found"
        exit 1
    fi
}

check_uart_device() {
    if [ ! -c "/dev/$UART_DEV" ]; then
        echo "❌ Error: UART device /dev/$UART_DEV does not exist"
        echo "💡 Available UART devices:"
        ls -1 /dev/tty* | grep -E "ttyTHS|ttyTCU|ttyS" || echo "   No UART devices found"
        exit 1
    fi
}

create_initial_backups() {
    if [ ! -f "$BACKUP_WITH_UART" ] && grep -q "$UART_CONSOLE" "$EXTLINUX_CONF"; then
        sudo cp "$EXTLINUX_CONF" "$BACKUP_WITH_UART"
        echo "📑 Created backup with UART console"
    fi
    
    if [ ! -f "$BACKUP_WITHOUT_UART" ]; then
        sudo cp "$EXTLINUX_CONF" "$BACKUP_WITHOUT_UART"
        sudo sed -i "s/$UART_CONSOLE //" "$BACKUP_WITHOUT_UART"
        echo "📑 Created backup without UART console"
    fi
}

# Enable serial console
enable_console() {
  check_prerequisites
  echo "🟢 Enabling serial console on /dev/$UART_DEV"
  check_uart_device
    
  if [ -f "$BACKUP_WITH_UART" ]; then
    sudo cp "$BACKUP_WITH_UART" "$EXTLINUX_CONF"
  else
    create_initial_backups
    # Add console=ttyTCU0 if not present
    if ! grep -q "$UART_CONSOLE" "$EXTLINUX_CONF"; then
      sudo sed -i "s/APPEND /APPEND $UART_CONSOLE /" "$EXTLINUX_CONF"
    fi
  fi

  # Enable serial-getty
  sudo systemctl enable "serial-getty@$UART_DEV.service"
  sudo systemctl start "serial-getty@$UART_DEV.service"

  # Enable nvgetty if it exists
  if systemctl list-unit-files | grep -q nvgetty.service; then
    echo "✔ Enabling nvgetty.service"
    sudo systemctl enable nvgetty.service
    sudo systemctl start nvgetty.service
  fi

  echo "✅ Serial console enabled. Reboot to apply."
  return 0
}

# Disable serial console
disable_console() {
  check_prerequisites
  echo "🛑 Disabling serial console on /dev/$UART_DEV"
  check_uart_device
    
  if [ -f "$BACKUP_WITHOUT_UART" ]; then
    sudo cp "$BACKUP_WITHOUT_UART" "$EXTLINUX_CONF"
  else
    create_initial_backups
    sudo cp "$BACKUP_WITHOUT_UART" "$EXTLINUX_CONF"
  fi

  # Disable serial-getty
  sudo systemctl stop "serial-getty@$UART_DEV.service"
  sudo systemctl disable "serial-getty@$UART_DEV.service"

  # Disable nvgetty if it exists
  if systemctl list-unit-files | grep -q nvgetty.service; then
    echo "✔ Disabling nvgetty.service"
    sudo systemctl stop nvgetty.service
    sudo systemctl disable nvgetty.service
  fi

  echo "✅ Serial console disabled. Reboot to apply."
  return 0
}

# Check status of serial console
status() {
  check_prerequisites
  echo "🔍 Status for /dev/$UART_DEV"

  grep "$UART_CONSOLE" "$EXTLINUX_CONF" &> /dev/null && \
    echo " - Kernel console: ENABLED" || echo " - Kernel console: DISABLED"

  systemctl is-enabled "serial-getty@$UART_DEV.service" &> /dev/null && \
    echo " - serial-getty: ENABLED" || echo " - serial-getty: DISABLED"

  if systemctl list-unit-files | grep -q nvgetty.service; then
    systemctl is-enabled nvgetty.service &> /dev/null && \
      echo " - nvgetty.service: ENABLED" || echo " - nvgetty.service: DISABLED"
  else
    echo " - nvgetty.service: NOT INSTALLED"
  fi
  return 0
}

# Usage text
show_usage() {
  echo "Usage: $0 [enable|disable|status] [uart_device]"
  echo "  enable   - Enable UART console and boot logs"
  echo "  disable  - Disable UART console to use as raw serial"
  echo "  status   - Show current status of UART console"
  echo ""
  echo "Arguments:"
  echo "  uart_device - Optional: UART device to use (default: $DEFAULT_UART_DEV)"
  echo "                Example: $0 enable ttyTHS0"
}

# Check if the script is run with no arguments
if [ -n "$MODE" ] && [[ ! "$MODE" =~ ^(enable|disable|status)$ ]]; then
    echo "❌ Error: Invalid mode '$MODE'"
    show_usage
    exit 1
fi

# Run the requested mode
case "$MODE" in
  enable) enable_console ;;
  disable) disable_console ;;
  status) status ;;
  *) show_usage ;;
esac
