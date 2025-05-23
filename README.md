# Robot Jetson Setup Script

Automated installation and configuration script for essential packages, tools, and environment settings for robotics development on NVIDIA Jetson devices.

## Features

- **Dry-run mode** for testing before execution
- **Step-by-step progress tracking** with resume capability
- **Automatic reboot handling** for system updates
- **Comprehensive error management** and logging
- **Optimized installation order** for efficiency

## Quick Start

```bash
# Clone and make executable
git clone https://github.com/charithmu/robot_jetson_setup.git
cd robot_jetson_setup
chmod +x robot_jetson_setup.sh

# Test with dry-run (recommended first)
./robot_jetson_setup.sh --dry-run

# Run the setup
./robot_jetson_setup.sh
```

## What Gets Installed

- **System Updates** - Latest packages and security updates
- **NVIDIA JetPack** - GPU development toolkit
- **Development Tools** - build-essential, cmake, git, python3
- **System Utilities** - terminator, htop, tmux, nano, and more
- **Docker + NVIDIA Runtime** - Container platform with GPU support
- **Git Configuration** - Modern defaults and helpful aliases
- **Development Workspace** - ~/dev directory setup
- **CUDA Environment** - Proper PATH and library configurations

## Usage

| Command | Description |
|---------|-------------|
| `./robot_jetson_setup.sh` | Normal execution |
| `./robot_jetson_setup.sh --dry-run` | Preview what would be executed |

The script automatically resumes from the last completed step if interrupted.

## Author

**Charith Munasinghe** (munge@zhaw.ch)

---

*Optimized for NVIDIA Jetson devices running Ubuntu-based distributions*
