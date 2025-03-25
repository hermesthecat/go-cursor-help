# Set output encoding to UTF-8
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Color definitions
$RED = "`e[31m"
$GREEN = "`e[32m"
$YELLOW = "`e[33m"
$BLUE = "`e[34m"
$NC = "`e[0m"

# Configuration file paths
$STORAGE_FILE = "$env:APPDATA\Cursor\User\globalStorage\storage.json"
$BACKUP_DIR = "$env:APPDATA\Cursor\User\globalStorage\backups"

# Check administrator privileges
function Test-Administrator {
    $user = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($user)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Administrator)) {
    Write-Host "$RED[Error]$NC Please run this script as administrator"
    Write-Host "Please right-click on the script and select 'Run as Administrator'"
    Read-Host "Press Enter to exit"
    exit 1
}

# Display Logo
Clear-Host
Write-Host @"

    ██████╗██╗   ██╗██████╗ ███████╗ ██████╗ ██████╗ 
   ██╔════╝██║   ██║██╔══██╗██╔════╝██╔═══██╗██╔══██╗
   ██║     ██║   ██║██████╔╝███████╗██║   ██║██████╔╝
   ██║     ██║   ██║██╔══██╗╚════██║██║   ██║██╔══██╗
   ╚██████╗╚██████╔╝██║  ██║███████║╚██████╔╝██║  ██║
    ╚═════╝ ╚═════╝ ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚═╝  ╚═╝

"@
Write-Host "$BLUE================================$NC"
Write-Host "$GREEN   Cursor Device ID Modifier Tool        $NC"
Write-Host "$YELLOW  Follow public account [JianBingGuoZiJuanAI] $NC"
Write-Host "$YELLOW  Discuss more Cursor tips and AI knowledge (script is free, follow the public account to join the group for more tips and masters)  $NC"
Write-Host "$YELLOW  [Important Note] This tool is free, if it helps you, please follow the public account [JianBingGuoZiJuanAI]  $NC"
Write-Host "$BLUE================================$NC"
Write-Host ""

