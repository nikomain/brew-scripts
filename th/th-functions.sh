# ===========================================================
# 		    Teleport CLI shortcuts
# ===========================================================
th(){
  echo "e rvlqerlk"
  th_login() {
    if tsh status 2>/dev/null | grep -q 'Logged in as:'; then
      echo "Already logged in to Teleport."
      return 0
    fi

    echo "Logging you into Teleport..."
    tsh login --auth=ad --proxy=youlend.teleport.sh:443

    # Wait until login completes (max 15 seconds)
    for i in {1..30}; do
      if tsh status 2>/dev/null | grep -q 'Logged in as:'; then
	echo "✅ Logged in to Teleport."
	return 0
      fi
      sleep 0.5
    done

    echo "❌ Timed out waiting for Teleport login."
    return 1
  }
  # Helper function to prompt user to switch roles once all proxies have been configured
  th_switch() {
    local available_roles=()
    local role_path name

    # Enable nullglob in Zsh so /tmp/* doesn't error when empty
    if [ -n "$ZSH_VERSION" ]; then
      setopt NULL_GLOB
      setopt KSH_ARRAYS
    fi

    # Collect role files from /tmp
    for role_path in /tmp/*; do
      # Skip logs
      [[ "$role_path" == *.log ]] && continue

      # Portable basename extraction
      name=$(basename "$role_path")

      # Match role prefix
      case "$name" in
	yl*|tsh*|admin*)
	  available_roles+=("$name")
	  ;;
      esac
    done

    # Exit if no roles found
    if [[ ${#available_roles[@]} -eq 0 ]]; then
      echo "No roles available. Run 'th init' to set up Teleport proxies and AWS profiles."
      return 1
    fi

    # Direct switch if role name given
    if [[ -n "$1" ]]; then
      for role in "${available_roles[@]}"; do
	if [[ "$1" == "$role" ]]; then
	  source "/tmp/$role"
	  echo "Switched to $role successfully"
	  return 0
	fi
      done
      echo "Error: Role '$1' not found among available roles."
      return 1
    fi

    echo "Available roles:"
    for ((i = 0; i < ${#available_roles[@]}; i++)); do
      printf "%2d. %s\n" $((i + 1)) "${available_roles[$i]}"
    done

    echo
    echo -n "Select which role you'd like to assume (number): "
    read choice

    # Validate numeric input
    if ! echo "$choice" | grep -qE '^[0-9]+$'; then
      echo "Invalid selection. Exiting."
      return 1
    fi

    local index=$((choice - 1))
    if (( index < 0 || index >= ${#available_roles[@]} )); then
      echo "Selection out of range. Exiting."
      return 1
    fi

    local selected_role="${available_roles[$index]}"
    if [[ -f "/tmp/$selected_role" ]]; then
      source "/tmp/$selected_role"
      echo "Switched to $selected_role successfully"
    else
      echo "Error: Role file '/tmp/$selected_role' not found."
      return 1
    fi
  }

  th_kill() {
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_CA_BUNDLE
    unset HTTPS_PROXY

    echo "Cleaning up /tmp and shell profile"

    # Enable nullglob in Zsh to prevent errors from unmatched globs
    if [ -n "$ZSH_VERSION" ]; then
      setopt NULL_GLOB
    fi

    # Remove temp credential files
    for f in /tmp/yl* /tmp/tsh* /tmp/admin_*; do
      [ -e "$f" ] && rm -f "$f"
    done

    # Determine which shell profile to clean
    local shell_name shell_profile
    shell_name=$(basename "$SHELL")

    if [ "$shell_name" = "zsh" ]; then
      shell_profile="$HOME/.zshrc"
    elif [ "$shell_name" = "bash" ]; then
      shell_profile="$HOME/.bash_profile"
    else
      echo "Unsupported shell: $shell_name. Skipping profile cleanup."
      shell_profile=""
    fi

    # Remove any lines sourcing proxy envs from the profile
    if [ -n "$shell_profile" ] && [ -f "$shell_profile" ]; then
      sed -i.bak '/[[:space:]]*source \/tmp\/tsh_proxy_/d' "$shell_profile"
      echo "Cleaned up $shell_profile"
    fi

    # Log out of all TSH apps
    tsh apps logout

    # Kill all tsh proxy aws processes
    ps aux | grep '[t]sh proxy aws' | awk '{print $2}' | xargs kill 2>/dev/null

    echo "Killed all running tsh proxy processes"
  }

  # This function will start a Teleport proxy for the specified account and save the environment variables in a file
  th_proxy() {
    unset AWS_ACCESS_KEY_ID
    unset AWS_SECRET_ACCESS_KEY
    unset AWS_CA_BUNDLE
    unset HTTPS_PROXY
    local ACCOUNT=$1
    local ISADMIN=$2
    if [[ -n $ISADMIN ]]; then
	    echo "I am an admin"
	    echo "$ACCOUNT $ISADMIN"
	    tsh proxy aws --app $ACCOUNT  2>&1 | tee /tmp/tsh_admin_proxy_output.log &
	    # Wait for a bit to ensure the log file gets populated (adjust if needed)
	    sleep 2
	    # Extract the environment variables and save them in a sourceable script
	    grep "export " /tmp/tsh_admin_proxy_output.log > /tmp/admin_$ACCOUNT
    else
	    tsh proxy aws --app $ACCOUNT  2>&1 | tee /tmp/tsh_proxy_output.log &
	    #› Wait for a bit to ensure the log file gets populated (adjust if needed)
	    sleep 2
	    # Extract the environment variables and save them in a sourceable script
	    grep "export " /tmp/tsh_proxy_output.log > /tmp/$ACCOUNT
    fi
    if [[ $ACCOUNT =~ ^yl-us ]]; then
	    echo "export AWS_DEFAULT_REGION=us-east-2" >> "/tmp/$ACCOUNT"
    else
	    echo "export AWS_DEFAULT_REGION=eu-west-1" >> "/tmp/$ACCOUNT"
    fi
  }

  # Inital start-up function. Signs into Teleport & creates files containing ENVs for each account.
  th_init() {
    # Logout first
    th_kill

    # Login to Teleport
    th_login 

    # Set-up proxies for each of the environments
    for i in $(tsh apps ls | awk 'NR>2 {print $1}' | grep -v admin | grep .); do
      tsh apps login $i  2>&1 | tee /tmp/tsh_login_output.log
      if grep -q "ERROR" /tmp/tsh_login_output.log; then
	      ROLE=$(grep arn /tmp/tsh_login_output.log | head -n1 | sed 's/ .*//g')
	      echo "Using role:" $ROLE
	      tsh apps login $i --aws-role $ROLE
      fi
      th_proxy $i
    done
    # Login to yl-admin as admin
    tsh apps login yl-admin --aws-role sudo_admin
    th_proxy yl-admin true
    tsh kube ls | cut -d ' ' -f1 | sed '1,2d' | grep . | xargs -n1 tsh kube login

    printf "Run \033[1mth switch\033[0m or \033[1mth switch <role>\033[0m to select an AWS role."
    printf "\nOr run \033[1mth kube | th k\033[0m to log into a cluster."

  }
  #===============================================
  #================ Kubernetes ===================
  #===============================================
  
  # Helper function for interactive login (choose)
  tkube_interactive_login() {
    th_login

    local output header clusters
    output=$(tsh kube ls -f text)
    header=$(echo "$output" | head -n 2)
    clusters=$(echo "$output" | tail -n +3)

    if [ -z "$clusters" ]; then
      echo "No Kubernetes clusters available."
      return 1
    fi

    # Show header and numbered list of clusters
    echo
    echo "$header"
    echo "$clusters" | nl -w2 -s'. '

    # Prompt for selection
    echo
    echo -n "Choose cluster to login (number): "
    read choice

    if [ -z "$choice" ]; then
      echo "No selection made. Exiting."
      return 1
    fi

    local chosen_line cluster
    chosen_line=$(echo "$clusters" | sed -n "${choice}p")
    if [ -z "$chosen_line" ]; then
      echo "Invalid selection."
      return 1
    fi

    cluster=$(echo "$chosen_line" | awk '{print $1}')
    if [ -z "$cluster" ]; then
      echo "Invalid selection."
      return 1
    fi
    
    echo
    echo "Logging you into cluster: $cluster"
    tsh kube login "$cluster"
  }

  # th kube handler
  tkube() {
    if [ $# -eq 0 ]; then
      tkube_interactive_login
      return
    fi 

    case "$1" in
      -l)
	tsh kube ls -f text
	;;
      -s)
	shift
	if [ $# -eq 0 ]; then
	  echo "Missing arguments for -s"
	  return 1
	fi
	tsh kube sessions "$@"
	;;
      -e)
	shift
	if [ $# -eq 0 ]; then
	  echo "Missing arguments for -e"
	  return 1
	fi
	tsh kube exec "$@"
	;;
      -j)
	shift
	if [ $# -eq 0 ]; then
	  echo "Missing arguments for -j"
	  return 1
	fi
	tsh kube join "$@"
	;;
      *)
	echo "Usage:"
	echo "-l : List all clusters"
	echo "-s : List all sessions"
	echo "-e : Execute command"
	echo "-j : Join something"
	;;
    esac
  }

  #===============================================
  #=================== AWS =======================
  #===============================================
  get_credentials() {
    # Enable nullglob in Zsh to avoid errors on unmatched globs
    if [ -n "$ZSH_VERSION" ]; then
      setopt NULL_GLOB
    fi

    local app
    app=$(tsh apps ls -f text | awk '$1 == ">" { print $2 }')

    if [ -z "$app" ]; then
      echo "No active app found. Run 'tsh apps login <app>' first."
      return 1
    fi

    local log_file="/tmp/tsh_proxy_${app}.log"

    # Kill only the matching tsh proxy for this app
    echo
    echo "Killed existing proxy"
    sleep 2

    # Clean up any matching temp files — won't error in Zsh or Bash now
    for f in /tmp/yl* /tmp/tsh* /tmp/admin_*; do
      [ -e "$f" ] && rm -f "$f"
    done
    echo "Cleaned up existing credentials files."

    echo
    echo "Starting AWS proxy for app: $app..."

    tsh proxy aws --app "$app" > "$log_file" 2>&1 &

    # Wait up to 10 seconds for credentials to appear
    local wait_time=0
    while ! grep -q '^  export AWS_ACCESS_KEY_ID=' "$log_file"; do
      sleep 0.5
      wait_time=$((wait_time + 1))
      if (( wait_time >= 20 )); then
	echo "Timed out waiting for AWS credentials."
	return 1
      fi
    done

    # Retain only export lines
    printf "%s\n" "$(grep -E '^[[:space:]]*export ' "$log_file")" > "$log_file"

    # Source all export lines into the shell
    while read -r line; do
      [[ $line == export* || $line == "  export"* ]] && eval "$line"
    done < "$log_file"

    export ACCOUNT=$app
    echo "export ACCOUNT=$app" >> "$log_file"

    # Determine shell and modify appropriate profile
    local shell_name shell_profile
    shell_name=$(basename "$SHELL")

    if [ "$shell_name" = "zsh" ]; then
      shell_profile="$HOME/.zshrc"
    elif [ "$shell_name" = "bash" ]; then
      shell_profile="$HOME/.bash_profile"
    else
      shell_profile="$HOME/.profile"  # fallback
    fi

    sed -i.bak '/^source \/tmp\/tsh/d' "$shell_profile"
    echo "source $log_file" >> "$shell_profile"

    # Set region based on app name
    if [[ $app =~ ^yl-us ]]; then
      export AWS_DEFAULT_REGION=us-east-2
      echo "export AWS_DEFAULT_REGION=us-east-2" >> "$log_file"
    else
      export AWS_DEFAULT_REGION=eu-west-1
      echo "export AWS_DEFAULT_REGION=eu-west-1" >> "$log_file"
    fi

    echo "Credentials exported, and made global, for app: $app"
  } 
  # Helper function for interactive app login with AWS role selection
  tawsp_interactive_login() {
    th_login

    local output header apps

    # Get the list of apps.
    output=$(tsh apps ls -f text)
    header=$(echo "$output" | head -n 2)
    apps=$(echo "$output" | tail -n +3)

    if [ -z "$apps" ]; then
      echo "No apps available."
      return 1
    fi

    # Display header and numbered list of apps.
    echo
    echo "$header"
    echo "$apps" | nl -w2 -s'. '

    # Prompt for app selection.
    echo
    echo -n "Choose app to login (number): "
    read app_choice
    if [ -z "$app_choice" ]; then
      echo "No selection made. Exiting."
      return 1
    fi

    local chosen_line app
    chosen_line=$(echo "$apps" | sed -n "${app_choice}p")
    if [ -z "$chosen_line" ]; then
      echo "Invalid selection."
      return 1
    fi

    # If the first column is ">", use the second column; otherwise, use the first.
    app=$(echo "$chosen_line" | awk '{if ($1==">") print $2; else print $1;}')
    if [ -z "$app" ]; then
      echo "Invalid selection."
      return 1
    fi

    echo "Selected app: $app"

    # Log out of the selected app to force fresh AWS role output.
    echo "Logging out of app: $app..."
    tsh apps logout > /dev/null 2>&1

    # Run tsh apps login to capture the AWS roles listing.
    # (This command will error out because --aws-role is required, but it prints the available AWS roles.)
    local login_output
    login_output=$(tsh apps login "$app" 2>&1)
    echo $login_output
    return 1
    # Extract the AWS roles section.
    # The section is expected to start after "Available AWS roles:" and end before the error message.
    local role_section
    role_section=$(echo "$login_output" | awk '/Available AWS roles:/{flag=1; next} /ERROR: --aws-role flag is required/{flag=0} flag')

    # Remove lines that contain "ERROR:" or that are empty.
    role_section=$(echo "$role_section" | grep -v "ERROR:" | sed '/^\s*$/d')
    echo $role_section
    return 1

    if [ -z "$role_section" ]; then
      echo "No AWS roles info found. Attempting direct login..."
      tsh apps login "$app"
      return
    fi

    # Assume the first 2 lines of role_section are headers.
    local role_header roles_list
    role_header=$(echo "$role_section" | head -n 2)
    roles_list=$(echo "$role_section" | tail -n +3 | sed '/^\s*$/d')

    if [ -z "$roles_list" ]; then
      echo "No roles found in the AWS roles listing."
      echo "Logging you into app \"$app\" without specifying an AWS role."
      tsh apps login "$app"
      return
    fi

    echo
    echo "Available AWS roles:"
    echo "$role_header"
    echo "$roles_list" | nl -w2 -s'. '

    # Prompt for role selection.
    echo
    echo -n "Choose AWS role (number): " 
    read role_choice
    if [ -z "$role_choice" ]; then
      echo "No selection made. Exiting."
      return 1
    fi

    local chosen_role_line role_name
    chosen_role_line=$(echo "$roles_list" | sed -n "${role_choice}p")
    if [ -z "$chosen_role_line" ]; then
      echo "Invalid selection."
      return 1
    fi

    role_name=$(echo "$chosen_role_line" | awk '{print $1}')
    if [ -z "$role_name" ]; then
      echo "Invalid selection."
      return 1
    fi

    echo "Logging you into app: $app with AWS role: $role_name"
    tsh apps login "$app" --aws-role "$role_name"

    echo
    while true; do
      echo -n "Would you like to create a proxy? (y/n) "
      read proxy
      if [[ $proxy =~ ^[Yy]$ ]]; then
	get_credentials
	break
      elif [[ $proxy =~ ^[Nn]$ ]]; then
	echo "Proxy creation skipped."
	break
      else
	echo "Invalid input. Please enter Y or N."
      fi
    done
  }

  # th aws handler
  tawsp() {
    if [[ $# -eq 0 ]]; then
      tawsp_interactive_login
      return
    fi
    case "$1" in
      -l)
	tsh apps ls -f text
      ;;
      *)
	echo "Usage:"
	echo "-i : Interactive login"
	echo "-l : List all accounts"
    esac
  }

  #===============================================
  #================= Terraform ===================
  #===============================================
  terraform_login() {
    th_login
    tsh apps logout
    tsh apps login "yl-admin" --aws-role "sudo_admin"
    get_credentials
    echo "Logged into yl-admin as sudo_admin."
  }

  #===============================================
  #================== Handler ====================
  #===============================================
  # Handle user input & redirect to the appropriate function
  case "$1" in
    init|i)
      if [[ "$2" == "-h" ]]; then
	echo "Sets up all proxies. Saves each profile to /tmp."
	printf "Once complete can switch between the various accounts with \33[1mth switch\033[0m."
      else
	th_init "$@"
      fi
      ;;
    switch|s)
      if [[ "$2" == "-h" ]]; then
	echo "Switch between the various AWS accounts."
	printf "Usage: \033[1mth switch\033[1m for interactive or"
	printf "\033[1mth switch <profile>\033[0m"
      else
	shift
	th_switch "$@"
      fi
      ;;
    kube|k)
      if [[ "$2" == "-h" ]]; then
	echo "Usage:"
	echo "-l : List all kubernetes clusters"
	echo "-s : List all current sessions"
	echo "-e : Execute a command"
	echo "-j : Join something"
      else
	shift
	tkube "$@"
      fi
      ;;
    terra|t)
      if [[ "$2" == "-h" ]]; then
	echo "Logs into yl-admin as sudo-admin"
      else
	shift
	terraform_login "$@"
      fi
      ;;
    aws|a)
      if [[ "$2" == "-h" ]]; then
	echo "Usage:"
	echo "-l : List all accounts"
      else
	shift
	tawsp "$@"
      fi
      ;;
    logout|l)
      if [[ "$2" == "-h" ]]; then
	echo "Logout from all proxies."
      else
	th_kill
	tsh logout      
      fi
      ;;
    *)
      printf "\033[1mGeneral Usage:\033[0m\n\n"
      printf "Run \033[1mth init\033[0m to start. This will set up all proxies & create files \n"
      printf "which can be used to switch accounts. To switch account run \033[1mth switch|s\033[0m \n"
      printf "which will prompt you with the various available accounts. Once finished \n"
      printf "run \033[1mtsh kill\033[0m to log out of all proxies & clean up /tmp. \n\n"
      printf "\033[1mComplete option list:\033[0m\n\n"
      printf "\033[1mth init   | i\033[0m : Initialise all accounts.\n"
      printf "\033[1mth switch | s\033[0m : Switch active account.\n"
      printf "\033[1mth kube   | k\033[0m : Kubernetes login options.\n"
      printf "\033[1mth aws    | a\033[0m : AWS login options.\n"
      printf "\033[1mth terra  | t\033[0m : Log into yl-admin as sudo-admin.\n"
      printf "\033[1mth logout | l\033[0m : Logout from all proxies.\n"
      printf "\033[1m------------------------------------------------------------------------\033[0m\n"
      printf "For specific instructions regarding any of the above, run \033[1mth <option> -h\033[0m\n"
  esac
}
