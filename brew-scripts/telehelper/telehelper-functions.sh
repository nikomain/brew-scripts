# ===========================================================
# 		    Teleport CLI shortcuts
# ===========================================================

# Easily log in/out to your Teleport cluster
alias tl='tsh login --auth=ad --proxy=youlend.teleport.sh:443'
alias tlo='tsh logout'
# Quickly obtain AWS credentials via Teleport
alias taws='tsh aws'
hello(){
  echo Hello budopaat
}
# Main tkube function
tkube() {
  # Check for top-level flags:
  # -c for choose (interactive login)
  # -l for list clusters
  if [ "$1" = "-c" ]; then
    tkube_interactive_login
    return
  elif [ "$1" = "-l" ]; then
    tsh kube ls -f text
    return
  fi

  local subcmd="$1"
  shift
  case "$subcmd" in
    ls)
      tsh kube ls -f text
      ;;
    login)
      if [ "$1" = "-c" ]; then
        tkube_interactive_login
      else
        tsh kube login "$@"
      fi
      ;;
    sessions)
      tsh kube sessions "$@"
      ;;
    exec)
      tsh kube exec "$@"
      ;;
    join)
      tsh kube join "$@"
      ;;
    *)
      echo "Usage: tkube {[-c | -l] | ls | login [cluster_name | -c] | sessions | exec | join }"
      ;;
  esac
}

# Main function for Teleport apps
tawsp() {
  # Top-level flags:
  # -c: interactive login (choose app and then role)
  # -l: list available apps
  if [ "$1" = "-c" ]; then
    tawsp_interactive_login
    return
  elif [ "$1" = "-l" ]; then
    tsh apps ls -f text
    return
  elif [ "$1" = "login" ]; then
    shift
    if [ "$1" = "-c" ]; then
      tawsp_interactive_login
    else
      tsh apps login "$@"
    fi
    return
  fi

  echo "Usage: tawsp { -c | -l | login [app_name | -c] }"
}


# /////////////////////////////////////////////
# /////////////// Helper functions ////////////
# /////////////////////////////////////////////

# Helper function for interactive app login with AWS role selection
tawsp_interactive_login() {
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
  echo "$header"
  echo "$apps" | nl -w2 -s'. '

  # Prompt for app selection.
  read -p "Choose app to login (number): " app_choice
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

  # Extract the AWS roles section.
  # The section is expected to start after "Available AWS roles:" and end before the error message.
  local role_section
  role_section=$(echo "$login_output" | awk '/Available AWS roles:/{flag=1; next} /ERROR: --aws-role flag is required/{flag=0} flag')

  # Remove lines that contain "ERROR:" or that are empty.
  role_section=$(echo "$role_section" | grep -v "ERROR:" | sed '/^\s*$/d')

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

  echo "Available AWS roles:"
  echo "$role_header"
  echo "$roles_list" | nl -w2 -s'. '

  # Prompt for role selection.
  read -p "Choose AWS role (number): " role_choice
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
}

# Helper function for interactive login (choose)
tkube_interactive_login() {
  local output header clusters
  output=$(tsh kube ls -f text)
  header=$(echo "$output" | head -n 2)
  clusters=$(echo "$output" | tail -n +3)

  if [ -z "$clusters" ]; then
    echo "No Kubernetes clusters available."
    return 1
  fi

  # Show header and numbered list of clusters
  echo "$header"
  echo "$clusters" | nl -w2 -s'. '

  # Prompt for selection
  read -p "Choose cluster to login (number): " choice

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

  echo "Logging you into cluster: $cluster"
  tsh kube login "$cluster"
}

#===============================================
#===============================================
#===============================================

kill_tsh() {
	unset AWS_ACCESS_KEY_ID
	unset AWS_SECRET_ACCESS_KEY
	unset AWS_CA_BUNDLE
	unset HTTPS_PROXY
	tsh apps logout
	sudo netstat -tlpun | grep tsh | awk '{print $7}' | cut -d '/' -f1 | xargs -I {} kill {}

}

# run this as soon as you boot up, it will setup all of the proxies and end points
# it will create files in /tmp with environment variables that you can source
# to switch between accounts simply source the relavent file.
tsh_apps_init() {
	# Logout first
	kill_tsh

	# Login to Teleport
	tsh login --auth=ad --proxy=youlend.teleport.sh:443
	#for i in admin production usproduction sandbox development staging coreplayground dataplayground usstaging; do
	#	tsh_proxy yl-$i
	#done
	for i in $(tsh apps ls | awk 'NR>2 {print $1}' | grep -v admin | grep .); do
		tsh apps login $i  2>&1 | tee /tmp/tsh_login_output.log
		if grep -q "ERROR" /tmp/tsh_login_output.log; then
			ROLE=$(grep arn /tmp/tsh_login_output.log | head -n1 | sed 's/ .*//g')
			tsh apps login $i --aws-role $ROLE
		fi
		tsh_proxy $i
	done
	tsh apps login yl-admin --aws-role sudo_admin
	tsh_proxy yl-admin true
	tsh kube ls | cut -d ' ' -f1 | sed '1,2d' | grep . | xargs -n1 tsh kube login
	#source /tmp/yl-admin
}
# [3] 39234
#Available AWS roles:
#Role Name Role ARN
#--------- ---------------------------------------
#dev       arn:aws:iam::777909771556:role/dev
#sudo_dev  arn:aws:iam::777909771556:role/sudo_dev
#
#ERROR: --aws-role flag is required
#
#[3]+  Done                    tsh proxy aws --app $ACCOUNT 2>&1 | tee /tmp/tsh_proxy_output.log

# This function will start a Teleport proxy for the specified account and save the environment variables in a file
tsh_proxy() {
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
		# Wait for a bit to ensure the log file gets populated (adjust if needed)
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


