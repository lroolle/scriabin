#!/bin/bash

# Check if hysteria is installed
if ! command -v hysteria &> /dev/null; then
    echo "hysteria is not installed. Installing now..."
    bash <(curl -fsSL https://get.hy2.sh/)
    
    # Verify installation
    if ! command -v hysteria &> /dev/null; then
        echo "Failed to install hysteria. Please check your internet connection or install manually."
        exit 1
    fi
    echo "hysteria installed successfully."
fi

# Run hysteria check-update and capture both stdout and stderr
update_info=$(hysteria check-update 2>&1)

# Extract current version, new version, and urgency from the captured output
current_version=$(echo "$update_info" | grep -oP '"version": "\K[^"]*' | head -n 1)
new_version=$(echo "$update_info" | grep -oP '"version": "\K[^"]*' | tail -n 1)
urgent=$(echo "$update_info" | grep -oP '"urgent": \K(true|false)')

# Debugging: Print captured output for verification
echo "Captured update information:"
echo "$update_info"

# Check if an update is urgent
if [ "$urgent" == "true" ]; then
    echo "Urgent update available from $current_version to $new_version"

    # Backup the current hysteria binary
    backup_path="/usr/local/bin/hysteria.bak.$current_version"
    cp /usr/local/bin/hysteria "$backup_path"
    echo "Backup created at $backup_path"

    # Detect OS and architecture
    case "$(uname -s)" in
        Darwin*)
            os="darwin"
            ;;
        Linux*)
            os="linux"
            ;;
        *)
            echo "Unsupported operating system"
            exit 1
            ;;
    esac

    case "$(uname -m)" in
        x86_64|amd64)
            arch="amd64"
            ;;
        arm64|aarch64)
            arch="arm64"
            ;;
        *)
            echo "Unsupported architecture"
            exit 1
            ;;
    esac

    download_url="https://github.com/apernet/hysteria/releases/download/app%2F$new_version/hysteria-$os-$arch"
    temp_file="/tmp/hysteria-$new_version"

    wget -O "$temp_file" "$download_url"
    if [ $? -ne 0 ]; then
        echo "Failed to download the update. Please check your internet connection or the URL."
        exit 1
    fi
    echo "Downloaded hysteria version $new_version"

    # Make the binary executable
    chmod +x "$temp_file"

    # Move the new binary to /usr/local/bin
    mv "$temp_file" /usr/local/bin/hysteria
    echo "Updated hysteria to version $new_version"

    # Verify the update
    hysteria --version
else
    echo "No urgent update required."
fi
