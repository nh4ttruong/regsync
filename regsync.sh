#!/bin/bash
###########
# Usage: ./regsync.sh <command> <name> [options]

# Commands:
#   image <image_name>    Sync a container image.
#   chart <chart_name_or_oci_url> [repo_url]    Sync a Helm chart (OCI if starts with oci://, HTTP otherwise).

# Options:
#   -v, --version <tag>       Specify the version/tag of the artifact (default: latest).
#   -p, --path <path>         Override the default destination path (e.g., charts/bitnami).
#   -g, --registry <url>      Override the private registry URL.
#   -s, --source-registry <url>   Specify the source registry for the image (e.g., oci.external-secrets.io).
#   -f, --full-image <image>      Specify the full public image reference (auto-detect registry).
#       --debug               Enable detailed logging to a file in /tmp.
#       --dry-run             Show what would be done without executing.
#   -h, --help                Show this help message.
###########

# --- Configuration ---
SCRIPT_VERSION="latest"
PRIVATE_REGISTRY_URL="${PRIVATE_REGISTRY_URL:-}"
IMAGE_PATH="${IMAGE_PATH:-library}"
CHART_PATH="${CHART_PATH:-charts}"

# --- Logging & Colors ---
DEBUG_MODE=0
DRY_RUN=0
LOG_FILE=""
C_RESET='\033[0m'
C_RED='\033[0;31m'
C_GREEN='\033[0;32m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_CYAN='\033[0;36m'
C_BOLD='\033[1m'

# --- Script Setup ---
set -eo pipefail
CONTAINER_CMD=""

# --- Utility Functions ---

log() {
    local level=$1; shift; local message="$@"; local timestamp; timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color=$C_RESET; local emoji=""
    case "$level" in
        INFO)    color=$C_BLUE;   emoji="ℹ️ " ;;
        SUCCESS) color=$C_GREEN;  emoji="✅" ;;
        WARN)    color=$C_YELLOW; emoji="⚠️ " ;;
        ERROR)   color=$C_RED;    emoji="❌" ;;
        STEP)    color=$C_CYAN;   emoji="➡️ " ;;
        *)       level="DEBUG";   emoji="🐞" ;;
    esac
    echo -e "${color}${C_BOLD}${emoji} ${message}${C_RESET}"
    if [[ "$DEBUG_MODE" -eq 1 ]]; then echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"; fi
}

run_with_spinner() {
    local cmd_to_run="$1"; local message="$2"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log INFO "[DRY-RUN] Would run: ${cmd_to_run}"
        echo -e "${C_GREEN}  ↳ ${message}... ✔ Skipped (dry-run)${C_RESET}"
        return 0
    fi
    local pid; local spin='|/-\'
    local output_target="/dev/null"
    if [[ "$DEBUG_MODE" -eq 1 ]]; then output_target="$LOG_FILE"; fi
    eval "$cmd_to_run" >> "$output_target" 2>&1 &
    pid=$!
    trap "kill $pid 2> /dev/null; log ERROR 'Operation cancelled by user.'; exit 1" SIGINT
    echo -n -e "${C_CYAN}${C_BOLD}  ↳ ${message}... ${C_RESET}"
    local i=0
    while kill -0 $pid 2>/dev/null; do
        i=$(( (i+1) %4 )); echo -n -e "${C_CYAN}\r  ↳ ${message}... ${spin:$i:1}${C_RESET}"; sleep 0.1
    done
    wait $pid; local exit_code=$?
    if [ $exit_code -eq 0 ]; then echo -e "${C_GREEN}\r  ↳ ${message}... ✔ Success${C_RESET}      "; else
        echo -e "${C_RED}\r  ↳ ${message}... ✖ Failed${C_RESET}       "
        if [[ "$DEBUG_MODE" -eq 1 ]]; then
            log ERROR "Operation failed. See details below and in '${LOG_FILE}'."; tail -n 5 "$LOG_FILE" | sed 's/^/    /'
        else log ERROR "Operation failed. Run with --debug for detailed logs."; fi
        exit 1
    fi
    trap - SIGINT
}

