#!/usr/bin/env bash
#
# SAP ASE 16 Docker entrypoint.
# - First run: atomically build the server (srvbuildres + sqllocres + cfg
#   tweaks + user init hooks). A sentinel file is touched only when every
#   step succeeds; on failure, partial state is wiped so the next start
#   retries from scratch.
# - Subsequent runs: start the previously built server, then keep PID 1
#   alive while the dataserver runs.
# - SIGTERM/SIGINT issues an ASE `shutdown` and waits for the dataserver
#   process to exit (with hard-timeout fallback) so `docker stop` does not
#   trigger recovery on the next boot.

export LANG=C
set -eo pipefail

# shellcheck source=/dev/null
. /opt/sap/SYBASE.sh

set -u

SQL_DIR="${SQL_DIR:-/docker-entrypoint-initdb.d}"

ASE_HOST="${ASE_HOST:-localhost}"
ASE_PORT="${ASE_PORT:-5000}"
ASE_DB="${ASE_DB:-master}"

export ASE_DS_NAME="${ASE_DS_NAME:-MYSYBASE}"
export ASE_SA_PASSWORD="${ASE_SA_PASSWORD:-$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 16; echo)}"

export ASE_INSTALL_PATH="${SYBASE}"
export ASE_DATA_PATH="${ASE_DATA_PATH:-${ASE_INSTALL_PATH}/data}"

ASE_CHARSET="${ASE_CHARSET:-utf8}"
ASE_LANGUAGE="${ASE_LANGUAGE:-us_english}"
ASE_SORT_ORDER="${ASE_SORT_ORDER:-binary}"

if [ "${ASE_LANGUAGE}" = "us_english" ]; then
    ASE_LANGUAGE_INSTALL_LIST="us_english"
else
    ASE_LANGUAGE_INSTALL_LIST="us_english,${ASE_LANGUAGE}"
fi

ASE_MAX_MEMORY_MB="${ASE_MAX_MEMORY_MB:-2048}"

WAIT_SEC="${WAIT_SEC:-120}"
SHUTDOWN_WAIT_SEC="${SHUTDOWN_WAIT_SEC:-60}"
SQLLOCRES_WAIT_SEC="${SQLLOCRES_WAIT_SEC:-180}"

ASE_RUN_FILE="${SYBASE}/${SYBASE_ASE}/install/RUN_${ASE_DS_NAME}"
ASE_CFG_FILE="${SYBASE}/${SYBASE_ASE}/${ASE_DS_NAME}.cfg"
ASE_ERROR_LOG="${SYBASE}/${SYBASE_ASE}/install/${ASE_DS_NAME}.log"
ASE_INIT_SENTINEL="${ASE_DATA_PATH}/.ase-initialized"

ASE_DATASERVER_PGREP_PATTERN="dataserver.*-s ?${ASE_DS_NAME}"

