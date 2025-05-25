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
#   ./robot_jetson_setup.sh               # Normal execution
#   ./robot_jetson_setup.sh --dry-run     # Preview what would be executed
#   ./robot_jetson_setup.sh --skip:N      # Skip steps up to and including step N
#   ./robot_jetson_setup.sh --steps       # Show all steps and exit
#
# Features:
#   - Dry-run functionality for testing
#   - Step-by-step execution with progress tracking
#   - Skip functionality to start from specific steps
#   - Show steps functionality to list all steps
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
#   8. Remove unnecessary packages (games, LibreOffice, Thunderbird)
#   9. Create development workspace directory
#   10. Configure bash environment with CUDA paths and aliases
#   11. Apply bash environment changes immediately
#=============================================================================

set -e  # Exit immediately if a command exits with a non-zero status

#=============================================================================
# COMMAND LINE ARGUMENT PARSING
#=============================================================================

# Parse command line arguments
DRY_RUN=false
SKIP_UNTIL=0
SHOW_STEPS=false

for arg in "$@"; do
    case $arg in
        --dry-run)
            DRY_RUN=true
            ;;
        --skip:*)
            SKIP_UNTIL="${arg#*:}"
            ;;
        --steps)
            SHOW_STEPS=true
            ;;
        *)
            # Unknown option - silently ignore for now
            ;;
    esac
done

# Function to show all steps and exit
show_steps() {
    echo "Robot Jetson Setup Script - Steps:"
    echo "1. Update system packages"
    echo "2. Install NVIDIA JetPack (requires reboot)"
    echo "3. Install development tools (build-essential, cmake, git, python3)"
    echo "4. Install system utilities (terminator, htop, tmux, nano, etc.)"
    echo "5. Install jetson-stats for system monitoring"
    echo "6. Setup Docker with NVIDIA runtime as default"
    echo "7. Configure Git with modern defaults and user credentials"
    echo "8. Remove unnecessary packages (games, LibreOffice, Thunderbird)"
    echo "9. Create development workspace directory"
    echo "10. Configure bash environment with CUDA paths and aliases"
    echo "11. Apply bash environment changes immediately"
    exit 0
}

# Show steps if requested
if [ "$SHOW_STEPS" = true ]; then
    show_steps
fi

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

# Validate that SUDO_USER is set when running as root (except in dry run)
if [ "$DRY_RUN" = false ] && [ "$(id -u)" -eq 0 ] && [ -z "$SUDO_USER" ]; then
    echo -e "\033[1;31mError: This script must be run with sudo, not as root directly.\033[0m"
    echo "Please run: sudo $0 $*"
    exit 1
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

# Handle skip functionality
if [ "$SKIP_UNTIL" != "0" ]; then
    # Check if SKIP_UNTIL is a valid number
    if ! [[ "$SKIP_UNTIL" =~ ^[0-9]+$ ]]; then
        echo -e "\033[1;31mError: --skip parameter must be a number\033[0m"
        exit 1
    fi
    
    # Validate skip parameter is a valid step number (1-11)
    if [ "$SKIP_UNTIL" -lt 1 ] || [ "$SKIP_UNTIL" -gt 11 ]; then
        echo -e "\033[1;31mError: --skip parameter must be between 1 and 11\033[0m"
        exit 1
    fi
    
    if [ "$SKIP_UNTIL" -gt "$CURRENT_STEP" ]; then
        echo -e "\033[1;33mSkipping steps up to and including step $SKIP_UNTIL\033[0m"
        echo "$SKIP_UNTIL" > "$STEP_FILE"
        CURRENT_STEP=$SKIP_UNTIL
    else
        echo -e "\033[1;33mStep $SKIP_UNTIL has already been completed or passed. Current step: $CURRENT_STEP\033[0m"
    fi
fi

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
            eval "$cmd"
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
"sudo apt install -y terminator net-tools nmap htop iotop iftop ncdu tmux tree mlocate nano"

# Step 5: Install jetson-stats for system monitoring
execute_step 5 \
"Installing jetson-stats" \
"sudo pip3 install -U jetson-stats"

