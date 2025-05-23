#!/usr/bin/env bash
#=============================================================================
# Robot Jetson Setup Script
#=============================================================================
# Author: Charith Munasinghe (munge@zhaw.ch)
# Description: Automated installation and configuration script for essential 
#              packages, tools, and environment settings for robotics 
#              development on NVIDIA Jetson devices.
# 
# Usage:
#   ./robot_jetson_setup.sh          # Normal execution
#   ./robot_jetson_setup.sh --dry-run # Preview what would be executed
#
# Features:
#   - Dry-run functionality for testing
#   - Step-by-step execution with progress tracking
#   - Automatic reboot handling for system updates
#   - Comprehensive error management and logging
#   - Optimized step ordering for efficient setup
#   - Resume capability after interruption or reboot
#
# Steps performed:
#   1. Update system packages
#   2. Install NVIDIA JetPack (requires reboot)
#   3. Install development tools (build-essential, cmake, git, python3)
#   4. Install system utilities (terminator, htop, tmux, nano, etc.)
#   5. Install jetson-stats for system monitoring
#   6. Setup Docker with NVIDIA runtime as default
#   7. Configure Git with modern defaults and user credentials
#   8. Create development workspace directory
#   9. Remove unnecessary packages (games, LibreOffice, Thunderbird)
#   10. Configure bash environment with CUDA paths and aliases
#=============================================================================

set -e  # Exit immediately if a command exits with a non-zero status

#=============================================================================
# COMMAND LINE ARGUMENT PARSING
#=============================================================================

# Parse command line arguments
DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            shift # Remove --dry-run from processing
            ;;
        *)
            # Unknown option - silently ignore for now
            ;;
    esac
done

#=============================================================================
# PRIVILEGE AND SETUP VALIDATION
#=============================================================================

# Check if running with sudo privileges (skip for dry run)
if [ "$DRY_RUN" = false ] && [ "$(id -u)" -ne 0 ]; then
    echo "This script requires sudo privileges for some operations."
    echo "Running with sudo..."
    sudo "$0" "$@"
    exit $?
fi

#=============================================================================
# STEP TRACKING SYSTEM
#=============================================================================

# Get the script's directory for storing progress marker file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STEP_FILE="${SCRIPT_DIR}/.robot_setup_progress"

# Create and check step tracking file
if [ ! -f "$STEP_FILE" ]; then
    echo "0" > "$STEP_FILE"
    chmod 666 "$STEP_FILE"  # Ensure the file is writable for future runs
fi
CURRENT_STEP=$(cat "$STEP_FILE")

#=============================================================================
# UTILITY FUNCTIONS
#=============================================================================

# Function to execute a step and update step counter with proper error handling
# Parameters:
#   $1: step_num - The step number for tracking progress
#   $2: step_desc - Human-readable description of the step
#   $3: cmd - The command(s) to execute for this step
#   $4: reboot_required (optional) - Set to "true" if step requires reboot
execute_step() {
    local step_num=$1
    local step_desc=$2
    local cmd=$3
    local reboot_required=${4:-false}  # Optional 4th parameter, defaults to false
    
    # Only execute steps that haven't been completed yet
    if [ "$CURRENT_STEP" -lt "$step_num" ]; then
        echo -e "\n\033[1;32m=== Step $step_num: $step_desc ===\033[0m"
        echo "Command: $cmd"
        echo "-------------------------------------"
        
                # In dry run mode, just show the command but don't execute it
        if [ "$DRY_RUN" = true ]; then
            echo -e "\033[1;33m[DRY RUN] Would execute the command above\033[0m"
            local result=0
        else
            # Execute command and capture result
            set +e  # Temporarily disable exit on error to handle it gracefully
            eval $cmd
            local result=$?
            set -e  # Re-enable exit on error
        fi
        
        # Handle step completion or failure
        if [ $result -eq 0 ]; then
            if [ "$DRY_RUN" = true ]; then
                echo -e "\033[1;33m[DRY RUN] Step $step_num would be marked as completed\033[0m"
            else
                echo -e "\033[1;32mStep $step_num completed successfully\033[0m"
                echo "$step_num" > "$STEP_FILE"
                CURRENT_STEP=$step_num
            fi
            
            # Handle reboot requirement if specified
            if [ "$reboot_required" = true ] && [ "$DRY_RUN" = false ]; then
                echo -e "\n\033[1;33mStep $step_num requires a system reboot.\033[0m"
                read -p "Would you like to reboot now? (y/N) " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]]; then
                    echo "Rebooting system..."
                    sudo reboot
                else
                    echo -e "\033[1;33mPlease remember to reboot before continuing to step $((step_num+1)).\033[0m"
                    exit 0
                fi
            elif [ "$reboot_required" = true ] && [ "$DRY_RUN" = true ]; then
                echo -e "\n\033[1;33m[DRY RUN] This step would require a reboot\033[0m"
            fi
        else
            echo -e "\033[1;31mStep $step_num failed with exit code $result\033[0m"
            exit $result
        fi
    else
        # Step already completed - skip execution
        echo -e "\033[1;34mStep $step_num: $step_desc (Already Completed)\033[0m"
    fi
}