usage() {
    echo -e "${C_BOLD}regsync (v${SCRIPT_VERSION})${C_RESET}"
    echo ""
    echo -e "${C_YELLOW}Usage:${C_RESET} $0 <command> <name> [options]"
    echo ""
    echo -e "${C_BOLD}Commands:${C_RESET}"
    echo "  image <image_name>        Sync a container image."
    echo "  chart <chart_name_or_oci_url> [repo_url]    Sync a Helm chart (OCI if starts with oci://, HTTP otherwise). For HTTP, chart_name can be 'repo/name'."
    echo "  set [--registry <url>] [--image-path <path>] [--chart-path <path>]   Set default registry and paths."
    echo ""
    echo -e "${C_BOLD}Options:${C_RESET}"
    echo "  -v, --version <tag>           Specify the version/tag of the artifact (default: latest)."
    echo "  -p, --path <path>             Override the default destination path."
    echo "  -g, --registry <url>          Override the private registry URL."
    echo "  -s, --source-registry <url>   Specify the source registry for the image (e.g., oci.external-secrets.io)."
    echo "  -f, --full-image <image>      Specify the full public image reference (auto-detect registry)."
    echo "      --debug                   Enable detailed logging to a file in /tmp."
    echo "      --dry-run                 Show what would be done without executing."
    echo "  -h, --help                    Show this help message."
}

# --- Validation Functions ---

check_helm() { if ! command -v helm &> /dev/null; then log ERROR "Helm is not installed."; exit 1; fi; }
check_container_engine() {
    if command -v docker &> /dev/null; then CONTAINER_CMD="docker"; elif command -v podman &> /dev/null; then CONTAINER_CMD="podman"
    else log ERROR "Neither 'docker' nor 'podman' was found."; exit 1; fi
    log INFO "Using ${C_BOLD}${CONTAINER_CMD}${C_RESET} as the container engine."
}

##
# Checks login status, checking all standard auth file locations.
# @param $1 - The command type ('image' or 'chart').
##
check_login() {
    local command_type=$1
    log INFO "Checking login status for '${PRIVATE_REGISTRY_URL}'..."

    local is_logged_in=0
    local docker_config="${HOME}/.docker/config.json"
    local podman_config_user="${HOME}/.config/containers/auth.json"
    local podman_config_runtime=""
    if [[ -n "$XDG_RUNTIME_DIR" ]]; then
        podman_config_runtime="${XDG_RUNTIME_DIR}/containers/auth.json"
    fi

    if [[ -n "$podman_config_runtime" ]] && grep -q -E "\"${PRIVATE_REGISTRY_URL}\"" "$podman_config_runtime" 2>/dev/null; then
        is_logged_in=1
    elif [[ -f "$podman_config_user" ]] && grep -q -E "\"${PRIVATE_REGISTRY_URL}\"" "$podman_config_user" 2>/dev/null; then
        is_logged_in=1
    elif [[ -f "$docker_config" ]] && grep -q -E "\"${PRIVATE_REGISTRY_URL}\"" "$docker_config" 2>/dev/null; then
        is_logged_in=1
    fi

    if [[ "$is_logged_in" -eq 0 ]]; then
        log WARN "Login credentials not found. Please log in."
        if [[ "$command_type" == "image" ]]; then
            ${CONTAINER_CMD} login "${PRIVATE_REGISTRY_URL}"
        else # command_type is 'chart'
            helm registry login "${PRIVATE_REGISTRY_URL}"
        fi
        log SUCCESS "Login successful."
    else
        log INFO "Already logged in."
    fi
    echo ""
}

# --- Command Handlers ---

