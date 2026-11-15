#!/bin/zsh

set -eu
setopt NO_UNSET PIPE_FAIL

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
CONFIG_DIR="${CLAUDE_NETWORK_LOCK_CONFIG_DIR:-${HOME}/.config/claude-network-lock}"
BIN_DIR="${CLAUDE_NETWORK_LOCK_BIN_DIR:-${HOME}/.local/bin}"
PROXY_HOST="127.0.0.1"
PROXY_PORT=""
CLAUDE_BIN=""
EXPECTED_IP=""
ASSUME_YES=0

usage() {
  print -- "用法：$0 --proxy-port PORT [--claude-bin PATH] [--expected-ip IP] [--yes]"
}

fail() {
  print -u2 -- "[安装器] $*"
  exit 1
}

while (( $# > 0 )); do
  case "$1" in
    --proxy-port)
      (( $# >= 2 )) || fail "--proxy-port 缺少值"
      PROXY_PORT="$2"
      shift 2
      ;;
    --claude-bin)
      (( $# >= 2 )) || fail "--claude-bin 缺少值"
      CLAUDE_BIN="$2"
      shift 2
      ;;
    --expected-ip)
      (( $# >= 2 )) || fail "--expected-ip 缺少值"
      EXPECTED_IP="$2"
      shift 2
      ;;
    --yes)
      ASSUME_YES=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "未知参数：$1"
      ;;
  esac
done

[[ "${PROXY_PORT}" == <-> ]] || fail "必须使用 --proxy-port 指定数字端口"
(( PROXY_PORT >= 1 && PROXY_PORT <= 65535 )) || fail "代理端口超出范围"

if [[ -z "${CLAUDE_BIN}" ]]; then
  CLAUDE_BIN="$(command -v claude 2>/dev/null || true)"
  [[ -n "${CLAUDE_BIN}" ]] || fail "未找到 claude；请用 --claude-bin 指定官方 CLI"
fi
CLAUDE_BIN="${CLAUDE_BIN:A}"
[[ -x "${CLAUDE_BIN}" ]] || fail "Claude 二进制不存在或不可执行：${CLAUDE_BIN}"
[[ "${CLAUDE_BIN:t}" != "claude-locked" ]] \
  || fail "检测到了网络锁本身；请用 --claude-bin 指定真实 Claude 二进制"

signature_info="$(/usr/bin/codesign -dv --verbose=2 "${CLAUDE_BIN}" 2>&1)" \
  || fail "目标二进制没有可验证的 macOS 代码签名"
identifier="$(print -r -- "${signature_info}" | /usr/bin/awk -F= '/^Identifier=/{print $2; exit}')"
team_id="$(print -r -- "${signature_info}" | /usr/bin/awk -F= '/^TeamIdentifier=/{print $2; exit}')"
[[ -n "${identifier}" && -n "${team_id}" ]] \
  || fail "无法从代码签名读取 Identifier 或 TeamIdentifier"
claude_sha256="$(/usr/bin/shasum -a 256 "${CLAUDE_BIN}" | /usr/bin/awk '{print $1}')"

/usr/bin/nc -z -w 2 "${PROXY_HOST}" "${PROXY_PORT}" 2>/dev/null \
  || fail "${PROXY_HOST}:${PROXY_PORT} 未监听；请先配置代理工具的专用端口"

unset http_proxy https_proxy all_proxy no_proxy
unset HTTP_PROXY HTTPS_PROXY ALL_PROXY NO_PROXY
proxy_url="http://${PROXY_HOST}:${PROXY_PORT}"
ip_one="$(/usr/bin/curl --fail --silent --show-error --max-time 10 \
  --noproxy "" --proxy "${proxy_url}" https://api.ipify.org | /usr/bin/tr -d '[:space:]')" \
  || fail "第一项出口查询失败"
ip_two="$(/usr/bin/curl --fail --silent --show-error --max-time 10 \
  --noproxy "" --proxy "${proxy_url}" https://ifconfig.me/ip | /usr/bin/tr -d '[:space:]')" \
  || fail "第二项出口查询失败"
[[ -n "${ip_one}" && "${ip_one}" == "${ip_two}" ]] \
  || fail "两个出口查询结果不一致"

if [[ -n "${EXPECTED_IP}" && "${EXPECTED_IP}" != "${ip_one}" ]]; then
  fail "当前代理出口与 --expected-ip 不一致"
fi

masked_ip="${ip_one}"
if [[ "${ip_one}" == *.* ]]; then
  masked_ip="$(print -rn -- "${ip_one}" | /usr/bin/awk -F. '{print $1 "." $2 ".x.x"}')"
fi
print -- "[安装器] 检测到出口 ${masked_ip}，Claude Identifier=${identifier}，Team=${team_id}"

if (( ASSUME_YES == 0 )); then
  print -n -- "确认将当前出口固定为唯一允许出口？[y/N] "
  read -r answer
  [[ "${answer:l}" == "y" || "${answer:l}" == "yes" ]] || fail "用户取消"
fi

expected_ip_sha256="$(print -rn -- "${ip_one}" | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}')"

/bin/mkdir -p -m 700 "${CONFIG_DIR}" "${BIN_DIR}"
if [[ -e "${CONFIG_DIR}/config" ]]; then
  timestamp="$(/bin/date +%Y%m%d-%H%M%S)"
  /bin/cp -p "${CONFIG_DIR}/config" "${CONFIG_DIR}/config.backup-${timestamp}"
  print -- "[安装器] 已备份旧配置：${CONFIG_DIR}/config.backup-${timestamp}"
fi

temp_config="$(/usr/bin/mktemp "${CONFIG_DIR}/config.tmp.XXXXXX")"
trap '/bin/rm -f -- "${temp_config}"' EXIT
{
  print -r -- "CONFIG_VERSION=1"
  printf 'PROXY_HOST=%q\n' "${PROXY_HOST}"
  printf 'PROXY_PORT=%q\n' "${PROXY_PORT}"
  printf 'EXPECTED_IP_SHA256=%q\n' "${expected_ip_sha256}"
  printf 'PINNED_CLAUDE_BIN=%q\n' "${CLAUDE_BIN}"
  printf 'PINNED_IDENTIFIER=%q\n' "${identifier}"
  printf 'PINNED_TEAM_ID=%q\n' "${team_id}"
  printf 'PINNED_SHA256=%q\n' "${claude_sha256}"
} > "${temp_config}"
/bin/chmod 600 "${temp_config}"
/bin/mv -f "${temp_config}" "${CONFIG_DIR}/config"
trap - EXIT

[[ -e "${CONFIG_DIR}/local-ports" ]] || {
  print -r -- "# 每行一个允许 Claude Code 访问的本机开发端口；默认留空。" > "${CONFIG_DIR}/local-ports"
  /bin/chmod 600 "${CONFIG_DIR}/local-ports"
}

/usr/bin/install -m 700 "${PROJECT_DIR}/bin/claude-locked" "${BIN_DIR}/claude-locked"

print -- "[安装器] 安装完成：${BIN_DIR}/claude-locked"
print -- "[安装器] 下一步：${BIN_DIR}/claude-locked --lock-self-test"
if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  print -- "[安装器] 提示：${BIN_DIR} 当前不在 PATH 中"
fi