log_info()  { echo "[INFO]  $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*"; }
log_warn()  { echo "[WARN]  $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >&2; }
log_error() { echo "[ERROR] $(date -u +'%Y-%m-%dT%H:%M:%SZ') $*" >&2; }

dump_errorlog_tail() {
    if [ -f "${ASE_ERROR_LOG}" ]; then
        log_error "Last 80 lines of ${ASE_ERROR_LOG}:"
        tail -n 80 "${ASE_ERROR_LOG}" >&2 || true
    fi
}

# shellcheck disable=SC2119,SC2120
isql_cmd() {
    isql --retserverror -b -S "${ASE_DS_NAME}" -Usa -P "${ASE_SA_PASSWORD}" \
         -D "${ASE_DB}" -w 1000 "$@"
}

dataserver_running() {
    pgrep -f "${ASE_DATASERVER_PGREP_PATTERN}" >/dev/null 2>&1
}

dataserver_pid() {
    pgrep -f "${ASE_DATASERVER_PGREP_PATTERN}" | head -n 1 || true
}

wait_for_ase_ready() {
    local max_wait="${1:-${WAIT_SEC}}"
    local elapsed=0
    local interval=3

    log_info "Waiting up to ${max_wait}s for ASE to accept connections..."
    while [ "${elapsed}" -lt "${max_wait}" ]; do
        if isql_cmd <<-SQL 
SELECT 1
GO
SQL
        then
            log_info "ASE accepting connections after ${elapsed}s"
            return 0
        fi
        sleep "${interval}"
        elapsed=$(( elapsed + interval ))
    done

    log_error "ASE did not become ready within ${max_wait}s"
    return 1
}

wait_for_dataserver_exit() {
    local max_wait="${1:-${SHUTDOWN_WAIT_SEC}}"
    local elapsed=0
    while dataserver_running; do
        if [ "${elapsed}" -ge "${max_wait}" ]; then
            return 1
        fi
        sleep 1
        elapsed=$(( elapsed + 1 ))
    done
    return 0
}

graceful_shutdown() {
    if ! dataserver_running; then
        log_info "graceful_shutdown: dataserver not running"
        return 0
    fi

    log_info "Issuing ASE 'shutdown'..."
    # `shutdown` severs the client connection while the server is stopping,
    # so a non-zero isql exit here is normal and ignored.
    isql_cmd <<SQL >/dev/null 2>&1 || true
use master
go
shutdown
go
SQL

    if wait_for_dataserver_exit "${SHUTDOWN_WAIT_SEC}"; then
        log_info "Dataserver exited cleanly"
        return 0
    fi

    log_warn "Dataserver did not exit within ${SHUTDOWN_WAIT_SEC}s; trying 'shutdown with nowait'"
    isql_cmd <<SQL >/dev/null 2>&1 || true
use master
go
shutdown with nowait
go
SQL

    if wait_for_dataserver_exit 15; then
        log_info "Dataserver exited after 'shutdown with nowait'"
        return 0
    fi

    log_warn "Forcing dataserver termination via SIGTERM/SIGKILL"
    local pid
    pid="$(dataserver_pid)"
    if [ -n "${pid}" ]; then
        kill -TERM "${pid}" 2>/dev/null || true
        sleep 5
        if dataserver_running; then
            kill -KILL "${pid}" 2>/dev/null || true
        fi
    fi
    wait_for_dataserver_exit 10 || log_error "Dataserver still alive after SIGKILL"
}

TAIL_PID=""

on_terminate() {
    log_info "Received termination signal; shutting down ASE..."
    graceful_shutdown || true
    if [ -n "${TAIL_PID}" ]; then
        kill "${TAIL_PID}" 2>/dev/null || true
    fi
    exit 0
}
trap on_terminate SIGTERM SIGINT

process_init_files() {
    local init_dir="${SQL_DIR}"
    if [ ! -d "${init_dir}" ]; then
        return 0
    fi

    local files
    files="$(find "${init_dir}" -maxdepth 1 -type f \( -name '*.sql' -o -name '*.sh' \) 2>/dev/null | sort || true)"
    if [ -z "${files}" ]; then
        return 0
    fi

    local count
    count="$(echo "${files}" | wc -l)"
    log_info "Processing ${count} init file(s) from ${init_dir}..."

    while IFS= read -r f; do
        [ -z "${f}" ] && continue
        case "${f}" in
            *.sh)
                if [ -x "${f}" ]; then
                    log_info "Running ${f}"
                    if ! "${f}"; then
                        log_error "Init script failed: ${f}"
                        return 1
                    fi
                else
                    log_info "Sourcing ${f}"
                    # shellcheck source=/dev/null
                    if ! . "${f}"; then
                        log_error "Init script failed: ${f}"
                        return 1
                    fi
                fi
                ;;
            *.sql)
                log_info "Running ${f}"
                if ! isql_cmd < "${f}"; then
                    log_error "Init SQL failed: ${f}"
                    return 1
                fi
                ;;
        esac
    done <<< "${files}"
    return 0
}

cleanup_partial_init() {
    log_info "Cleaning up any partial init state under ${ASE_DATA_PATH} and install dir..."
    rm -f \
        "${ASE_DATA_PATH}"/master.dat \
        "${ASE_DATA_PATH}"/sysprocs.dat \
        "${ASE_DATA_PATH}"/sybsysdb.dat \
        "${ASE_DATA_PATH}"/tempdbdev.dat \
        "${ASE_DATA_PATH}"/sybpcidbdev_data.dat \
        "${ASE_RUN_FILE}" \
        "${ASE_CFG_FILE}" \
        "${ASE_CFG_FILE}.bak" \
        "${ASE_ERROR_LOG}" \
        "${SYBASE}/${SYBASE_ASE}/install/RUN_${ASE_DS_NAME}_BS" \
        2>/dev/null || true
}