handle_image() {
    local path_override=$1; local artifact_version=$2; local public_image_name=$3; local source_registry=$4; local full_image=$5
    # If full_image is specified, use it directly
    if [[ -n "$full_image" ]]; then
        local public_image="$full_image"
        # Extract image_basename and version from full_image
        local image_basename="${full_image##*/}"
        local version="${public_image##*:}"
        # Remove tag from image_basename if present
        image_basename="${image_basename%%:*}"
        local path=${path_override:-$IMAGE_PATH}
        local private_image="${PRIVATE_REGISTRY_URL}/${path}/${image_basename}:${version}"
        log STEP "Processing Image: ${C_BOLD}${public_image}${C_RESET}"
        log INFO "Target: ${private_image}"
        if [[ "$DRY_RUN" -eq 1 ]]; then
            run_with_spinner "${CONTAINER_CMD} pull ${public_image}" "Pulling image"
            run_with_spinner "${CONTAINER_CMD} tag ${public_image} ${private_image}" "Tagging image"
            run_with_spinner "${CONTAINER_CMD} push ${private_image}" "Pushing image"
        else
            log INFO "Pulling image..."
            ${CONTAINER_CMD} pull ${public_image}
            if [[ $? -ne 0 ]]; then
                log ERROR "Failed to pull image"
                exit 1
            fi
            run_with_spinner "${CONTAINER_CMD} tag ${public_image} ${private_image}" "Tagging image"
            log INFO "Pushing image..."
            ${CONTAINER_CMD} push ${private_image}
            if [[ $? -ne 0 ]]; then
                log ERROR "Failed to push image"
                exit 1
            fi
        fi
        echo ""; log SUCCESS "Successfully mirrored image to ${C_BOLD}${private_image}${C_RESET}"
        return
    fi
    
    # Legacy image handling
    local image_name_only="$public_image_name"
    local image_tag=""
    # If image name contains a colon, extract tag
    if [[ "$public_image_name" == *:* ]]; then
        image_name_only="${public_image_name%%:*}"
        image_tag="${public_image_name##*:}"
    fi
    # If -v/--version is provided, it overrides the tag
    local version="${artifact_version:-$image_tag}"
    [[ -z "$version" ]] && version="latest"
    local path=${path_override:-$IMAGE_PATH}
    local public_image="${image_name_only}:${version}"
    if [[ -n "$source_registry" ]]; then
        public_image="${source_registry}/${image_name_only}:${version}"
    fi
    local image_basename="${image_name_only##*/}"
    local private_image="${PRIVATE_REGISTRY_URL}/${path}/${image_basename}:${version}"
    log STEP "Processing Image: ${C_BOLD}${public_image}${C_RESET}"
    log INFO "Target: ${private_image}"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        run_with_spinner "${CONTAINER_CMD} pull ${public_image}" "Pulling image"
        run_with_spinner "${CONTAINER_CMD} tag ${public_image} ${private_image}" "Tagging image"
        run_with_spinner "${CONTAINER_CMD} push ${private_image}" "Pushing image"
    else
        log INFO "Pulling image..."
        ${CONTAINER_CMD} pull ${public_image}
        if [[ $? -ne 0 ]]; then
            log ERROR "Failed to pull image"
            exit 1
        fi
        run_with_spinner "${CONTAINER_CMD} tag ${public_image} ${private_image}" "Tagging image"
        log INFO "Pushing image..."
        ${CONTAINER_CMD} push ${private_image}
        if [[ $? -ne 0 ]]; then
            log ERROR "Failed to push image"
            exit 1
        fi
    fi
    echo ""; log SUCCESS "Successfully mirrored image to ${C_BOLD}${private_image}${C_RESET}"
}