# Step 6: Install and configure Docker with NVIDIA runtime as default
execute_step 6 \
"Setting up Docker and Docker Compose with NVIDIA runtime" \
"sudo apt install -y docker.io docker-compose-v2 && \
sudo groupadd -f docker && \
sudo usermod -aG docker \$SUDO_USER && \
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
sudo systemctl enable docker && \
sudo systemctl restart docker && \
sudo systemctl --no-pager status docker"

# Step 7: Configure Git with helpful defaults and user credentials
execute_step 7 \
"Configuring Git" \
"read -p 'Enter your Git name: ' gitname && \
read -p 'Enter your Git email: ' gitemail && \
sudo -u \$SUDO_USER git config --global user.name \"\$gitname\" && \
sudo -u \$SUDO_USER git config --global user.email \"\$gitemail\" && \
sudo -u \$SUDO_USER git config --global init.defaultBranch main && \
sudo -u \$SUDO_USER git config --global color.ui auto && \
sudo -u \$SUDO_USER git config --global pull.rebase true && \
sudo -u \$SUDO_USER git config --global push.default simple && \
sudo -u \$SUDO_USER git config --global core.editor 'nano' && \
sudo -u \$SUDO_USER git config --global alias.lg 'log --oneline --graph --all --decorate' && \
sudo -u \$SUDO_USER git config --global credential.helper 'cache --timeout=3600' && \
echo 'Git configuration complete.'"

# Step 8: Remove unnecessary packages to free up space
execute_step 8 \
"Removing unnecessary packages" \
"sudo apt purge -y aisleriot gnome-mahjongg gnome-mines gnome-sudoku thunderbird-* libreoffice-* && \
sudo apt autoremove -y"

# Step 9: Create development workspace directory
execute_step 9 \
"Creating development workspace" \
"mkdir -p /home/\$SUDO_USER/dev && chown \$SUDO_USER:\$SUDO_USER /home/\$SUDO_USER/dev && echo 'Created development workspace at /home/\$SUDO_USER/dev' && ls -la /home/\$SUDO_USER/dev"

# Step 10: Configure bash environment with CUDA paths and useful aliases
execute_step 10 \
"Configuring bash environment" \
"cat >> /home/\$SUDO_USER/.bashrc << \"EOL\"

#=============================================================================
# Robot Jetson Setup - Environment Configuration
#=============================================================================
# Added by robot_jetson_setup.sh on $(date)
 
# CUDA Environment Setup
export PATH=\"/usr/local/cuda/bin:\$PATH\"
export LD_LIBRARY_PATH=\"/usr/local/cuda/lib64:\$LD_LIBRARY_PATH\"

# Useful Aliases for Development
alias cc=\"clear\"                    # Quick clear command
alias lx=\"ls -aX1C\"                 # List files in columns, sorted by extension

# Auto-navigate to development workspace
if [ -d \"\$HOME/dev\" ]; then
    cd \"\$HOME/dev\" 2>/dev/null || true
fi
#=============================================================================
EOL
echo 'Bash environment configured.'"

# Step 11: Source the updated bashrc file to apply changes immediately
execute_step 11 \
"Applying bash environment changes" \
"sudo -u \$SUDO_USER bash -c '. /home/\$SUDO_USER/.bashrc' && echo 'Environment changes applied successfully.'"

#=============================================================================
# COMPLETION MESSAGE
#=============================================================================

echo -e "\n\033[1;32m✓ All steps completed successfully!\033[0m"
echo -e "\033[1;36mYour Jetson device is now configured for robotics development.\033[0m"
echo ""
echo -e "Note: Log out or restart before continue to apply configurations. (Docker group changes, etc.)"
echo ""
echo -e "\033[1;34mScript by: Charith Munasinghe (munge@zhaw.ch)\033[0m"
echo ""
echo -e "\033[1;32mSystem Information:\033[0m"
if command -v jetson_release >/dev/null 2>&1; then
    jetson_release
else
    echo "jetson_release command not available (install jetson-stats to see system info)"
fi

#=============================================================================
# END OF SCRIPT
#=============================================================================
# Note: This script is designed for NVIDIA Jetson devices and may not work
#       correctly on other systems. Always review and test scripts before
#       executing them, especially with sudo privileges.
#       Use at your own risk!!
#=============================================================================
