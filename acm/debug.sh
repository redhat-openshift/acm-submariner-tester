#!/bin/bash

export RED='\x1b[0;31m'
export GREEN='\x1b[38;5;22m'
export CYAN='\x1b[36m'
export YELLOW='\x1b[33m'
export NO_COLOR='\x1b[0m'

if [ -z "${LOG_TITLE}" ]; then
  LOG_TITLE=''
fi
if [ -z "${LOG_LEVEL}" ]; then
    LOG_LEVEL="INFO"
fi

PS4="${GREEN}[DEBUG]${LOG_TITLE} ${NO_COLOR}"
set -e            # exit immediately.
set -E            # any trap on ERR is inherited.
# set +E            # turn off this option
# set -u            # treat unset variables and parameters as an error.
# set -o pipefail   # set the exit code of a pipeline to that of the rightmost command to exit with a non-zero status.
#
# #trap 'catch $? $LINENO $LASTNO "$BASH_COMMAND"' SIGHUP SIGINT SIGTERM SIGQUIT ERR EXIT
# trap 'catch $? $LINENO "$BASH_COMMAND"' SIGHUP SIGINT SIGTERM SIGQUIT ERR EXIT

catch() {
  if [ "$1" != "0" ]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
      log_title="(${LOG_TITLE})"
    else
      log_title=''
    fi
    echo -e "${RED}[ERROR]${log_title} \
    RC=$1 \
    LINE=$2 \
    CMD=$3 ${NO_COLOR}"
  fi
}

debug() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${GREEN}[DEBUG]${log_title} ${NO_COLOR}$1"
  fi
}

info() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${CYAN}[INFO] ${log_title} ${NO_COLOR}$1"
  fi
}

warn() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]] ||\
     [[ "${LOG_LEVEL}" == "WARN" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${YELLOW}[WARN] ${log_title} ${NO_COLOR}$1"
  fi
}

error() {
  if [[ "${LOG_LEVEL}" == "DEBUG" ]] ||\
     [[ "${LOG_LEVEL}" == "INFO" ]] ||\
     [[ "${LOG_LEVEL}" == "WARN" ]] ||\
     [[ "${LOG_LEVEL}" == "ERROR" ]]; then
    local log_title
    if [ -n "${LOG_TITLE}" ]; then
     log_title="(${LOG_TITLE})"
    else
     log_title=''
    fi
    echo -e "${RED}[ERROR]${log_title} ${NO_COLOR}$1"
  fi
}

is_shell_attribute_set() { # attribute, like "e"
  case "$-" in
    *"$1"*) return 0 ;;
    *)    return 1 ;;
  esac
}


is_shell_option_set() { # option, like "pipefail"
  case "$(set -o | grep "$1")" in
    *on) return 0 ;;
    *)   return 1 ;;
  esac
}

if [ "${LOG_LEVEL}" == "DEBUG" ]; then
  set -x
fi
