#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

ORACLE_BASE="/u01/app/oracle"
VEEAM_PLUGIN_DIR="/opt/veeam/VeeamPluginforOracleRMAN"
LOG_FILE="/tmp/prepare_oracle_veeam_$(date +%Y%m%d_%H%M%S).log"

print_msg() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a $LOG_FILE
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a $LOG_FILE
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a $LOG_FILE
}

print_info() {
    echo -e "${CYAN}[INFO]${NC} $1" | tee -a $LOG_FILE
}

print_header() {
    echo -e "${BLUE}===============================================${NC}" | tee -a $LOG_FILE
    echo -e "${BLUE}  $1${NC}" | tee -a $LOG_FILE
    echo -e "${BLUE}===============================================${NC}" | tee -a $LOG_FILE
}

check_oracle_user() {
    if [[ $(whoami) != "oracle" ]]; then
        print_error "This script must be run as oracle user"
        print_msg "Current user: $(whoami)"
        exit 1
    fi
    print_msg "Running as user: oracle"
}

collect_information() {
    print_header "ORACLE PREPARATION FOR VEEAM EXPLORER"
    echo ""
    
    read -p "Enter Oracle SID (e.g. AUSTIN): " ORACLE_SID
    while [[ -z "$ORACLE_SID" ]]; do
        print_error "SID cannot be empty"
        read -p "Enter Oracle SID: " ORACLE_SID
    done
    
    existing_processes=$(ps -ef | grep "pmon_${ORACLE_SID}$" | grep -v grep | wc -l)
    if [[ $existing_processes -gt 0 ]]; then
        print_warning "An active instance already exists with SID: ${ORACLE_SID}"
        echo "Processes found:"
        ps -ef | grep "ora_.*_${ORACLE_SID}$" | grep -v grep
        read -p "Do you want to continue and shut down this instance? (y/n) [n]: " continue_sid
        if [[ "${continue_sid:-n}" != "y" ]]; then
            print_msg "Operation cancelled"
            exit 0
        fi
    fi
    
    export ORACLE_SID
    
    echo ""
    echo "Detecting installed Oracle versions..."
    echo ""
    
    ORACLE_HOMES=()
    if [[ -d "${ORACLE_BASE}/product" ]]; then
        while IFS= read -r -d '' oracle_home; do
            if [[ -f "${oracle_home}/bin/oracle" ]]; then
                ORACLE_HOMES+=("$oracle_home")
            fi
        done < <(find "${ORACLE_BASE}/product" -name "dbhome_*" -type d -print0 2>/dev/null)
    fi
    
    if [[ ${#ORACLE_HOMES[@]} -eq 0 ]]; then
        print_error "No Oracle installations found"
        read -p "Enter the complete Oracle Home path: " ORACLE_HOME
    elif [[ ${#ORACLE_HOMES[@]} -eq 1 ]]; then
        ORACLE_HOME="${ORACLE_HOMES[0]}"
        print_msg "Oracle Home detected: $ORACLE_HOME"
    else
        echo "Oracle Homes found:"
        for i in "${!ORACLE_HOMES[@]}"; do
            version=$(echo "${ORACLE_HOMES[$i]}" | grep -oP '\d+\.\d+\.\d+' | head -1)
            echo "$((i+1)). ${ORACLE_HOMES[$i]} [$version]"
        done
        echo ""
        read -p "Select Oracle Home (1-${#ORACLE_HOMES[@]}): " home_choice
        
        if [[ $home_choice -ge 1 && $home_choice -le ${#ORACLE_HOMES[@]} ]]; then
            ORACLE_HOME="${ORACLE_HOMES[$((home_choice-1))]}"
        else
            print_error "Invalid selection"
            read -p "Enter the complete Oracle Home path: " ORACLE_HOME
        fi
    fi
    
    ORACLE_VERSION=$(echo "$ORACLE_HOME" | grep -oP '\d+\.\d+\.\d+' | head -1)
    if [[ -z "$ORACLE_VERSION" ]]; then
        read -p "Could not detect version. Enter version (e.g. 19.0.0): " ORACLE_VERSION
    fi
    
    export ORACLE_HOME
    export PATH=$ORACLE_HOME/bin:$PATH
    
    if [[ ! -f "$ORACLE_HOME/bin/oracle" ]]; then
        print_error "Invalid Oracle Home: $ORACLE_HOME"
        print_error "Oracle executable not found"
        exit 1
    fi
    
    print_msg "Selected Oracle Home: $ORACLE_HOME"
    print_msg "Oracle Version: $ORACLE_VERSION"
    
    echo ""
    read -p "Enter the original database DBID: " DBID
    while ! [[ "$DBID" =~ ^[0-9]+$ ]]; do
        print_error "DBID must be a valid number"
        read -p "Enter the original DBID: " DBID
    done
    
    echo ""
    echo "Select a password for SYS user:"
    echo "1. Welcome#123_DB"
    echo "2. ${ORACLE_SID}\$2025_Db"
    echo "3. Veeam@Recovery_19c"
    echo "4. Oracle#Restore_2025"
    echo "5. Enter custom password"
    read -p "Select an option (1-5) [1]: " pwd_choice
    
    case ${pwd_choice:-1} in
        1) SYS_PASSWORD="Welcome#123_DB" ;;
        2) SYS_PASSWORD="${ORACLE_SID}\$2025_Db" ;;
        3) SYS_PASSWORD="Veeam@Recovery_19c" ;;
        4) SYS_PASSWORD="Oracle#Restore_2025" ;;
        5) 
            echo ""
            echo "Password requirements:"
            echo "- Minimum 8 characters"
            echo "- At least 1 uppercase, 1 lowercase, 1 number"
            echo "- At least 1 special character (@#$%^&*_+=)"
            read -s -p "Enter password: " SYS_PASSWORD
            echo ""
            ;;
        *) SYS_PASSWORD="Welcome#123_DB" ;;
    esac
    
    echo ""
    read -p "Memory size for instance (e.g. 2G, 4G) [2G]: " MEMORY_SIZE
    MEMORY_SIZE=${MEMORY_SIZE:-2G}
    
    echo ""
    print_header "CONFIRM CONFIGURATION"
    echo "Oracle SID:      $ORACLE_SID"
    echo "Oracle Home:     $ORACLE_HOME"
    echo "Oracle Version:  $ORACLE_VERSION"
    echo "Original DBID:   $DBID"
    echo "SYS Password:    ${SYS_PASSWORD:0:3}***"
    echo "Memory Target:   $MEMORY_SIZE"
    echo "Log File:        $LOG_FILE"
    echo ""
    
    read -p "Is the information correct? (y/n) [y]: " confirm
    if [[ "${confirm:-y}" != "y" ]]; then
        print_msg "Operation cancelled by user"
        exit 0
    fi
}

create_directory_structure() {
    print_header "CREATING DIRECTORY STRUCTURE"
    
    directories=(
        "${ORACLE_BASE}/admin/${ORACLE_SID}/adump"
        "${ORACLE_BASE}/admin/${ORACLE_SID}/pfile"
        "${ORACLE_BASE}/admin/${ORACLE_SID}/scripts"
        "${ORACLE_BASE}/oradata/${ORACLE_SID}"
        "${ORACLE_BASE}/fast_recovery_area/${ORACLE_SID}"
    )
    
    for dir in "${directories[@]}"; do
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir"
            print_msg "Directory created: $dir"
        else
            print_warning "Directory already exists: $dir"
        fi
    done
}

create_initial_initora() {
    print_header "CREATING INITIAL PARAMETER FILE"
    
    INIT_FILE="${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora"
    
    if [[ -f "$INIT_FILE" ]]; then
        cp "$INIT_FILE" "${INIT_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
        print_warning "Backup created for existing init.ora"
    fi
    
    cat > "$INIT_FILE" << EOF
db_name=${ORACLE_SID}
db_block_size=8192
compatible=${ORACLE_VERSION}
memory_target=${MEMORY_SIZE}
memory_max_target=${MEMORY_SIZE}
processes=300
sessions=500
audit_file_dest='${ORACLE_BASE}/admin/${ORACLE_SID}/adump'
diagnostic_dest='${ORACLE_BASE}'
db_recovery_file_dest='${ORACLE_BASE}/fast_recovery_area'
db_recovery_file_dest_size=10G
nls_language='AMERICAN'
nls_territory='AMERICA'
nls_date_format='DD-MON-RR'
undo_tablespace='UNDOTBS1'
open_cursors=300
db_domain=''
remote_login_passwordfile='EXCLUSIVE'
EOF

    print_msg "File init${ORACLE_SID}.ora created"
}

create_password_file() {
    print_header "CREATING PASSWORD FILE"
    
    PWD_FILE="${ORACLE_HOME}/dbs/orapw${ORACLE_SID}"
    
    if [[ -f "$PWD_FILE" ]]; then
        rm -f "$PWD_FILE"
        print_warning "Previous password file removed"
    fi
    
    orapwd file="$PWD_FILE" password="$SYS_PASSWORD" entries=10 force=y format=12
    
    if [[ $? -eq 0 ]]; then
        print_msg "Password file created successfully"
        
        INFO_FILE="${ORACLE_HOME}/dbs/.${ORACLE_SID}_info.txt"
        echo "Oracle Database Recovery Information" > "$INFO_FILE"
        echo "====================================" >> "$INFO_FILE"
        echo "Created: $(date)" >> "$INFO_FILE"
        echo "SID: $ORACLE_SID" >> "$INFO_FILE"
        echo "DBID: $DBID" >> "$INFO_FILE"
        echo "SYS Password: $SYS_PASSWORD" >> "$INFO_FILE"
        echo "Oracle Home: $ORACLE_HOME" >> "$INFO_FILE"
        chmod 600 "$INFO_FILE"
        
        print_info "Information saved in: $INFO_FILE"
    else
        print_error "Error creating password file"
        exit 1
    fi
}

setup_environment() {
    print_header "CONFIGURING ENVIRONMENT VARIABLES"
    
    PROFILE_FILE="${HOME}/.bash_profile"
    
    cp "$PROFILE_FILE" "${PROFILE_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
    
    sed -i "/# Oracle Settings for ${ORACLE_SID}/,/# End Oracle Settings for ${ORACLE_SID}/d" "$PROFILE_FILE"
    
    cat >> "$PROFILE_FILE" << EOF

# Oracle Settings for ${ORACLE_SID}
export ORACLE_SID=${ORACLE_SID}
export ORACLE_BASE=${ORACLE_BASE}
export ORACLE_HOME=${ORACLE_HOME}
export PATH=\$ORACLE_HOME/bin:\$PATH
export LD_LIBRARY_PATH=\$ORACLE_HOME/lib:\$LD_LIBRARY_PATH
export NLS_LANG=AMERICAN_AMERICA.AL32UTF8
# End Oracle Settings for ${ORACLE_SID}
EOF

    print_msg "Environment variables configured in .bash_profile"
}

shutdown_instance() {
    print_header "VERIFYING INSTANCE STATUS"
    
    sqlplus -s / as sysdba << EOF > /dev/null 2>&1
shutdown abort;
exit;
EOF
    
    sleep 3
    
    pmon_count=$(ps -ef | grep "pmon_${ORACLE_SID}" | grep -v grep | wc -l)
    
    if [[ $pmon_count -gt 0 ]]; then
        print_error "Oracle processes still active for ${ORACLE_SID}"
        ps -ef | grep "${ORACLE_SID}" | grep -v grep
        print_msg "Attempting to terminate processes..."
        
        ps -ef | grep "ora_.*_${ORACLE_SID}" | grep -v grep | awk '{print $2}' | xargs -r kill -9 2>/dev/null
        sleep 3
        
        pmon_count=$(ps -ef | grep "pmon_${ORACLE_SID}" | grep -v grep | wc -l)
        if [[ $pmon_count -gt 0 ]]; then
            print_error "Could not terminate all processes"
            print_msg "Execute manually: kill -9 \$(ps -ef | grep ${ORACLE_SID} | grep -v grep | awk '{print \$2}')"
            exit 1
        fi
    fi
    
    print_msg "Instance ${ORACLE_SID} shut down successfully"
}

setup_listener() {
    print_header "CONFIGURING ORACLE LISTENER"
    
    LISTENER_FILE="${ORACLE_HOME}/network/admin/listener.ora"
    TNSNAMES_FILE="${ORACLE_HOME}/network/admin/tnsnames.ora"
    
    mkdir -p "${ORACLE_HOME}/network/admin"
    
    cat > "$LISTENER_FILE" << EOF
LISTENER =
  (DESCRIPTION_LIST =
    (DESCRIPTION =
      (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    )
  )

SID_LIST_LISTENER =
  (SID_LIST =
    (SID_DESC =
      (GLOBAL_DBNAME = ${ORACLE_SID})
      (ORACLE_HOME = ${ORACLE_HOME})
      (SID_NAME = ${ORACLE_SID})
    )
  )

ADR_BASE_LISTENER = ${ORACLE_BASE}
EOF

    cat > "$TNSNAMES_FILE" << EOF
${ORACLE_SID} =
  (DESCRIPTION =
    (ADDRESS = (PROTOCOL = TCP)(HOST = $(hostname))(PORT = 1521))
    (CONNECT_DATA =
      (SERVER = DEDICATED)
      (SERVICE_NAME = ${ORACLE_SID})
    )
  )
EOF

    lsnrctl stop 2>/dev/null || true
    sleep 2
    lsnrctl start
    
    if [[ $? -eq 0 ]]; then
        print_msg "Listener configured and started"
    else
        print_warning "Could not start listener (not critical)"
    fi
}

configure_veeam_plugin() {
    print_header "CONFIGURING VEEAM PLUGIN"
    
    if [[ ! -d "$VEEAM_PLUGIN_DIR" ]]; then
        print_error "Veeam Plugin not installed in $VEEAM_PLUGIN_DIR"
        print_warning "You will need to configure it manually later"
        return 1
    fi
    
    cd "$VEEAM_PLUGIN_DIR"
    
    print_info "Configure authentication to access backups"
    print_msg "Options: 1=Credentials, 2=Recovery Token"
    
    ./OracleRMANConfigTool --set-auth-data-for-restore
    
    if [[ $? -eq 0 ]]; then
        print_msg "Authentication configured"
        echo ""
        
        print_info "To get the Backup ID, run the following command:"
        echo ""
        echo "cd $VEEAM_PLUGIN_DIR"
        echo "./OracleRMANConfigTool --get-backup-for-restore"
        echo ""
        print_msg "Note the Backup ID shown (format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
        echo ""
    else
        print_error "Error configuring authentication"
        return 1
    fi
}

restore_control_file() {
    print_header "RESTORE CONTROL FILE FROM VEEAM"
    
    echo ""
    read -p "Do you want to restore the control file now? (y/n) [y]: " restore_cf
    
    if [[ "${restore_cf:-y}" != "y" ]]; then
        print_warning "Skipping control file restore"
        print_info "You must restore it manually before using Veeam Explorer"
        return 0
    fi
    
    echo ""
    read -p "Do you already have the Backup ID? (y/n) [n]: " has_backup_id
    
    if [[ "${has_backup_id:-n}" == "n" ]]; then
        print_info "Run the following command to get the Backup ID:"
        echo ""
        echo "cd $VEEAM_PLUGIN_DIR"
        echo "./OracleRMANConfigTool --get-backup-for-restore"
        echo ""
        print_msg "Select the backup and note the Backup ID shown"
        echo ""
        
        read -p "Do you want to run the command now? (y/n) [y]: " exec_now
        if [[ "${exec_now:-y}" == "y" ]]; then
            cd "$VEEAM_PLUGIN_DIR"
            ./OracleRMANConfigTool --get-backup-for-restore
            echo ""
        fi
    fi
    
    echo ""
    echo "Enter the Backup ID in format: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
    read -p "Backup ID: " BACKUP_ID
    
    if ! [[ "$BACKUP_ID" =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]]; then
        print_error "Invalid Backup ID format"
        print_info "Expected format: babbb9c8-9684-48db-b9b8-ff85bfd4868f"
        return 1
    fi
    
    print_msg "Updating init.ora with control files location..."
    INIT_FILE="${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora"
    
    if ! grep -q "^control_files" "$INIT_FILE"; then
        echo "" >> "$INIT_FILE"
        echo "control_files='${ORACLE_BASE}/oradata/${ORACLE_SID}/control01.ctl','${ORACLE_BASE}/oradata/${ORACLE_SID}/control02.ctl'" >> "$INIT_FILE"
    fi
    
    echo ""
    echo "Do you know the exact control file backup name?"
    echo "(Typical format: c-${DBID}-YYYYMMDD-XX)"
    read -p "Do you know the name? (y/n) [n]: " knows_name
    
    if [[ "${knows_name:-n}" == "y" ]]; then
        read -p "Enter the control file name: " CF_NAME
        
        print_msg "Restoring control file: $CF_NAME"
        
        rman target / << EOF | tee -a $LOG_FILE
STARTUP NOMOUNT;
SET DBID=$DBID;

RUN {
    ALLOCATE CHANNEL ch1 TYPE sbt_tape PARMS 
    'SBT_LIBRARY=${VEEAM_PLUGIN_DIR}/libOracleRMANPlugin.so';
    
    SEND 'srcBackup=$BACKUP_ID';
    
    RESTORE CONTROLFILE FROM '$CF_NAME';
    
    ALTER DATABASE MOUNT;
}

SELECT name, dbid FROM v\$database;
SHUTDOWN IMMEDIATE;
EXIT;
EOF
    else
        print_msg "Attempting to restore control file from AUTOBACKUP..."
        print_warning "If this fails, you will need the exact control file name"
        
        rman target / << EOF | tee -a $LOG_FILE
STARTUP NOMOUNT;
SET DBID=$DBID;

RUN {
    ALLOCATE CHANNEL ch1 TYPE sbt_tape PARMS 
    'SBT_LIBRARY=${VEEAM_PLUGIN_DIR}/libOracleRMANPlugin.so';
    
    SEND 'srcBackup=$BACKUP_ID';
    
    SET CONTROLFILE AUTOBACKUP FORMAT FOR DEVICE TYPE 'SBT_TAPE' TO '%F_RMAN_AUTOBACKUP.vab';
    
    RESTORE CONTROLFILE FROM AUTOBACKUP;
    
    ALTER DATABASE MOUNT;
}

SELECT name, dbid FROM v\$database;
SHUTDOWN IMMEDIATE;
EXIT;
EOF
    fi
    
    echo ""
    if [[ -f "${ORACLE_BASE}/oradata/${ORACLE_SID}/control01.ctl" ]]; then
        print_msg "✓ Control file restored successfully"
        ls -lh ${ORACLE_BASE}/oradata/${ORACLE_SID}/control*.ctl
    else
        print_error "✗ Control file not restored"
        print_info "You must restore it manually"
        echo ""
        print_info "Command to list available backups:"
        echo "rman target /"
        echo "RMAN> STARTUP NOMOUNT;"
        echo "RMAN> SET DBID=$DBID;"
        echo "RMAN> RUN {"
        echo "        ALLOCATE CHANNEL ch1 TYPE sbt_tape PARMS"
        echo "        'SBT_LIBRARY=${VEEAM_PLUGIN_DIR}/libOracleRMANPlugin.so';"
        echo "        SEND 'srcBackup=$BACKUP_ID';"
        echo "        LIST BACKUP OF CONTROLFILE;"
        echo "      }"
    fi
}

create_spfile() {
    print_header "CREATE SPFILE"
    
    if [[ ! -f "${ORACLE_BASE}/oradata/${ORACLE_SID}/control01.ctl" ]]; then
        print_warning "No control files found, skipping SPFILE creation"
        return 0
    fi
    
    print_msg "Creating SPFILE from PFILE..."
    
    sqlplus -s / as sysdba << EOF
STARTUP NOMOUNT;
CREATE SPFILE FROM PFILE;
SHUTDOWN IMMEDIATE;

STARTUP NOMOUNT;
SHOW PARAMETER spfile;
SHUTDOWN IMMEDIATE;
EXIT;
EOF
    
    if [[ $? -eq 0 ]]; then
        print_msg "✓ SPFILE created successfully"
        
        INIT_FILE="${ORACLE_HOME}/dbs/init${ORACLE_SID}.ora"
        cp "$INIT_FILE" "${INIT_FILE}.full.bak"
        echo "SPFILE='${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora'" > "$INIT_FILE"
        
        print_msg "init.ora updated to use SPFILE"
    else
        print_error "Error creating SPFILE"
    fi
}

create_utility_scripts() {
    print_header "CREATING UTILITY SCRIPTS"
    
    SCRIPTS_DIR="${ORACLE_BASE}/admin/${ORACLE_SID}/scripts"
    
    cat > "${SCRIPTS_DIR}/verify_${ORACLE_SID}.sh" << 'EOF'
#!/bin/bash

export ORACLE_SID=_ORACLE_SID_
export ORACLE_HOME=_ORACLE_HOME_
export PATH=$ORACLE_HOME/bin:$PATH

echo "======================================"
echo " Verification: $ORACLE_SID"
echo "======================================"
echo ""

echo "1. Configuration files:"
ls -la $ORACLE_HOME/dbs/*${ORACLE_SID}* 2>/dev/null | grep -E "(init|spfile|orapw)"
echo ""

echo "2. Control Files:"
ls -la /u01/app/oracle/oradata/${ORACLE_SID}/control*.ctl 2>/dev/null
echo ""

echo "3. Instance status:"
sqlplus -s / as sysdba << EOSQL 2>/dev/null
set heading off feedback off
select 'Status: SHUTDOWN' from dual where 1=2;
exit;
EOSQL
echo ""

echo "4. Saved information:"
if [[ -f "$ORACLE_HOME/dbs/.${ORACLE_SID}_info.txt" ]]; then
    grep -E "DBID:|SYS Password:" "$ORACLE_HOME/dbs/.${ORACLE_SID}_info.txt"
fi
echo ""
EOF

    sed -i "s/_ORACLE_SID_/${ORACLE_SID}/g" "${SCRIPTS_DIR}/verify_${ORACLE_SID}.sh"
    sed -i "s|_ORACLE_HOME_|${ORACLE_HOME}|g" "${SCRIPTS_DIR}/verify_${ORACLE_SID}.sh"
    chmod +x "${SCRIPTS_DIR}/verify_${ORACLE_SID}.sh"
    
    print_msg "Verification script created: ${SCRIPTS_DIR}/verify_${ORACLE_SID}.sh"
}

show_final_summary() {
    print_header "PREPARATION COMPLETED"
    
    echo ""
    echo "Database ${ORACLE_SID} is prepared for Veeam Explorer"
    echo ""
    echo "Important information:"
    echo "========================"
    echo "Oracle SID:      ${ORACLE_SID}"
    echo "Oracle Home:     ${ORACLE_HOME}"
    echo "Original DBID:   ${DBID}"
    echo "SYS Password:    ${SYS_PASSWORD}"
    echo "Memory Target:   ${MEMORY_SIZE}"
    echo ""
    
    echo "Component status:"
    echo "======================"
    
    if [[ -f "${ORACLE_HOME}/dbs/orapw${ORACLE_SID}" ]]; then
        echo "✓ Password file created"
    else
        echo "✗ Password file NOT found"
    fi
    
    if [[ -f "${ORACLE_HOME}/dbs/spfile${ORACLE_SID}.ora" ]]; then
        echo "✓ SPFILE created"
    else
        echo "✗ SPFILE NOT created (using PFILE)"
    fi
    
    if [[ -f "${ORACLE_BASE}/oradata/${ORACLE_SID}/control01.ctl" ]]; then
        echo "✓ Control files restored"
    else
        echo "✗ Control files NOT restored"
        echo ""
        echo "  IMPORTANT: You must restore the control file before using Veeam Explorer"
        echo "  Use the following RMAN command:"
        echo ""
        echo "  rman target /"
        echo "  RMAN> STARTUP NOMOUNT;"
        echo "  RMAN> SET DBID=${DBID};"
        echo "  RMAN> RUN {"
        echo "          ALLOCATE CHANNEL ch1 TYPE sbt_tape PARMS"
        echo "          'SBT_LIBRARY=${VEEAM_PLUGIN_DIR}/libOracleRMANPlugin.so';"
        echo "          SEND 'srcBackup=YOUR-BACKUP-ID';"
        echo "          RESTORE CONTROLFILE FROM 'control-file-name';"
        echo "        }"
    fi
    
    echo ""
    echo "In Veeam Explorer for Oracle:"
    echo "=============================="
    echo "1. Right-click on backup → 'Restore application items' → 'Oracle databases'"
    echo "2. In Target Database configure:"
    echo "   - Oracle home: ${ORACLE_HOME}"
    echo "   - Database SID: ${ORACLE_SID}"
    echo "   - Database state: 'Database is shut down'"
    echo "   - Credentials: oracle user or SYS/${SYS_PASSWORD}"
    echo ""
    echo "Reference files:"
    echo "======================="
    echo "- Script log: $LOG_FILE"
    echo "- Saved information: ${ORACLE_HOME}/dbs/.${ORACLE_SID}_info.txt"
    echo "- Verification script: ${ORACLE_BASE}/admin/${ORACLE_SID}/scripts/verify_${ORACLE_SID}.sh"
    echo ""
}

main() {
    clear
    
    check_oracle_user
    
    collect_information
    
    print_msg "Starting preparation..."
    echo ""
    
    create_directory_structure
    create_initial_initora
    create_password_file
    setup_environment
    shutdown_instance
    setup_listener
    
    echo ""
    read -p "Do you want to configure Veeam Plugin now? (y/n) [y]: " config_veeam
    if [[ "${config_veeam:-y}" == "y" ]]; then
        configure_veeam_plugin
    fi
    
    restore_control_file
    
    if [[ -f "${ORACLE_BASE}/oradata/${ORACLE_SID}/control01.ctl" ]]; then
        create_spfile
    fi
    
    create_utility_scripts
    
    show_final_summary
    
    print_msg "Process completed. Check log at: $LOG_FILE"
}

trap 'print_error "Script interrupted"; exit 1' INT TERM

main "$@"