run_srvbuildres() {
    log_info "Building ASE server '${ASE_DS_NAME}' via srvbuildres..."

    local saved_umask
    saved_umask="$(umask)"
    umask 077

    local res_file
    res_file="$(mktemp /tmp/sap-srvbuild.XXXXXX.res)"

    cat > "${res_file}" <<EOF
sybinit.release_directory: ${ASE_INSTALL_PATH}
sybinit.product: sqlsrv
sqlsrv.server_name: ${ASE_DS_NAME}
sqlsrv.sa_password: ${ASE_SA_PASSWORD}
sqlsrv.new_config: yes
sqlsrv.do_add_server: yes
sqlsrv.network_protocol_list: tcp
sqlsrv.network_hostname_list: ${ASE_HOST}
sqlsrv.network_port_list: ${ASE_PORT}
sqlsrv.application_type: MIXED
sqlsrv.server_page_size: 16k
sqlsrv.force_buildmaster: no
sqlsrv.addl_cmdline_parameters:
sqlsrv.master_device_physical_name: ${ASE_DATA_PATH}/master.dat
sqlsrv.master_device_size: 384
sqlsrv.master_database_size: 300
sqlsrv.errorlog: ${ASE_ERROR_LOG}
sqlsrv.sort_order: ${ASE_SORT_ORDER}
sqlsrv.default_characterset: ${ASE_CHARSET}
sqlsrv.default_language: ${ASE_LANGUAGE}
sqlsrv.do_upgrade: no
sqlsrv.sybsystemprocs_device_physical_name: ${ASE_DATA_PATH}/sysprocs.dat
sqlsrv.sybsystemprocs_device_size: 184
sqlsrv.sybsystemprocs_database_size: 184
sqlsrv.sybsystemdb_device_physical_name: ${ASE_DATA_PATH}/sybsysdb.dat
sqlsrv.sybsystemdb_device_size: 24
sqlsrv.sybsystemdb_database_size: 24
sqlsrv.tempdb_device_physical_name: ${ASE_DATA_PATH}/tempdbdev.dat
sqlsrv.tempdb_device_size: 150
sqlsrv.tempdb_database_size: 150
sqlsrv.default_backup_server: ${ASE_DS_NAME}_BS
sqlsrv.do_configure_pci: no
sqlsrv.do_optimize_config: no
sqlsrv.avail_physical_memory: ${ASE_MAX_MEMORY_MB}
sqlsrv.avail_cpu_num:
EOF

    umask "${saved_umask}"

    local rc=0
    if ! srvbuildres -r "${res_file}" 2>&1; then
        rc=$?
        log_error "srvbuildres exited with code ${rc}"
        rm -f "${res_file}"
        dump_errorlog_tail
        return 1
    fi

    rm -f "${res_file}"

    if [ ! -f "${ASE_RUN_FILE}" ]; then
        log_error "srvbuildres reported success but RUN file missing: ${ASE_RUN_FILE}"
        dump_errorlog_tail
        return 1
    fi

    # srvbuildres leaves the server running on success; verify via isql.
    if ! wait_for_ase_ready "${WAIT_SEC}"; then
        log_error "Server not reachable after srvbuildres"
        dump_errorlog_tail
        return 1
    fi
    return 0
}

run_sqllocres() {
    log_info "Configuring locales / charset via sqllocres..."

    local saved_umask
    saved_umask="$(umask)"
    umask 077

    local res_file
    res_file="$(mktemp /tmp/sap-sqlloc.XXXXXX.res)"

    cat > "${res_file}" <<EOF
sybinit.release_directory: USE_DEFAULT
sqlsrv.server_name: ${ASE_DS_NAME}
sqlsrv.sa_login: sa
sqlsrv.sa_password: ${ASE_SA_PASSWORD}
sqlsrv.default_language: ${ASE_LANGUAGE}
sqlsrv.language_install_list: ${ASE_LANGUAGE_INSTALL_LIST}
sqlsrv.default_characterset: ${ASE_CHARSET}
sqlsrv.characterset_install_list: ${ASE_CHARSET}
sqlsrv.characterset_remove_list: USE_DEFAULT
sqlsrv.sort_order: ${ASE_SORT_ORDER}
EOF

    umask "${saved_umask}"

    local rc=0
    if ! sqllocres -r "${res_file}" 2>&1; then
        rc=$?
        log_warn "sqllocres exited with code ${rc} - continuing"
    fi
    rm -f "${res_file}"

    # sqllocres bounces the server when charset/language changes; allow a
    # longer budget than the cold-start one before declaring failure.
    if ! wait_for_ase_ready "${SQLLOCRES_WAIT_SEC}"; then
        log_error "Server not reachable after sqllocres"
        dump_errorlog_tail
        return 1
    fi
    return 0
}

