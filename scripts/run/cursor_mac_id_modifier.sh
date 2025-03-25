#!/bin/bash

# Set error handling
set -e

# Define log file path
LOG_FILE="/tmp/cursor_mac_id_modifier.log"

# Initialize log file
initialize_log() {
    echo "========== Cursor ID Modifier Tool Log Start $(date) ==========" > "$LOG_FILE"
    chmod 644 "$LOG_FILE"
}

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log functions - output to both terminal and log file
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

log_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
    echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') $1" >> "$LOG_FILE"
}

# Log command output to log file
log_cmd_output() {
    local cmd="$1"
    local msg="$2"
    echo "[CMD] $(date '+%Y-%m-%d %H:%M:%S') Executing command: $cmd" >> "$LOG_FILE"
    echo "[CMD] $msg:" >> "$LOG_FILE"
    eval "$cmd" 2>&1 | tee -a "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

# Get current user
get_current_user() {
    if [ "$EUID" -eq 0 ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

CURRENT_USER=$(get_current_user)
if [ -z "$CURRENT_USER" ]; then
    log_error "Unable to get username"
    exit 1
fi

# Define configuration file paths
STORAGE_FILE="$HOME/Library/Application Support/Cursor/User/globalStorage/storage.json"
BACKUP_DIR="$HOME/Library/Application Support/Cursor/User/globalStorage/backups"

# Define Cursor application path
CURSOR_APP_PATH="/Applications/Cursor.app"

# Check permissions
check_permissions() {
    if [ "$EUID" -ne 0 ]; then
        log_error "Please run this script with sudo"
        echo "Example: sudo $0"
        exit 1
    fi
}

# Check and kill Cursor process
check_and_kill_cursor() {
    log_info "Checking Cursor process..."
    
    local attempt=1
    local max_attempts=5
    
    # Function: Get process details
    get_process_details() {
        local process_name="$1"
        log_debug "Getting $process_name process details:"
        ps aux | grep -i "/Applications/Cursor.app" | grep -v grep
    }
    
    while [ $attempt -le $max_attempts ]; do
        # Use more precise matching to get Cursor process
        CURSOR_PIDS=$(ps aux | grep -i "/Applications/Cursor.app" | grep -v grep | awk '{print $2}')
        
        if [ -z "$CURSOR_PIDS" ]; then
            log_info "No running Cursor process found"
            return 0
        fi
        
        log_warn "Cursor process is running"
        get_process_details "cursor"
        
        log_warn "Attempting to close Cursor process..."
        
        if [ $attempt -eq $max_attempts ]; then
            log_warn "Attempting to force kill process..."
            kill -9 $CURSOR_PIDS 2>/dev/null || true
        else
            kill $CURSOR_PIDS 2>/dev/null || true
        fi
        
        sleep 1
        
        # Use more precise matching to check if process is still running
        if ! ps aux | grep -i "/Applications/Cursor.app" | grep -v grep > /dev/null; then
            log_info "Cursor process successfully closed"
            return 0
        fi
        
        log_warn "Waiting for process to close, attempt $attempt/$max_attempts..."
        ((attempt++))
    done
    
    log_error "Unable to close Cursor process after $max_attempts attempts"
    get_process_details "cursor"
    log_error "Please close the process manually and try again"
    exit 1
}

# Backup configuration file
backup_config() {
    if [ ! -f "$STORAGE_FILE" ]; then
        log_warn "Configuration file does not exist, skipping backup"
        return 0
    fi
    
    mkdir -p "$BACKUP_DIR"
    local backup_file="$BACKUP_DIR/storage.json.backup_$(date +%Y%m%d_%H%M%S)"
    
    if cp "$STORAGE_FILE" "$backup_file"; then
        chmod 644 "$backup_file"
        chown "$CURRENT_USER" "$backup_file"
        log_info "Configuration backed up to: $backup_file"
    else
        log_error "Backup failed"
        exit 1
    fi
}

# Generate random ID
generate_random_id() {
    # Generate 32 bytes (64 hex characters) random number
    openssl rand -hex 32
}

# Generate random UUID
generate_uuid() {
    uuidgen | tr '[:upper:]' '[:lower:]'
}

# Modify existing file
modify_or_add_config() {
    local key="$1"
    local value="$2"
    local file="$3"
    
    if [ ! -f "$file" ]; then
        log_error "File does not exist: $file"
        return 1
    fi
    
    # Ensure file is writable
    chmod 644 "$file" || {
        log_error "Unable to modify file permissions: $file"
        return 1
    }
    
    # Create temporary file
    local temp_file=$(mktemp)
    
    # Check if key exists
    if grep -q "\"$key\":" "$file"; then
        # Key exists, perform replacement
        sed "s/\"$key\":[[:space:]]*\"[^\"]*\"/\"$key\": \"$value\"/" "$file" > "$temp_file" || {
            log_error "Failed to modify configuration: $key"
            rm -f "$temp_file"
            return 1
        }
    else
        # Key does not exist, add new key-value pair
        sed "s/}$/,\n    \"$key\": \"$value\"\n}/" "$file" > "$temp_file" || {
            log_error "Failed to add configuration: $key"
            rm -f "$temp_file"
            return 1
        }
    fi
    
    # Check if temporary file is empty
    if [ ! -s "$temp_file" ]; then
        log_error "Generated temporary file is empty"
        rm -f "$temp_file"
        return 1
    fi
    
    # Use cat to replace original file content
    cat "$temp_file" > "$file" || {
        log_error "Unable to write to file: $file"
        rm -f "$temp_file"
        return 1
    }
    
    rm -f "$temp_file"
    
    # Restore file permissions
    chmod 444 "$file"
    
    return 0
}

# Generate new configuration
generate_new_config() {
    echo
    log_warn "Machine ID Reset Options"
    
    # Use menu selection function to ask user if they want to reset machine ID
    select_menu_option "Do you want to reset the machine ID? (Usually, modifying js files is sufficient):" "No Reset - Only modify js files|Reset - Modify both configuration and machine ID" 0
    reset_choice=$?
    
    # Log for debugging
    echo "[INPUT_DEBUG] Machine ID reset option choice: $reset_choice" >> "$LOG_FILE"
    
    # Handle user choice - index 0 corresponds to "No Reset" option, index 1 corresponds to "Reset" option
    if [ "$reset_choice" = "1" ]; then
        log_info "You chose to reset machine ID"
        
        # Ensure configuration directory exists
        if [ -f "$STORAGE_FILE" ]; then
            log_info "Found existing configuration file: $STORAGE_FILE"
            
            # Backup existing configuration (just in case)
            backup_config
            
            # Generate and set new device ID
            local new_device_id=$(generate_uuid)
            local new_machine_id="auth0|user_$(openssl rand -hex 16)"
            
            log_info "Setting new device and machine IDs..."
            log_debug "New device ID: $new_device_id"
            log_debug "New machine ID: $new_machine_id"
            
            # Modify configuration file
            if modify_or_add_config "deviceId" "$new_device_id" "$STORAGE_FILE" && \
               modify_or_add_config "machineId" "$new_machine_id" "$STORAGE_FILE"; then
                log_info "Configuration file modification successful"
            else
                log_error "Configuration file modification failed"
            fi
        else
            log_warn "Configuration file not found, this is normal, script will skip ID modification"
        fi
    else
        log_info "You chose not to reset machine ID, will only modify js files"
        
        # Ensure configuration directory exists
        if [ -f "$STORAGE_FILE" ]; then
            log_info "Found existing configuration file: $STORAGE_FILE"
            
            # Backup existing configuration (just in case)
            backup_config
        else
            log_warn "Configuration file not found, this is normal, script will skip ID modification"
        fi
    fi
    
    echo
    log_info "Configuration processing complete"
}

# Clean previous Cursor modifications
clean_cursor_app() {
    log_info "Attempting to clean previous Cursor modifications..."
    
    # If backup exists, restore it directly
    local latest_backup=""
    
    # Find latest backup
    latest_backup=$(find /tmp -name "Cursor.app.backup_*" -type d -print 2>/dev/null | sort -r | head -1)
    
    if [ -n "$latest_backup" ] && [ -d "$latest_backup" ]; then
        log_info "Found existing backup: $latest_backup"
        log_info "Restoring original version..."
        
        # Stop Cursor process
        check_and_kill_cursor
        
        # Restore backup
        sudo rm -rf "$CURSOR_APP_PATH"
        sudo cp -R "$latest_backup" "$CURSOR_APP_PATH"
        sudo chown -R "$CURRENT_USER:staff" "$CURSOR_APP_PATH"
        sudo chmod -R 755 "$CURSOR_APP_PATH"
        
        log_info "Original version restored"
        return 0
    else
        log_warn "No existing backup found, attempting to reinstall Cursor..."
        echo "You can download and reinstall Cursor from https://cursor.sh"
        echo "Or continue with this script to attempt to fix existing installation"
        
        # Add re-download and installation logic here if needed
        return 1
    fi
}

# Modify Cursor main program files (safe mode)
modify_cursor_app_files() {
    log_info "Safely modifying Cursor main program files..."
    log_info "Detailed logs will be recorded to: $LOG_FILE"
    
    # Clean previous modifications first
    clean_cursor_app
    
    # Verify application exists
    if [ ! -d "$CURSOR_APP_PATH" ]; then
        log_error "Cursor.app not found, please verify installation path: $CURSOR_APP_PATH"
        return 1
    fi

    # Define target files - prioritize extensionHostProcess.js
    local target_files=(
        "${CURSOR_APP_PATH}/Contents/Resources/app/out/vs/workbench/api/node/extensionHostProcess.js"
        "${CURSOR_APP_PATH}/Contents/Resources/app/out/main.js"
        "${CURSOR_APP_PATH}/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
    )
    
    # Check if files exist and if they need modification
    local need_modification=false
    local missing_files=false
    
    log_debug "Checking target files..."
    for file in "${target_files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "File does not exist: ${file/$CURSOR_APP_PATH\//}"
            echo "[FILE_CHECK] File does not exist: $file" >> "$LOG_FILE"
            missing_files=true
            continue
        fi
        
        echo "[FILE_CHECK] File exists: $file ($(wc -c < "$file") bytes)" >> "$LOG_FILE"
        
        if ! grep -q "return crypto.randomUUID()" "$file" 2>/dev/null; then
            log_info "File needs modification: ${file/$CURSOR_APP_PATH\//}"
            grep -n "IOPlatformUUID" "$file" | head -3 >> "$LOG_FILE" || echo "[FILE_CHECK] IOPlatformUUID not found" >> "$LOG_FILE"
            need_modification=true
            break
        else
            log_info "File already modified: ${file/$CURSOR_APP_PATH\//}"
        fi
    done
    
    # Exit if all files are modified or don't exist
    if [ "$missing_files" = true ]; then
        log_error "Some target files do not exist, please verify Cursor installation is complete"
        return 1
    fi
    
    if [ "$need_modification" = false ]; then
        log_info "All target files have been modified, no need for further action"
        return 0
    fi

    # Create temporary working directory
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local temp_dir="/tmp/cursor_reset_${timestamp}"
    local temp_app="${temp_dir}/Cursor.app"
    local backup_app="/tmp/Cursor.app.backup_${timestamp}"
    
    log_debug "Creating temporary directory: $temp_dir"
    echo "[TEMP_DIR] Creating temporary directory: $temp_dir" >> "$LOG_FILE"
    
    # Clean up any existing temporary directory
    if [ -d "$temp_dir" ]; then
        log_info "Cleaning up existing temporary directory..."
        rm -rf "$temp_dir"
    fi
    
    # Create new temporary directory
    mkdir -p "$temp_dir" || {
        log_error "Unable to create temporary directory: $temp_dir"
        echo "[ERROR] Unable to create temporary directory: $temp_dir" >> "$LOG_FILE"
        return 1
    }

    # Backup original application
    log_info "Backing up original application..."
    echo "[BACKUP] Starting backup: $CURSOR_APP_PATH -> $backup_app" >> "$LOG_FILE"
    
    cp -R "$CURSOR_APP_PATH" "$backup_app" || {
        log_error "Unable to create application backup"
        echo "[ERROR] Backup failed: $CURSOR_APP_PATH -> $backup_app" >> "$LOG_FILE"
        rm -rf "$temp_dir"
        return 1
    }
    
    echo "[BACKUP] Backup complete" >> "$LOG_FILE"

    # Copy application to temporary directory
    log_info "Creating temporary working copy..."
    echo "[COPY] Starting copy: $CURSOR_APP_PATH -> $temp_dir" >> "$LOG_FILE"
    
    cp -R "$CURSOR_APP_PATH" "$temp_dir" || {
        log_error "Unable to copy application to temporary directory"
        echo "[ERROR] Copy failed: $CURSOR_APP_PATH -> $temp_dir" >> "$LOG_FILE"
        rm -rf "$temp_dir" "$backup_app"
        return 1
    }
    
    echo "[COPY] Copy complete" >> "$LOG_FILE"

    # Ensure correct permissions for temporary directory
    chown -R "$CURRENT_USER:staff" "$temp_dir"
    chmod -R 755 "$temp_dir"

    # Remove signature (enhance compatibility)
    log_info "Removing application signature..."
    echo "[CODESIGN] Removing signature: $temp_app" >> "$LOG_FILE"
    
    codesign --remove-signature "$temp_app" 2>> "$LOG_FILE" || {
        log_warn "Failed to remove application signature"
        echo "[WARN] Failed to remove signature: $temp_app" >> "$LOG_FILE"
    }

    # Remove signatures from all related components
    local components=(
        "$temp_app/Contents/Frameworks/Cursor Helper.app"
        "$temp_app/Contents/Frameworks/Cursor Helper (GPU).app"
        "$temp_app/Contents/Frameworks/Cursor Helper (Plugin).app"
        "$temp_app/Contents/Frameworks/Cursor Helper (Renderer).app"
    )

    for component in "${components[@]}"; do
        if [ -e "$component" ]; then
            log_info "Removing signature: $component"
            codesign --remove-signature "$component" || {
                log_warn "Failed to remove component signature: $component"
            }
        fi
    done
    
    # Modify target files - prioritize js files
    local modified_count=0
    local files=(
        "${temp_app}/Contents/Resources/app/out/vs/workbench/api/node/extensionHostProcess.js"
        "${temp_app}/Contents/Resources/app/out/main.js"
        "${temp_app}/Contents/Resources/app/out/vs/code/node/cliProcessMain.js"
    )
    
    for file in "${files[@]}"; do
        if [ ! -f "$file" ]; then
            log_warn "File does not exist: ${file/$temp_dir\//}"
            continue
        fi
        
        log_debug "Processing file: ${file/$temp_dir\//}"
        echo "[PROCESS] Starting to process file: $file" >> "$LOG_FILE"
        echo "[PROCESS] File size: $(wc -c < "$file") bytes" >> "$LOG_FILE"
        
        # Output file contents to log
        echo "[FILE_CONTENT] First 100 lines of file:" >> "$LOG_FILE"
        head -100 "$file" 2>/dev/null | grep -v "^$" | head -50 >> "$LOG_FILE"
        echo "[FILE_CONTENT] ..." >> "$LOG_FILE"
        
        # Create file backup
        cp "$file" "${file}.bak" || {
            log_error "Unable to create file backup: ${file/$temp_dir\//}"
            echo "[ERROR] Unable to create file backup: $file" >> "$LOG_FILE"
            continue
        }

        # Use sed for replacement instead of string operations
        if [[ "$file" == *"extensionHostProcess.js"* ]]; then
            log_debug "Processing extensionHostProcess.js file..."
            echo "[PROCESS_DETAIL] Starting to process extensionHostProcess.js file" >> "$LOG_FILE"
            
            # Check if target code exists
            if grep -q 'i.header.set("x-cursor-checksum' "$file"; then
                log_debug "Found x-cursor-checksum setting code"
                echo "[FOUND] Found x-cursor-checksum setting code" >> "$LOG_FILE"
                
                # Log matching lines
                grep -n 'i.header.set("x-cursor-checksum' "$file" >> "$LOG_FILE"
                
                # Perform specific replacement
                if sed -i.tmp 's/i\.header\.set("x-cursor-checksum",e===void 0?`${p}${t}`:`${p}${t}\/${e}`)/i.header.set("x-cursor-checksum",e===void 0?`${p}${t}`:`${p}${t}\/${p}`)/' "$file"; then
                    log_info "Successfully modified x-cursor-checksum setting code"
                    echo "[SUCCESS] Successfully completed x-cursor-checksum setting code replacement" >> "$LOG_FILE"
                    # Log modified lines
                    grep -n 'i.header.set("x-cursor-checksum' "$file" >> "$LOG_FILE"
                    ((modified_count++))
                    log_info "Successfully modified file: ${file/$temp_dir\//}"
                else
                    log_error "Failed to modify x-cursor-checksum setting code"
                    echo "[ERROR] Failed to replace x-cursor-checksum setting code" >> "$LOG_FILE"
                    cp "${file}.bak" "$file"
                fi
            else
                log_warn "x-cursor-checksum setting code not found"
                echo "[FILE_CHECK] x-cursor-checksum setting code not found" >> "$LOG_FILE"
                
                # Log file contents for troubleshooting
                echo "[FILE_CONTENT] Lines containing 'header.set':" >> "$LOG_FILE"
                grep -n "header.set" "$file" | head -20 >> "$LOG_FILE"
                
                echo "[FILE_CONTENT] Lines containing 'checksum':" >> "$LOG_FILE"
                grep -n "checksum" "$file" | head -20 >> "$LOG_FILE"
            fi
            
            echo "[PROCESS_DETAIL] Completed processing extensionHostProcess.js file" >> "$LOG_FILE"
        elif grep -q "IOPlatformUUID" "$file"; then
            log_debug "Found IOPlatformUUID keyword"
            echo "[FOUND] Found IOPlatformUUID keyword" >> "$LOG_FILE"
            grep -n "IOPlatformUUID" "$file" | head -5 >> "$LOG_FILE"
            
            # Locate IOPlatformUUID related function
            if grep -q "function a\$" "$file"; then
                # Check if already modified
                if grep -q "return crypto.randomUUID()" "$file"; then
                    log_info "File already contains randomUUID call, skipping modification"
                    ((modified_count++))
                    continue
                fi
                
                # Modify for code structure found in main.js
                if sed -i.tmp 's/function a\$(t){switch/function a\$(t){return crypto.randomUUID(); switch/' "$file"; then
                    log_debug "Successfully injected randomUUID call into a\$ function"
                    ((modified_count++))
                    log_info "Successfully modified file: ${file/$temp_dir\//}"
                else
                    log_error "Failed to modify a\$ function"
                    cp "${file}.bak" "$file"
                fi
            elif grep -q "async function v5" "$file"; then
                # Check if already modified
                if grep -q "return crypto.randomUUID()" "$file"; then
                    log_info "File already contains randomUUID call, skipping modification"
                    ((modified_count++))
                    continue
                fi
                
                # Alternative method - modify v5 function
                if sed -i.tmp 's/async function v5(t){let e=/async function v5(t){return crypto.randomUUID(); let e=/' "$file"; then
                    log_debug "Successfully injected randomUUID call into v5 function"
                    ((modified_count++))
                    log_info "Successfully modified file: ${file/$temp_dir\//}"
                else
                    log_error "Failed to modify v5 function"
                    cp "${file}.bak" "$file"
                fi
            else
                # Check if custom code already injected
                if grep -q "// Cursor ID Modifier Tool Injection" "$file"; then
                    log_info "File already contains custom injection code, skipping modification"
                    ((modified_count++))
                    continue
                fi
                
                # Use more generic injection method
                log_warn "Specific function not found, attempting generic modification method"
                inject_code="
// Cursor ID Modifier Tool Injection - $(date +%Y%m%d%H%M%S)
// Random Device ID Generator Injection - $(date +%s)
const randomDeviceId_$(date +%s) = () => {
    try {
        return require('crypto').randomUUID();
    } catch (e) {
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, c => {
            const r = Math.random() * 16 | 0;
            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
        });
    }
};
"
                # Inject code at file beginning
                echo "$inject_code" > "${file}.new"
                cat "$file" >> "${file}.new"
                mv "${file}.new" "$file"
                
                # Replace call points
                sed -i.tmp 's/await v5(!1)/randomDeviceId_'"$(date +%s)"'()/g' "$file"
                sed -i.tmp 's/a\$(t)/randomDeviceId_'"$(date +%s)"'()/g' "$file"
                
                log_debug "Completed generic modification"
                ((modified_count++))
                log_info "Successfully modified file using generic method: ${file/$temp_dir\//}"
            fi
        else
            # IOPlatformUUID not found, file structure might have changed
            log_warn "IOPlatformUUID not found, attempting alternative method"
            
            # Check if already injected or modified
            if grep -q "return crypto.randomUUID()" "$file" || grep -q "// Cursor ID Modifier Tool Injection" "$file"; then
                log_info "File already modified, skipping modification"
                ((modified_count++))
                continue
            fi
            
            # Try to find other key functions like getMachineId or getDeviceId
            if grep -q "function t\$()" "$file" || grep -q "async function y5" "$file"; then
                log_debug "Found device ID related function"
                
                # Modify MAC address retrieval function
                if grep -q "function t\$()" "$file"; then
                    sed -i.tmp 's/function t\$(){/function t\$(){return "00:00:00:00:00:00";/' "$file"
                    log_debug "Successfully modified MAC address retrieval function"
                fi
                
                # Modify device ID retrieval function
                if grep -q "async function y5" "$file"; then
                    sed -i.tmp 's/async function y5(t){/async function y5(t){return crypto.randomUUID();/' "$file"
                    log_debug "Successfully modified device ID retrieval function"
                fi
                
                ((modified_count++))
                log_info "Successfully modified file using alternative method: ${file/$temp_dir\//}"
            else
                # Last resort - insert function override at file beginning
                log_warn "No known functions found, using most generic method"
                
                inject_universal_code="
// Cursor ID Modifier Tool Injection - $(date +%Y%m%d%H%M%S)
// Global Device Identifier Interception - $(date +%s)
const originalRequire_$(date +%s) = require;
require = function(module) {
    const result = originalRequire_$(date +%s)(module);
    if (module === 'crypto' && result.randomUUID) {
        const originalRandomUUID_$(date +%s) = result.randomUUID;
        result.randomUUID = function() {
            return '${new_uuid}';
        };
    }
    return result;
};

// Override all possible system ID retrieval functions
global.getMachineId = function() { return '${machine_id}'; };
global.getDeviceId = function() { return '${device_id}'; };
global.macMachineId = '${mac_machine_id}';
"
                # Inject code at file beginning
                local new_uuid=$(uuidgen | tr '[:upper:]' '[:lower:]')
                local machine_id="auth0|user_$(openssl rand -hex 16)"
                local device_id=$(uuidgen | tr '[:upper:]' '[:lower:]')
                local mac_machine_id=$(openssl rand -hex 32)
                
                inject_universal_code=${inject_universal_code//\$\{new_uuid\}/$new_uuid}
                inject_universal_code=${inject_universal_code//\$\{machine_id\}/$machine_id}
                inject_universal_code=${inject_universal_code//\$\{device_id\}/$device_id}
                inject_universal_code=${inject_universal_code//\$\{mac_machine_id\}/$mac_machine_id}
                
                echo "$inject_universal_code" > "${file}.new"
                cat "$file" >> "${file}.new"
                mv "${file}.new" "$file"
                
                log_debug "Completed universal override"
                ((modified_count++))
                log_info "Successfully modified file using most generic method: ${file/$temp_dir\//}"
            fi
        fi
        
        # Log after key operations
        echo "[MODIFIED] File contents after modification:" >> "$LOG_FILE"
        grep -n "return crypto.randomUUID()" "$file" | head -3 >> "$LOG_FILE"
        
        # Clean up temporary files
        rm -f "${file}.tmp" "${file}.bak"
        echo "[PROCESS] File processing complete: $file" >> "$LOG_FILE"
    done
    
    if [ "$modified_count" -eq 0 ]; then
        log_error "Failed to modify any files"
        rm -rf "$temp_dir"
        return 1
    fi
    
    # Re-sign application (with retry mechanism)
    local max_retry=3
    local retry_count=0
    local sign_success=false
    
    while [ $retry_count -lt $max_retry ]; do
        ((retry_count++))
        log_info "Attempting signature (attempt $retry_count)..."
        
        # Use more detailed signature parameters
        if codesign --sign - --force --deep --preserve-metadata=entitlements,identifier,flags "$temp_app" 2>&1 | tee /tmp/codesign.log; then
            # Verify signature
            if codesign --verify -vvvv "$temp_app" 2>/dev/null; then
                sign_success=true
                log_info "Application signature verification passed"
                break
            else
                log_warn "Signature verification failed, error log:"
                cat /tmp/codesign.log
            fi
        else
            log_warn "Signature failed, error log:"
            cat /tmp/codesign.log
        fi
        
        sleep 1
    done

    if ! $sign_success; then
        log_error "Failed to complete signature after $max_retry attempts"
        log_error "Please manually execute the following command to complete signature:"
        echo -e "${BLUE}sudo codesign --sign - --force --deep '${temp_app}'${NC}"
        echo -e "${YELLOW}After operation, please manually copy the application to original path:${NC}"
        echo -e "${BLUE}sudo cp -R '${temp_app}' '/Applications/'${NC}"
        log_info "Temporary files preserved at: ${temp_dir}"
        return 1
    fi

    # Replace original application
    log_info "Installing modified application..."
    if ! sudo rm -rf "$CURSOR_APP_PATH" || ! sudo cp -R "$temp_app" "/Applications/"; then
        log_error "Application replacement failed, restoring..."
        sudo rm -rf "$CURSOR_APP_PATH"
        sudo cp -R "$backup_app" "$CURSOR_APP_PATH"
        rm -rf "$temp_dir" "$backup_app"
        return 1
    fi
    
    # Clean up temporary files
    rm -rf "$temp_dir" "$backup_app"
    
    # Set permissions
    sudo chown -R "$CURRENT_USER:staff" "$CURSOR_APP_PATH"
    sudo chmod -R 755 "$CURSOR_APP_PATH"
    
    log_info "Cursor main program files modification complete! Original backup at: ${backup_app/$HOME/\~}"
    return 0
}

# Show file tree structure
show_file_tree() {
    local base_dir=$(dirname "$STORAGE_FILE")
    echo
    log_info "File structure:"
    echo -e "${BLUE}$base_dir${NC}"
    echo "├── globalStorage"
    echo "│   ├── storage.json (modified)"
    echo "│   └── backups"
    
    # List backup files
    if [ -d "$BACKUP_DIR" ]; then
        local backup_files=("$BACKUP_DIR"/*)
        if [ ${#backup_files[@]} -gt 0 ]; then
            for file in "${backup_files[@]}"; do
                if [ -f "$file" ]; then
                    echo "│       └── $(basename "$file")"
                fi
            done
        else
            echo "│       └── (empty)"
        fi
    fi
    echo
}

# Show follow information
show_follow_info() {
    echo
    echo -e "${GREEN}================================${NC}"
    echo -e "${YELLOW}  Follow us on WeChat Official Account [煎饼果子卷AI] for more Cursor tips and AI knowledge (Script is free, follow for more tips and experts) ${NC}"
    echo -e "${GREEN}================================${NC}"
    echo
}

# Disable auto-update
disable_auto_update() {
    local updater_path="$HOME/Library/Application Support/Caches/cursor-updater"
    local app_update_yml="/Applications/Cursor.app/Contents/Resources/app-update.yml"
    
    echo
    log_info "Disabling Cursor auto-update..."
    
    # Backup and clear app-update.yml
    if [ -f "$app_update_yml" ]; then
        log_info "Backing up and modifying app-update.yml..."
        if ! sudo cp "$app_update_yml" "${app_update_yml}.bak" 2>/dev/null; then
            log_warn "Failed to backup app-update.yml, continuing..."
        fi
        
        if sudo bash -c "echo '' > \"$app_update_yml\"" && \
           sudo chmod 444 "$app_update_yml"; then
            log_info "Successfully disabled app-update.yml"
        else
            log_error "Failed to modify app-update.yml, please manually execute the following commands:"
            echo -e "${BLUE}sudo cp \"$app_update_yml\" \"${app_update_yml}.bak\"${NC}"
            echo -e "${BLUE}sudo bash -c 'echo \"\" > \"$app_update_yml\"'${NC}"
            echo -e "${BLUE}sudo chmod 444 \"$app_update_yml\"${NC}"
        fi
    else
        log_warn "app-update.yml file not found"
    fi
    
    # Also handle cursor-updater
    log_info "Processing cursor-updater..."
    if sudo rm -rf "$updater_path" && \
       sudo touch "$updater_path" && \
       sudo chmod 444 "$updater_path"; then
        log_info "Successfully disabled cursor-updater"
    else
        log_error "Failed to disable cursor-updater, please manually execute the following command:"
        echo -e "${BLUE}sudo rm -rf \"$updater_path\" && sudo touch \"$updater_path\" && sudo chmod 444 \"$updater_path\"${NC}"
    fi
    
    echo
    log_info "Verification method:"
    echo "1. Run command: ls -l \"$updater_path\""
    echo "   Confirm file permissions show as: r--r--r--"
    echo "2. Run command: ls -l \"$app_update_yml\""
    echo "   Confirm file permissions show as: r--r--r--"
    echo
    log_info "Please restart Cursor after completion"
}

# New restore feature option
restore_feature() {
    # Check if backup directory exists
    if [ ! -d "$BACKUP_DIR" ]; then
        log_warn "Backup directory does not exist"
        return 1
    fi

    # Get backup file list using find command and store in array
    backup_files=()
    while IFS= read -r file; do
        [ -f "$file" ] && backup_files+=("$file")
    done < <(find "$BACKUP_DIR" -name "*.backup_*" -type f 2>/dev/null | sort)
    
    # Check if backup files found
    if [ ${#backup_files[@]} -eq 0 ]; then
        log_warn "No backup files found"
        return 1
    fi
    
    echo
    log_info "Available backup files:"
    
    # Build menu options string
    menu_options="Exit - Do not restore any files"
    for i in "${!backup_files[@]}"; do
        menu_options="$menu_options|$(basename "${backup_files[$i]}")"
    done
    
    # Use menu selection function
    select_menu_option "Use up/down arrows to select backup file to restore, press Enter to confirm:" "$menu_options" 0
    choice=$?
    
    # Handle user input
    if [ "$choice" = "0" ]; then
        log_info "Skipping restore operation"
        return 0
    fi
    
    # Get selected backup file (subtract 1 because first option is "Exit")
    local selected_backup="${backup_files[$((choice-1))]}"
    
    # Verify file existence and readability
    if [ ! -f "$selected_backup" ] || [ ! -r "$selected_backup" ]; then
        log_error "Unable to access selected backup file"
        return 1
    fi
    
    # Attempt to restore configuration
    if cp "$selected_backup" "$STORAGE_FILE"; then
        chmod 644 "$STORAGE_FILE"
        chown "$CURRENT_USER" "$STORAGE_FILE"
        log_info "Configuration restored from backup file: $(basename "$selected_backup")"
        return 0
    else
        log_error "Failed to restore configuration"
        return 1
    fi
}

# Fix "Application is damaged" issue
fix_damaged_app() {
    log_info "Fixing 'Application is damaged' issue..."
    
    # Check if Cursor application exists
    if [ ! -d "$CURSOR_APP_PATH" ]; then
        log_error "Cursor application not found: $CURSOR_APP_PATH"
        return 1
    fi
    
    log_info "Attempting to remove quarantine attribute..."
    if sudo xattr -rd com.apple.quarantine "$CURSOR_APP_PATH" 2>/dev/null; then
        log_info "Successfully removed quarantine attribute"
    else
        log_warn "Failed to remove quarantine attribute, trying alternative method..."
    fi
    
    log_info "Attempting to re-sign application..."
    if sudo codesign --force --deep --sign - "$CURSOR_APP_PATH" 2>/dev/null; then
        log_info "Application re-signing successful"
    else
        log_warn "Application re-signing failed"
    fi
    
    echo
    log_info "Fix complete! Please try opening Cursor application again"
    echo
    echo -e "${YELLOW}If still unable to open, you can try the following methods:${NC}"
    echo "1. Click 'Open Anyway' button in System Preferences -> Security & Privacy"
    echo "2. Temporarily disable Gatekeeper (not recommended): sudo spctl --master-disable"
    echo "3. Re-download and install Cursor application"
    echo
    echo -e "${BLUE}Reference link: https://sysin.org/blog/macos-if-crashes-when-opening/${NC}"
    
    return 0
}

# New: Generic menu selection function
# Parameters: 
# $1 - Prompt message
# $2 - Options array, format: "Option1|Option2|Option3"
# $3 - Default option index (starting from 0)
# Returns: Selected option index (starting from 0)
select_menu_option() {
    local prompt="$1"
    IFS='|' read -ra options <<< "$2"
    local default_index=${3:-0}
    local selected_index=$default_index
    local key_input
    local cursor_up='\033[A'
    local cursor_down='\033[B'
    local enter_key=$'\n'
    
    # Save cursor position
    tput sc
    
    # Display prompt message
    echo -e "$prompt"
    
    # First display menu
    for i in "${!options[@]}"; do
        if [ $i -eq $selected_index ]; then
            echo -e " ${GREEN}►${NC} ${options[$i]}"
        else
            echo -e "   ${options[$i]}"
        fi
    done
    
    # Loop handling keyboard input
    while true; do
        # Read single key
        read -rsn3 key_input
        
        # Detect key
        case "$key_input" in
            # Up arrow key
            $'\033[A')
                if [ $selected_index -gt 0 ]; then
                    ((selected_index--))
                fi
                ;;
            # Down arrow key
            $'\033[B')
                if [ $selected_index -lt $((${#options[@]}-1)) ]; then
                    ((selected_index++))
                fi
                ;;
            # Enter key
            "")
                echo # New line
                log_info "You selected: ${options[$selected_index]}"
                return $selected_index
                ;;
        esac
        
        # Restore cursor position
        tput rc
        
        # Redisplay menu
        for i in "${!options[@]}"; do
            if [ $i -eq $selected_index ]; then
                echo -e " ${GREEN}►${NC} ${options[$i]}"
            else
                echo -e "   ${options[$i]}"
            fi
        done
    done
}

# Main function
main() {
    
    # Initialize log file
    initialize_log
    log_info "Script started..."
    
    # Record system information
    log_info "System information: $(uname -a)"
    log_info "Current user: $CURRENT_USER"
    log_cmd_output "sw_vers" "macOS version information"
    log_cmd_output "which codesign" "codesign path"
    log_cmd_output "ls -la \"$CURSOR_APP_PATH\"" "Cursor application information"
    
    # New environment check
    if [[ $(uname) != "Darwin" ]]; then
        log_error "This script only supports macOS systems"
        exit 1
    fi
    
    clear
    # Display Logo
    echo -e "
    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝
    "
    echo -e "${BLUE}================================${NC}"
    echo -e "${GREEN}   Cursor Launch Tool          ${NC}"
    echo -e "${YELLOW}  Follow us on WeChat Official Account [煎饼果子卷AI]     ${NC}"
    echo -e "${YELLOW}  For more Cursor tips and AI knowledge (Script is free, follow for more tips and experts)  ${NC}"
    echo -e "${BLUE}================================${NC}"
    echo
    echo -e "${YELLOW}[Important Note]${NC} This tool prioritizes modifying js files for better safety and reliability"
    echo -e "${YELLOW}[Important Note]${NC} This tool is free, if it helps you, please follow our WeChat Official Account [煎饼果子卷AI]"
    echo
    
    # Execute main functions
    check_permissions
    check_and_kill_cursor
    backup_config
    
    # Ask user if they want to reset machine ID (default: no)
    generate_new_config
    
    # Execute main program file modification
    log_info "Executing main program file modification..."
    
    # Use subshell to execute modification, avoid errors causing entire script to exit
    (
        if modify_cursor_app_files; then
            log_info "Main program file modification successful!"
        else
            log_warn "Main program file modification failed, but configuration file modification might have succeeded"
            log_warn "If Cursor still shows device disabled after restart, please run this script again"
        fi
    )
    
    # Restore error handling
    set -e
    
    show_file_tree
    show_follow_info
  
    # Directly execute disable auto-update
    disable_auto_update

    log_info "Please restart Cursor to apply new configuration"

    # Display final prompt information
    show_follow_info

    # Provide fix option (moved to end)
    echo
    log_warn "Cursor Fix Options"
    
    # Use new menu selection function
    select_menu_option "Use up/down arrows to select, press Enter to confirm:" "Ignore - Do not execute fix operation|Fix Mode - Restore original Cursor installation" 0
    fix_choice=$?
    
    # Log for debugging
    echo "[INPUT_DEBUG] Fix option choice: $fix_choice" >> "$LOG_FILE"
    
    # Ensure script doesn't terminate due to input issues
    set +e
    
    # Handle user choice - index 1 corresponds to "Fix Mode" option
    if [ "$fix_choice" = "1" ]; then
        log_info "You chose Fix Mode"
        # Use subshell to execute cleanup, avoid errors causing entire script to exit
        (
            if clean_cursor_app; then
                log_info "Cursor restored to original state"
                log_info "If you need to apply ID modification, please run this script again"
            else
                log_warn "Backup not found, unable to auto-restore"
                log_warn "Recommendation: Reinstall Cursor"
            fi
        )
    else
        log_info "Skipped fix operation"
    fi
    
    # Restore error handling
    set -e

    # Record script completion information
    log_info "Script execution complete"
    echo "========== Cursor ID Modifier Tool Log End $(date) ==========" >> "$LOG_FILE"
    
    # Display log file location
    echo
    log_info "Detailed logs saved to: $LOG_FILE"
    echo "If you encounter issues, please provide this log file to the developer for troubleshooting"
    echo
    
    # Add fix for "Application is damaged" option
    echo
    log_warn "Application Fix Options"
    
    # Use new menu selection function
    select_menu_option "Use up/down arrows to select, press Enter to confirm:" "Ignore - Do not execute fix operation|Fix 'Application is damaged' issue - Resolve macOS prompt that application is damaged and cannot be opened" 0
    damaged_choice=$?
    
    echo "[INPUT_DEBUG] Application fix option choice: $damaged_choice" >> "$LOG_FILE"
    
    set +e
    
    # Handle user choice - index 1 corresponds to "Fix Application is damaged" option
    if [ "$damaged_choice" = "1" ]; then
        log_info "You chose to fix 'Application is damaged' issue"
        (
            if fix_damaged_app; then
                log_info "Fix for 'Application is damaged' issue complete"
            else
                log_warn "Fix for 'Application is damaged' issue failed"
            fi
        )
    else
        log_info "Skipped application fix operation"
    fi
    
    set -e
}

# Execute main function
main