handle_chart() {
    local path_override=$1; local artifact_version=$2; local chart_type=$3; local public_chart_name=$4; local repo_url=$5
    [[ -z "$public_chart_name" ]] && { log ERROR "Public chart name is required."; usage; exit 1; }

    local version=${artifact_version:-latest}
    local path=${path_override:-$CHART_PATH}
    local oci_repo_path="${PRIVATE_REGISTRY_URL}/${path}"
    local oci_target="oci://${oci_repo_path}"

    local temp_dir; temp_dir=$(mktemp -d)
    local helm_pull_cmd
    local temp_repo_added=false

    if [[ "$chart_type" == "oci" ]]; then
        if [[ "$version" == "latest" ]]; then
            helm_pull_cmd="helm pull ${public_chart_name} -d ${temp_dir}"
        else
            helm_pull_cmd="helm pull ${public_chart_name} -d ${temp_dir} --version ${version}"
        fi
        log STEP "Processing OCI Helm Chart: ${C_BOLD}${public_chart_name}${C_RESET} (version: ${version})"
    elif [[ "$chart_type" == "http" ]]; then
        [[ -z "$repo_url" ]] && { log ERROR "Repo URL is required for HTTP charts."; usage; exit 1; }
        
        # Check if chart name contains repo/name format
        if [[ "$public_chart_name" == */* ]]; then
            # Extract repo name and chart name
            local repo_name="${public_chart_name%%/*}"
            local chart_name="${public_chart_name#*/}"
            
            # Add repo temporarily
            log INFO "Adding Helm repository '${repo_name}' temporarily..."
            helm repo remove "$repo_name" >/dev/null 2>&1 || true
            helm repo add "$repo_name" "$repo_url"
            helm repo update
            helm repo list | grep "$repo_name"
            temp_repo_added=true
            
            # Use the full repo/chart name
            if [[ "$version" == "latest" ]]; then
                helm_pull_cmd="helm pull ${public_chart_name} -d ${temp_dir}"
            else
                helm_pull_cmd="helm pull ${public_chart_name} -d ${temp_dir} --version ${version}"
            fi
        else
            # Use direct --repo method
            if [[ "$version" == "latest" ]]; then
                helm_pull_cmd="helm pull ${public_chart_name} --repo ${repo_url} -d ${temp_dir}"
            else
                helm_pull_cmd="helm pull ${public_chart_name} --repo ${repo_url} -d ${temp_dir} --version ${version}"
            fi
        fi
        
        log STEP "Processing HTTP Helm Chart: ${C_BOLD}${public_chart_name}${C_RESET} from ${repo_url} (Version: ${version})"
    else
        log ERROR "Invalid chart type '$chart_type'."; exit 1
    fi

    log INFO "Target OCI repository: ${oci_target}"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        if [[ "$temp_repo_added" == true ]]; then
            run_with_spinner "helm repo remove '${repo_name}'" "Remove temporary repo"
        fi
        run_with_spinner "$helm_pull_cmd" "Pulling chart package"
        log INFO "Would find chart package in ${temp_dir}"
        run_with_spinner "helm push 'mock.tgz' '${oci_target}'" "Pushing chart to OCI registry"
        run_with_spinner "rm -rf '${temp_dir}'" "Cleaning up temporary files"
    else
        log INFO "Pulling chart package..."
        log INFO "Running: $helm_pull_cmd"
        $helm_pull_cmd
        if [[ $? -ne 0 ]]; then
            if [[ "$temp_repo_added" == true ]]; then
                helm repo remove "$repo_name" >/dev/null 2>&1
            fi
            log ERROR "Failed to pull chart package"
            rm -rf "$temp_dir"
            exit 1
        fi

        local chart_file; chart_file=$(ls -t "${temp_dir}"/*.tgz 2>/dev/null | head -n 1)
        [[ ! -f "$chart_file" ]] && { 
            if [[ "$temp_repo_added" == true ]]; then
                helm repo remove "$repo_name" >/dev/null 2>&1
            fi
            log ERROR "Could not find downloaded chart package (*.tgz) after pull."; rm -rf "$temp_dir"; exit 1; 
        }
        log INFO "Found chart package: ${chart_file}"

        log INFO "Pushing chart to OCI registry..."
    helm push ${chart_file} ${oci_target}
        if [[ $? -ne 0 ]]; then
            if [[ "$temp_repo_added" == true ]]; then
                helm repo remove "$repo_name" >/dev/null 2>&1
            fi
            log ERROR "Failed to push chart to OCI registry"
            rm -rf "$temp_dir"
            exit 1
        fi

        # Clean up temporary repo
        if [[ "$temp_repo_added" == true ]]; then
            run_with_spinner "helm repo remove '${repo_name}'" "Remove temporary repo"
        fi

        run_with_spinner "rm -rf '${temp_dir}'" "Cleaning up temporary files"
    fi

    echo ""; local final_chart_name; final_chart_name=$(basename "$public_chart_name")
    log SUCCESS "Successfully pushed chart to ${C_BOLD}${oci_target}/${final_chart_name}${C_RESET}"
}


# --- Main Execution Logic ---

[[ $# -eq 0 || "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }

COMMAND=$1; shift
path_override=""; artifact_version=""; source_registry=""; full_image=""

# --- Set Command ---
if [[ "$COMMAND" == "set" ]]; then
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --registry)
                [[ -z "$2" || "$2" == -* ]] && { echo "Error: --registry requires a value"; exit 1; }
                sed -i "s|^PRIVATE_REGISTRY_URL=.*$|PRIVATE_REGISTRY_URL=\"$2\"|" "$0"; shift 2 ;;
            --image-path)
                [[ -z "$2" || "$2" == -* ]] && { echo "Error: --image-path requires a value"; exit 1; }
                sed -i "s|^IMAGE_PATH=.*$|IMAGE_PATH=\"$2\"|" "$0"; shift 2 ;;
            --chart-path)
                [[ -z "$2" || "$2" == -* ]] && { echo "Error: --chart-path requires a value"; exit 1; }
                sed -i "s|^CHART_PATH=.*$|CHART_PATH=\"$2\"|" "$0"; shift 2 ;;
            *)
                echo "Unknown option: $1"; exit 1 ;;
        esac
    done
    echo "Defaults updated in $0"
    exit 0
fi

# Parse options first
TEMP_ARGS=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -v|--version)
            [[ -z "$2" || "$2" == -* ]] && { log ERROR "--version flag requires an argument."; exit 1; }
            artifact_version="$2"; shift 2 ;;
        -p|--path)
            [[ -z "$2" || "$2" == -* ]] && { log ERROR "--path flag requires an argument."; exit 1; }
            path_override="$2"; shift 2 ;;
        -g|--registry)
            [[ -z "$2" || "$2" == -* ]] && { log ERROR "--registry flag requires an argument."; exit 1; }
            PRIVATE_REGISTRY_URL="$2"; shift 2 ;;
        -s|--source-registry)
            [[ -z "$2" || "$2" == -* ]] && { log ERROR "--source-registry flag requires an argument."; exit 1; }
            source_registry="$2"; shift 2 ;;
        -f|--full-image)
            [[ -z "$2" || "$2" == -* ]] && { log ERROR "--full-image flag requires an argument."; exit 1; }
            full_image="$2"; shift 2 ;;
        --debug)
            DEBUG_MODE=1; LOG_FILE="/tmp/registry-manager-$(date +%Y%m%d-%H%M%S)-$$.log"
            log INFO "Debug mode enabled. Logging to ${LOG_FILE}"; shift 1 ;;
        --dry-run)
            DRY_RUN=1; log INFO "Dry-run mode enabled."; shift 1 ;;
        -* )
            log ERROR "Unknown option: $1"; usage; exit 1 ;;
        * )
            TEMP_ARGS+=("$1"); shift ;;
    esac
done
# Restore positional arguments
set -- "${TEMP_ARGS[@]}"

# Execute command
case "$COMMAND" in
    image)
        if [[ "$DRY_RUN" -ne 1 ]]; then check_container_engine; check_login "image"; fi
        handle_image "$path_override" "$artifact_version" "$1" "$source_registry" "$full_image" ;;
    chart)
        if [[ "$DRY_RUN" -ne 1 ]]; then check_helm; check_login "chart"; fi
        # Determine chart type and args
        if [[ $# -eq 1 ]]; then
            if [[ "$1" =~ ^oci:// ]]; then
                handle_chart "$path_override" "$artifact_version" "oci" "$1" ""
            else
                log ERROR "Invalid chart argument. For OCI charts use 'chart oci://url', for HTTP charts use 'chart <name> <repo>' or 'chart <repo> <name>' (name can be 'repo/name')."; usage; exit 1
            fi
        elif [[ $# -eq 2 ]]; then
            if [[ "$1" =~ ^https?:// ]]; then
                # Repo URL first, then chart name
                handle_chart "$path_override" "$artifact_version" "http" "$2" "$1"
            else
                # Chart name first, then repo URL
                handle_chart "$path_override" "$artifact_version" "http" "$1" "$2"
            fi
        else
            log ERROR "Invalid number of chart arguments. Use 'chart <oci_url>' for OCI or 'chart <name> <repo>' for HTTP (name can be 'repo/name')."; usage; exit 1
        fi ;;
    *)
        log ERROR "Invalid command '$COMMAND'"; usage; exit 1 ;;
esac