# Edits to ${ASE_DS_NAME}.cfg MUST happen with the server stopped: ASE
# rewrites this file from in-memory config on graceful shutdown, silently
# overwriting any edits made while it was running.
disable_async_io() {
    log_info "Disabling 'allow sql server async i/o' via sp_configure..."
    isql_cmd <<-SQL
	sp_configure 'allow sql server async i/o', 0
	go
	SQL
    return $?
}
# `startserver` forks the dataserver and returns; PID is recovered via pgrep
# and readiness is confirmed via isql.
start_server() {
    if [ ! -f "${ASE_RUN_FILE}" ]; then
        log_error "RUN file missing: ${ASE_RUN_FILE}"
        return 1
    fi
    if dataserver_running; then
        log_info "Dataserver already running; skipping startserver"
        return 0
    fi

    log_info "Starting ASE via startserver -f ${ASE_RUN_FILE}"
    if ! startserver -f "${ASE_RUN_FILE}" >/dev/null 2>&1; then
        log_error "startserver returned non-zero"
        dump_errorlog_tail
        return 1
    fi
    if ! wait_for_ase_ready "${WAIT_SEC}"; then
        dump_errorlog_tail
        return 1
    fi
    return 0
}

initial_setup() {
    log_info "Performing first-run ASE initialization..."
    cleanup_partial_init
    mkdir -p "${ASE_DATA_PATH}"
    : > "${SYBASE}/interfaces"

    run_srvbuildres        || return 1
    run_sqllocres          || return 1

    disable_async_io       || return 1
    log_info "Stopping server before applying static cfg edits..."
    graceful_shutdown      || return 1


    start_server           || return 1

    if ! process_init_files; then
        log_error "User init scripts failed"
        return 1
    fi

    log_info "Stopping server after init complete..."
    graceful_shutdown      || return 1

    touch "${ASE_INIT_SENTINEL}"
    log_info "First-run initialization complete (sentinel: ${ASE_INIT_SENTINEL})"
    return 0
}

mkdir -p "${ASE_DATA_PATH}"
[ -f "${SYBASE}/interfaces" ] || touch "${SYBASE}/interfaces"

if [ ! -f "${ASE_INIT_SENTINEL}" ]; then
    if ! initial_setup; then
        log_error "Initial setup failed; cleaning up so next start can retry from scratch"
        graceful_shutdown || true
        cleanup_partial_init
        exit 1
    fi
else
    log_info "Found init sentinel: ${ASE_INIT_SENTINEL} (skipping first-run setup)"
fi

if [ ! -f "${ASE_RUN_FILE}" ]; then
    log_error "RUN file missing after init: ${ASE_RUN_FILE}"
    log_error "Removing sentinel so next container start will rebuild from scratch"
    rm -f "${ASE_INIT_SENTINEL}"
    exit 1
fi

if ! start_server; then
    log_error "ASE failed to start"
    exit 1
fi

DATASERVER_PID="$(dataserver_pid)"
if [ -z "${DATASERVER_PID}" ]; then
    log_error "Dataserver started but PID could not be determined"
    exit 1
fi

log_info "ASE server '${ASE_DS_NAME}' ready on port ${ASE_PORT} (dataserver pid=${DATASERVER_PID})"
log_info "Tailing error log: ${ASE_ERROR_LOG}"

tail --pid="${DATASERVER_PID}" -F "${ASE_ERROR_LOG}" &
TAIL_PID=$!

# `wait` cannot be used: dataserver is not a child of this shell. Poll with
# `kill -0` so signal traps can fire between iterations.
while kill -0 "${DATASERVER_PID}" 2>/dev/null; do
    sleep 2
done

log_warn "Dataserver process exited unexpectedly"
if [ -n "${TAIL_PID}" ]; then
    kill "${TAIL_PID}" 2>/dev/null || true
    wait "${TAIL_PID}" 2>/dev/null || true
fi
dump_errorlog_tail
exit 1
