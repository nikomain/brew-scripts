printf "Create a new homebrew formula"
printf "\n\n\033[1mName:\033[0m"
read name
printf "\n\033[1mDescription:\033[0m"
read desc

mkdir ./$name

# ================================
# 	     Script File	  
# ================================
touch ./$name/$name.sh
chmod +x $name/$name.sh

# ================================
# 	    Installer.sh 	  
# ================================
cat <<EOF > "$name/installer.sh"
#!/bin/bash
# Installer for $name

set -e

echo "🔧 Installing $name..."

# Install to /usr/local/bin (may require sudo)
install -m 755 script.sh /usr/local/bin/$name

echo "✅ Installed $name to /usr/local/bin"
EOF

chmod +x "$name/installer.sh"

# ================================
# 	  Formula Metadata
# ================================
cat <<EOF > "$name/formula.meta"
name = $name
desc = $desc
version = 1.0.0
license = homepage = https://github.com/nikomain/brew-scripts/$name
install = bin.install "installer.sh" => "$name-install"
caveats = |
  Thanks for installing \`$name\`!
  - Run \`$name --help\` to get started.
  - Documentation: https://github.com/nikomain/brew-scripts/$name

EOF

# Instructions here
printf "\n\033[1m===================== Usage ====================\033\n[0m"
printf "\n1. run cd $test"
printf "\n1. Create your script n shit"
printf "\n2. Update installer.sh with specific instructions."
printf "\n3. Update the formula.metadata file with your info"


