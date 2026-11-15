#!/bin/zsh

set -eu
setopt NO_UNSET

CONFIG_DIR="${CLAUDE_NETWORK_LOCK_CONFIG_DIR:-${HOME}/.config/claude-network-lock}"
BIN_DIR="${CLAUDE_NETWORK_LOCK_BIN_DIR:-${HOME}/.local/bin}"
PURGE_CONFIG=0

if [[ "${1:-}" == "--purge-config" ]]; then
  PURGE_CONFIG=1
elif (( $# > 0 )); then
  print -u2 -- "用法：$0 [--purge-config]"
  exit 2
fi

if [[ -e "${BIN_DIR}/claude-locked" ]]; then
  /bin/rm -f -- "${BIN_DIR}/claude-locked"
  print -- "已删除启动器：${BIN_DIR}/claude-locked"
else
  print -- "启动器不存在，无需删除"
fi

if (( PURGE_CONFIG == 1 )); then
  if [[ "${CONFIG_DIR}" != "/" && "${CONFIG_DIR}" != "${HOME}" && \
        "${CONFIG_DIR}" == */claude-network-lock ]]; then
    /bin/rm -rf -- "${CONFIG_DIR}"
    print -- "已删除配置目录：${CONFIG_DIR}"
  else
    print -u2 -- "拒绝删除无法确认的配置路径：${CONFIG_DIR}"
    exit 1
  fi
else
  print -- "已保留配置：${CONFIG_DIR}"
fi
