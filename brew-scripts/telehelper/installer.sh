#!/bin/bash

# ================================================================
# 1. Check if Teleport is installed. Install if not
# ================================================================
function _ensure_teleport_installed {
  if ! command -v tsh >/dev/null 2>&1; then
    echo "Teleport (tsh) is not installed."
    echo "Attempting to install Teleport using Homebrew..."

    if command -v brew >/dev/null 2>&1; then
      brew install teleport

      # Verify installation
      if command -v tsh >/dev/null 2>&1; then
	echo "Teleport installed successfully."
      else
	echo "Teleport installation failed. Please install it manually."
      fi
    else
      echo "Homebrew is not installed. Cannot install Teleport automatically."
      echo "Please install Homebrew first: https://brew.sh/"
    fi
  fi
}

# Run the check
_ensure_teleport_installed

# ================================================================
# 2. Install helper script
# ================================================================

# Detect brew prefix properly
brew_prefix=$(brew --prefix 2>/dev/null || echo "/usr/local")

# Define install location
install_location="$brew_prefix/share/telehelper"
helper_script="$install_location/telehelper-functions.sh"

# Create the install directory if it doesn't exist
if [ ! -d "$install_location" ]; then
    mkdir -p "$install_location"
    echo "Created directory: $install_location"
fi

# Copy helper script
cp telehelper-functions.sh "$helper_script"
echo "Installed telehelper.sh to $helper_script"

# ================================================================
# 3. Add source command to shell profile
# ================================================================

# Detect the current shell
shell_name=$(basename "$SHELL")

if [ "$shell_name" = "zsh" ]; then
    shell_profile="$HOME/.zshrc"
elif [ "$shell_name" = "bash" ]; then
    shell_profile="$HOME/.bashrc"
else
    shell_profile="$HOME/.profile"
fi

line_to_add="source $helper_script"

# Only add if not already present
if ! grep -Fxq "$line_to_add" "$shell_profile"; then
    echo "$line_to_add" >> "$shell_profile"
    echo "Added source line to $shell_profile"
else
    echo "Source line already exists in $shell_profile"
fi

# Optional: reload shell profile immediately
source "$shell_profile"

echo "Setup complete!"