# Get and display Cursor version
function Get-CursorVersion {
    try {
        # Main detection path
        $packagePath = "$env:LOCALAPPDATA\Programs\cursor\resources\app\package.json"
        
        if (Test-Path $packagePath) {
            $packageJson = Get-Content $packagePath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Currently installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        # Alternative path detection
        $altPath = "$env:LOCALAPPDATA\cursor\resources\app\package.json"
        if (Test-Path $altPath) {
            $packageJson = Get-Content $altPath -Raw | ConvertFrom-Json
            if ($packageJson.version) {
                Write-Host "$GREEN[Info]$NC Currently installed Cursor version: v$($packageJson.version)"
                return $packageJson.version
            }
        }

        Write-Host "$YELLOW[Warning]$NC Unable to detect Cursor version"
        Write-Host "$YELLOW[Tip]$NC Please ensure Cursor is correctly installed"
        return $null
    }
    catch {
        Write-Host "$RED[Error]$NC Failed to get Cursor version: $_"
        return $null
    }
}

# Get and display version information
$cursorVersion = Get-CursorVersion
Write-Host ""

Write-Host "$YELLOW[Important Note]$NC Latest 0.47.x (is supported)"
Write-Host ""

# Check and close Cursor processes
Write-Host "$GREEN[Info]$NC Checking Cursor processes..."

function Get-ProcessDetails {
    param($processName)
    Write-Host "$BLUE[Debug]$NC Getting $processName process details:"
    Get-WmiObject Win32_Process -Filter "name='$processName'" | 
        Select-Object ProcessId, ExecutablePath, CommandLine | 
        Format-List
}

# Define maximum retries and wait time
$MAX_RETRIES = 5
$WAIT_TIME = 1

# Handle process closing
function Close-CursorProcess {
    param($processName)
    
    $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
    if ($process) {
        Write-Host "$YELLOW[Warning]$NC Found $processName running"
        Get-ProcessDetails $processName
        
        Write-Host "$YELLOW[Warning]$NC Attempting to close $processName..."
        Stop-Process -Name $processName -Force
        
        $retryCount = 0
        while ($retryCount -lt $MAX_RETRIES) {
            $process = Get-Process -Name $processName -ErrorAction SilentlyContinue
            if (-not $process) { break }
            
            $retryCount++
            if ($retryCount -ge $MAX_RETRIES) {
                Write-Host "$RED[Error]$NC Unable to close $processName after $MAX_RETRIES attempts"
                Get-ProcessDetails $processName
                Write-Host "$RED[Error]$NC Please close the process manually and try again"
                Read-Host "Press Enter to exit"
                exit 1
            }
            Write-Host "$YELLOW[Warning]$NC Waiting for process to close, attempt $retryCount/$MAX_RETRIES..."
            Start-Sleep -Seconds $WAIT_TIME
        }
        Write-Host "$GREEN[Info]$NC $processName has been successfully closed"
    }
}

# Close all Cursor processes
Close-CursorProcess "Cursor"
Close-CursorProcess "cursor"

# Create backup directory
if (-not (Test-Path $BACKUP_DIR)) {
    New-Item -ItemType Directory -Path $BACKUP_DIR | Out-Null
}

# Backup existing configuration
if (Test-Path $STORAGE_FILE) {
    Write-Host "$GREEN[Info]$NC Backing up configuration file..."
    $backupName = "storage.json.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $STORAGE_FILE "$BACKUP_DIR\$backupName"
}

# Generate new IDs
Write-Host "$GREEN[Info]$NC Generating new IDs..."

# Add this function after color definitions
function Get-RandomHex {
    param (
        [int]$length
    )
    
    $bytes = New-Object byte[] ($length)
    $rng = [System.Security.Cryptography.RNGCryptoServiceProvider]::new()
    $rng.GetBytes($bytes)
    $hexString = [System.BitConverter]::ToString($bytes) -replace '-',''
    $rng.Dispose()
    return $hexString
}

# Improved ID generation function
function New-StandardMachineId {
    $template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
    $result = $template -replace '[xy]', {
        param($match)
        $r = [Random]::new().Next(16)
        $v = if ($match.Value -eq "x") { $r } else { ($r -band 0x3) -bor 0x8 }
        return $v.ToString("x")
    }
    return $result
}

# Use new function when generating IDs
$MAC_MACHINE_ID = New-StandardMachineId
$UUID = [System.Guid]::NewGuid().ToString()
# Convert auth0|user_ to hexadecimal byte array
$prefixBytes = [System.Text.Encoding]::UTF8.GetBytes("auth0|user_")
$prefixHex = -join ($prefixBytes | ForEach-Object { '{0:x2}' -f $_ })
# Generate 32 bytes (64 hexadecimal characters) of random data as the random part of machineId
$randomPart = Get-RandomHex -length 32
$MACHINE_ID = "$prefixHex$randomPart"
$SQM_ID = "{$([System.Guid]::NewGuid().ToString().ToUpper())}"

# Add permissions check before Update-MachineGuid function
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "$RED[Error]$NC Please run this script with administrator privileges"
    Start-Process powershell "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    exit
}

