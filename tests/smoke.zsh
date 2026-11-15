#!/bin/zsh

set -eu
setopt NO_UNSET PIPE_FAIL

PROJECT_DIR="${0:A:h:h}"

for script in \
  "${PROJECT_DIR}/bin/claude-locked" \
  "${PROJECT_DIR}/scripts/install.zsh" \
  "${PROJECT_DIR}/scripts/uninstall.zsh"; do
  /bin/zsh -n "${script}"
done

/usr/bin/grep -Fq 'PROXY_HOST="127.0.0.1"' "${PROJECT_DIR}/scripts/install.zsh"
/usr/bin/grep -Fq '(deny network-outbound)' "${PROJECT_DIR}/bin/claude-locked"
/usr/bin/grep -Fq 'EXPECTED_IP_SHA256' "${PROJECT_DIR}/bin/claude-locked"

if /usr/bin/grep -REn --exclude='smoke.zsh' \
  '(/Users/|BEGIN (RSA |OPENSSH |EC )?PRIVATE KEY|subscription-url=|password: [^A-Z[:space:]])' \
  "${PROJECT_DIR}"; then
  print -u2 -- "发现疑似本机路径、密钥或真实凭据"
  exit 1
fi

print -- "smoke tests passed"