#=============================================================================
# MAIN SETUP STEPS - Optimally ordered for efficient installation
#=============================================================================

# Step 1: Update package lists and upgrade all packages (foundation step)
execute_step 1 \
"Updating system packages" \
"sudo apt update && sudo apt upgrade -y"

# Step 2: Install NVIDIA JetPack meta-package (requires reboot)
execute_step 2 \
"Installing NVIDIA JetPack" \
"sudo apt install -y nvidia-jetpack" true  # requires reboot

# Step 3: Install common development tools and utilities
execute_step 3 \
"Installing development tools" \
"sudo apt install -y build-essential cmake git python3-pip python3-dev curl wget unzip"

# Step 4: Install system management and network tools
execute_step 4 \
"Installing system utilities" \
"sudo apt install -y \\
    terminator \\
    net-tools \\
    nmap \\
    htop \\
    iotop \\
    iftop \\
    ncdu \\
    tmux \\
    tree \\
    mlocate \\
    nano"

# Step 5: Install jetson-stats for system monitoring
execute_step 5 \
"Installing jetson-stats" \
"sudo pip3 install -U jetson-stats"

# Step 6: Install and configure Docker with NVIDIA runtime as default
execute_step 6 \
"Setting up Docker and Docker Compose with NVIDIA runtime" \
"sudo apt install -y docker.io docker-compose-v2 && \
sudo groupadd -f docker && \
sudo usermod -aG docker \$USER && \
sudo mkdir -p /etc/docker && \
echo '{
    \"runtimes\": {
        \"nvidia\": {
            \"path\": \"nvidia-container-runtime\",
            \"runtimeArgs\": []
        }
    },
    \"default-runtime\": \"nvidia\"
}' | sudo tee /etc/docker/daemon.json > /dev/null && \
sudo systemctl restart docker && \
newgrp docker"

# Step 7: Configure Git with helpful defaults and user credentials
execute_step 7 \
"Configuring Git" \
"read -p 'Enter your Git name: ' gitname && \
read -p 'Enter your Git email: ' gitemail && \
git config --global user.name \"\$gitname\" && \
git config --global user.email \"\$gitemail\" && \
git config --global init.defaultBranch main && \
git config --global color.ui auto && \
git config --global pull.rebase true && \
git config --global push.default simple && \
git config --global core.editor 'nano' && \
git config --global alias.lg 'log --oneline --graph --all --decorate' && \
git config --global credential.helper 'cache --timeout=3600' && \
echo 'Git configuration complete.'"

# Step 8: Remove unnecessary packages to free up space
execute_step 8 \
"Removing unnecessary packages" \
"sudo apt purge -y aisleriot gnome-mahjongg gnome-mines gnome-sudoku thunderbird-* libreoffice-* && \
sudo apt autoremove -y"

# Step 9: Create development workspace directory
execute_step 9 \
"Creating development workspace" \
"mkdir -p ~/dev && \
cd ~/dev && \
echo 'Created development workspace at ~/dev'"

# Step 10: Configure bash environment with CUDA paths and useful aliases
execute_step 10 \
"Configuring bash environment" \
"echo '# Added by robot_jetson_setup.sh

# CUDA environment paths
export PATH=/usr/local/cuda/bin:\$PATH
export LD_LIBRARY_PATH=/usr/local/cuda/lib64:\$LD_LIBRARY_PATH

# Useful aliases for robotics development
alias cc=\"clear\"
alias lx=\"ls -aX1C\"

# Start in development workspace
cd ~/dev

' >> ~/.bashrc && \
source ~/.bashrc && \
echo 'Bash environment configured.'"

#=============================================================================
# COMPLETION MESSAGE
#=============================================================================

echo -e "\n\033[1;32m✓ All steps completed successfully!\033[0m"
echo ""
echo "Setup includes:"
echo "  • Updated system packages and removed unnecessary software"
echo "  • Development tools (build-essential, cmake, git, python3)"
echo "  • System utilities (terminator, htop, tmux, nano, etc.)"
echo "  • Configured Git with modern defaults and aliases"
echo "  • Created ~/dev development workspace"
echo "  • Configured bash environment with CUDA paths and aliases"
echo "  • Installed jetson-stats for system monitoring"
echo "  • Installed NVIDIA JetPack for GPU development"
echo "  • Configured Docker with NVIDIA runtime as default"
echo ""
echo -e "\033[1;36mYour Jetson device is now configured for robotics development.\033[0m"
echo ""
echo -e "\033[1;34mScript by: Charith Munasinghe (munge@zhaw.ch)\033[0m"
echo ""