function Update-MachineGuid {
    try {
        # Check if registry path exists, create if not
        $registryPath = "HKLM:\SOFTWARE\Microsoft\Cryptography"
        if (-not (Test-Path $registryPath)) {
            Write-Host "$YELLOW[Warning]$NC Registry path does not exist: $registryPath, creating..."
            New-Item -Path $registryPath -Force | Out-Null
            Write-Host "$GREEN[Info]$NC Registry path created successfully"
        }

        # Get current MachineGuid, use empty string as default if it doesn't exist
        $originalGuid = ""
        try {
            $currentGuid = Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction SilentlyContinue
            if ($currentGuid) {
                $originalGuid = $currentGuid.MachineGuid
                Write-Host "$GREEN[Info]$NC Current registry value:"
                Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography" 
                Write-Host "    MachineGuid    REG_SZ    $originalGuid"
            } else {
                Write-Host "$YELLOW[Warning]$NC MachineGuid value does not exist, will create new value"
            }
        } catch {
            Write-Host "$YELLOW[Warning]$NC Failed to get MachineGuid: $($_.Exception.Message)"
        }

        # Create backup directory (if it doesn't exist)
        if (-not (Test-Path $BACKUP_DIR)) {
            New-Item -ItemType Directory -Path $BACKUP_DIR -Force | Out-Null
        }

        # Create backup file (only when original value exists)
        if ($originalGuid) {
            $backupFile = "$BACKUP_DIR\MachineGuid_$(Get-Date -Format 'yyyyMMdd_HHmmss').reg"
            $backupResult = Start-Process "reg.exe" -ArgumentList "export", "`"HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography`"", "`"$backupFile`"" -NoNewWindow -Wait -PassThru
            
            if ($backupResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Info]$NC Registry key backed up to: $backupFile"
            } else {
                Write-Host "$YELLOW[Warning]$NC Backup creation failed, continuing execution..."
            }
        }

        # Generate new GUID
        $newGuid = [System.Guid]::NewGuid().ToString()

        # Update or create registry value
        Set-ItemProperty -Path $registryPath -Name MachineGuid -Value $newGuid -Force -ErrorAction Stop
        
        # Verify update
        $verifyGuid = (Get-ItemProperty -Path $registryPath -Name MachineGuid -ErrorAction Stop).MachineGuid
        if ($verifyGuid -ne $newGuid) {
            throw "Registry verification failed: Updated value ($verifyGuid) does not match expected value ($newGuid)"
        }

        Write-Host "$GREEN[Info]$NC Registry update successful:"
        Write-Host "HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Cryptography"
        Write-Host "    MachineGuid    REG_SZ    $newGuid"
        return $true
    }
    catch {
        Write-Host "$RED[Error]$NC Registry operation failed: $($_.Exception.Message)"
        
        # Try to restore backup (if it exists)
        if (($backupFile -ne $null) -and (Test-Path $backupFile)) {
            Write-Host "$YELLOW[Recover]$NC Restoring from backup..."
            $restoreResult = Start-Process "reg.exe" -ArgumentList "import", "`"$backupFile`"" -NoNewWindow -Wait -PassThru
            
            if ($restoreResult.ExitCode -eq 0) {
                Write-Host "$GREEN[Recovery Successful]$NC Original registry value has been restored"
            } else {
                Write-Host "$RED[Error]$NC Recovery failed, please manually import backup file: $backupFile"
            }
        } else {
            Write-Host "$YELLOW[Warning]$NC No backup file found or backup creation failed, cannot automatically recover"
        }
        return $false
    }
}

# Create or update configuration file
Write-Host "$GREEN[Info]$NC Updating configuration..."

try {
    # Check if configuration file exists
    if (-not (Test-Path $STORAGE_FILE)) {
        Write-Host "$RED[Error]$NC Configuration file not found: $STORAGE_FILE"
        Write-Host "$YELLOW[Tip]$NC Please install and run Cursor once before using this script"
        Read-Host "Press Enter to exit"
        exit 1
    }

    # Read existing configuration file
    try {
        $originalContent = Get-Content $STORAGE_FILE -Raw -Encoding UTF8
        
        # Convert JSON string to PowerShell object
        $config = $originalContent | ConvertFrom-Json 

        # Backup current values
        $oldValues = @{
            'machineId' = $config.'telemetry.machineId'
            'macMachineId' = $config.'telemetry.macMachineId'
            'devDeviceId' = $config.'telemetry.devDeviceId'
            'sqmId' = $config.'telemetry.sqmId'
        }

        # Update specific values
        $config.'telemetry.machineId' = $MACHINE_ID
        $config.'telemetry.macMachineId' = $MAC_MACHINE_ID
        $config.'telemetry.devDeviceId' = $UUID
        $config.'telemetry.sqmId' = $SQM_ID

        # Convert updated object back to JSON and save
        $updatedJson = $config | ConvertTo-Json -Depth 10
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($STORAGE_FILE), 
            $updatedJson, 
            [System.Text.Encoding]::UTF8
        )
        Write-Host "$GREEN[Info]$NC Configuration file updated successfully"
    } catch {
        # If an error occurs, try to restore original content
        if ($originalContent) {
            [System.IO.File]::WriteAllText(
                [System.IO.Path]::GetFullPath($STORAGE_FILE), 
                $originalContent, 
                [System.Text.Encoding]::UTF8
            )
        }
        throw "JSON processing failed: $_"
    }
    # Execute update MachineGuid directly, without asking
    Update-MachineGuid
    # Display results
    Write-Host ""
    Write-Host "$GREEN[Info]$NC Configuration updated:"
    Write-Host "$BLUE[Debug]$NC machineId: $MACHINE_ID"
    Write-Host "$BLUE[Debug]$NC macMachineId: $MAC_MACHINE_ID"
    Write-Host "$BLUE[Debug]$NC devDeviceId: $UUID"
    Write-Host "$BLUE[Debug]$NC sqmId: $SQM_ID"

    # Display file tree structure
    Write-Host ""
    Write-Host "$GREEN[Info]$NC File structure:"
    Write-Host "$BLUE$env:APPDATA\Cursor\User$NC"
    Write-Host "├── globalStorage"
    Write-Host "│   ├── storage.json (modified)"
    Write-Host "│   └── backups"

    # List backup files
    $backupFiles = Get-ChildItem "$BACKUP_DIR\*" -ErrorAction SilentlyContinue
    if ($backupFiles) {
        foreach ($file in $backupFiles) {
            Write-Host "│       └── $($file.Name)"
        }
    } else {
        Write-Host "│       └── (empty)"
    }

    # Display public account information
    Write-Host ""
    Write-Host "$GREEN================================$NC"
    Write-Host "$YELLOW  Follow public account [JianBingGuoZiJuanAI] to discuss more Cursor tips and AI knowledge (script is free, follow the public account to join the group for more tips and masters)  $NC"
    Write-Host "$GREEN================================$NC"
    Write-Host ""
    Write-Host "$GREEN[Info]$NC Please restart Cursor to apply new configuration"
    Write-Host ""

    # Ask whether to disable automatic updates
    Write-Host ""
    Write-Host "$YELLOW[Question]$NC Do you want to disable Cursor automatic update feature?"
    Write-Host "0) No - Keep default settings (press Enter)"
    Write-Host "1) Yes - Disable automatic updates"
    $choice = Read-Host "Please enter option (0)"

    if ($choice -eq "1") {
        Write-Host ""
        Write-Host "$GREEN[Info]$NC Processing automatic updates..."
        $updaterPath = "$env:LOCALAPPDATA\cursor-updater"

        # Define manual setup tutorial
        function Show-ManualGuide {
            Write-Host ""
            Write-Host "$YELLOW[Warning]$NC Automatic setup failed, please try manual operation:"
            Write-Host "$YELLOWManual steps to disable updates:$NC"
            Write-Host "1. Open PowerShell as administrator"
            Write-Host "2. Copy and paste the following commands:"
            Write-Host "$BLUECommand 1 - Delete existing directory (if exists):$NC"
            Write-Host "Remove-Item -Path `"$updaterPath`" -Force -Recurse -ErrorAction SilentlyContinue"
            Write-Host ""
            Write-Host "$BLUECommand 2 - Create blocking file:$NC"
            Write-Host "New-Item -Path `"$updaterPath`" -ItemType File -Force | Out-Null"
            Write-Host ""
            Write-Host "$BLUECommand 3 - Set read-only property:$NC"
            Write-Host "Set-ItemProperty -Path `"$updaterPath`" -Name IsReadOnly -Value `$true"
            Write-Host ""
            Write-Host "$BLUECommand 4 - Set permissions (optional):$NC"
            Write-Host "icacls `"$updaterPath`" /inheritance:r /grant:r `"`$($env:USERNAME):(R)`""
            Write-Host ""
            Write-Host "$YELLOWVerification method:$NC"
            Write-Host "1. Run command: Get-ItemProperty `"$updaterPath`""
            Write-Host "2. Confirm IsReadOnly property is True"
            Write-Host "3. Run command: icacls `"$updaterPath`""
            Write-Host "4. Confirm only read permissions are present"
            Write-Host ""
            Write-Host "$YELLOW[Tip]$NC Restart Cursor after completion"
        }

        try {
            # Check if cursor-updater exists
            if (Test-Path $updaterPath) {
                # If it's a file, it means update blocking has already been created
                if ((Get-Item $updaterPath) -is [System.IO.FileInfo]) {
                    Write-Host "$GREEN[Info]$NC Update blocking file already created, no need to block again"
                    return
                }
                # If it's a directory, try to delete it
                else {
                    try {
                        Remove-Item -Path $updaterPath -Force -Recurse -ErrorAction Stop
                        Write-Host "$GREEN[Info]$NC Successfully deleted cursor-updater directory"
                    }
                    catch {
                        Write-Host "$RED[Error]$NC Failed to delete cursor-updater directory"
                        Show-ManualGuide
                        return
                    }
                }
            }

            # Create blocking file
            try {
                New-Item -Path $updaterPath -ItemType File -Force -ErrorAction Stop | Out-Null
                Write-Host "$GREEN[Info]$NC Successfully created blocking file"
            }
            catch {
                Write-Host "$RED[Error]$NC Failed to create blocking file"
                Show-ManualGuide
                return
            }

            # Set file permissions
            try {
                # Set read-only property
                Set-ItemProperty -Path $updaterPath -Name IsReadOnly -Value $true -ErrorAction Stop
                
                # Use icacls to set permissions
                $result = Start-Process "icacls.exe" -ArgumentList "`"$updaterPath`" /inheritance:r /grant:r `"$($env:USERNAME):(R)`"" -Wait -NoNewWindow -PassThru
                if ($result.ExitCode -ne 0) {
                    throw "icacls command failed"
                }
                
                Write-Host "$GREEN[Info]$NC Successfully set file permissions"
            }
            catch {
                Write-Host "$RED[Error]$NC Failed to set file permissions"
                Show-ManualGuide
                return
            }

            # Verify settings
            try {
                $fileInfo = Get-ItemProperty $updaterPath
                if (-not $fileInfo.IsReadOnly) {
                    Write-Host "$RED[Error]$NC Verification failed: File permissions settings may not have taken effect"
                    Show-ManualGuide
                    return
                }
            }
            catch {
                Write-Host "$RED[Error]$NC Failed to verify settings"
                Show-ManualGuide
                return
            }

            Write-Host "$GREEN[Info]$NC Successfully disabled automatic updates"
        }
        catch {
            Write-Host "$RED[Error]$NC Unknown error occurred: $_"
            Show-ManualGuide
        }
    }
    else {
        Write-Host "$GREEN[Info]$NC Keeping default settings, no changes made"
    }

    # Retain valid registry updates
    Update-MachineGuid

} catch {
    Write-Host "$RED[Error]$NC Main operation failed: $_"
    Write-Host "$YELLOW[Attempt]$NC Using alternative method..."
    
    try {
        # Alternative method: Use Add-Content
        $tempFile = [System.IO.Path]::GetTempFileName()
        $config | ConvertTo-Json | Set-Content -Path $tempFile -Encoding UTF8
        Copy-Item -Path $tempFile -Destination $STORAGE_FILE -Force
        Remove-Item -Path $tempFile
        Write-Host "$GREEN[Info]$NC Successfully wrote configuration using alternative method"
    } catch {
        Write-Host "$RED[Error]$NC All attempts failed"
        Write-Host "Error details: $_"
        Write-Host "Target file: $STORAGE_FILE"
        Write-Host "Please ensure you have sufficient permissions to access the file"
        Read-Host "Press Enter to exit"
        exit 1
    }
}

Write-Host ""
Read-Host "Press Enter to exit"
exit 0

# Modified in file writing section
function Write-ConfigFile {
    param($config, $filePath)
    
    try {
        # Use UTF8 without BOM encoding
        $utf8NoBom = New-Object System.Text.UTF8Encoding $false
        $jsonContent = $config | ConvertTo-Json -Depth 10
        
        # Unify using LF line endings
        $jsonContent = $jsonContent.Replace("`r`n", "`n")
        
        [System.IO.File]::WriteAllText(
            [System.IO.Path]::GetFullPath($filePath),
            $jsonContent,
            $utf8NoBom
        )
        
        Write-Host "$GREEN[Info]$NC Successfully wrote configuration file (UTF8 no BOM)"
    }
    catch {
        throw "Failed to write configuration file: $_"
    }
}

# Get and display version information
$cursorVersion = Get-CursorVersion
Write-Host ""
if ($cursorVersion) {
    Write-Host "$GREEN[Info]$NC Detected Cursor version: $cursorVersion, continuing execution..."
} else {
    Write-Host "$YELLOW[Warning]$NC Unable to detect version, will continue execution..."
} 