# Claude Network Lock

一个面向 macOS 的 Claude Code 网络出口锁。它不修改 Claude Code，也不保证账号不会触发平台风控；它解决的是更具体的问题：**只有在本地固定代理端口可用、出口 IP 与预期一致时才启动 Claude Code，并阻止该进程树绕过这个端口直连网络。**

> 本项目与 Anthropic 无隶属或背书关系。请遵守服务条款、所在地法律以及所在组织的安全规范。

## 它做什么

```text
Claude Code
  -> macOS Seatbelt：只放行指定 localhost 代理端口
  -> 用户自己的代理工具
  -> 固定节点或固定链式代理（不得自动切换、DIRECT 或故障转移）
  -> 预期公网出口
```

每次启动前会验证：

1. Claude Code 的真实路径、SHA-256、签名 Identifier 和 Team ID；
2. 指定的本地代理端口正在监听；
3. 两个公网 IP 查询服务返回相同结果；
4. 出口 IP 的 SHA-256 与安装时记录的指纹一致；
5. Seatbelt 能放行指定代理端口，并阻止公网直连、`open` 和 `osascript`。

任何一项失败都会拒绝启动（fail-closed）。

## 系统要求

- macOS，且系统仍提供 `/usr/bin/sandbox-exec`；
- 已安装官方 Claude Code CLI；
- 一个支持 HTTP 或 mixed 入站的本地代理客户端；
- 一个稳定、合规且由你控制的固定出口；
- `zsh`、`curl`、`nc`、`codesign`、`shasum`（macOS 自带）。

不适用于 Windows/Linux，也不适合出口 IP 会频繁变化的普通自动选路订阅。

## 快速开始

### 1. 先配置代理客户端

请使用您自己的代理工具，配置一个专用端口（例如 `7899`）。该端口必须满足以下条件：

- 独立监听 `127.0.0.1:<端口>`，不要监听 `0.0.0.0`；
- 该端口直接绑定固定策略，不跟随”全局选择”变化；
- 策略内没有 `DIRECT`、自动测速、负载均衡或备用节点；
- 上游失效时端口应直接断网，不能回退到日常代理或系统直连。

请确保所使用的代理工具及网络出口符合所在地法律法规。

先验证端口和出口（下面以 `7899` 为例）：

```zsh
lsof -nP -iTCP:7899 -sTCP:LISTEN
curl --fail --proxy http://127.0.0.1:7899 https://api.ipify.org
curl --fail --proxy http://127.0.0.1:7899 https://ifconfig.me/ip
```

两次查询必须得到同一个预期 IP。

### 2. 安装网络锁

```zsh
chmod +x scripts/install.zsh
./scripts/install.zsh --proxy-port 7899
```

安装器会：

- 自动定位当前 `claude` 的真实二进制；
- 读取并固定其签名与文件哈希；
- 通过指定代理做双源出口检查；
- 只保存出口 IP 的 SHA-256，不保存明文 IP；
- 安装启动器到 `~/.local/bin/claude-locked`；
- 写入权限为 `600` 的本机配置。

自动化安装可明确提供参数：

```zsh
./scripts/install.zsh \
  --proxy-port 7899 \
  --claude-bin /path/to/real/claude \
  --expected-ip 203.0.113.10 \
  --yes
```

`203.0.113.10` 只是文档示例地址，请换成自己的实际出口。

### 3. 自检并启动

如果 `~/.local/bin` 不在 `PATH` 中：

```zsh
export PATH="$HOME/.local/bin:$PATH"
```

执行完整自检：

```zsh
claude-locked --lock-self-test
```

正常使用：

```zsh
claude-locked
```

首次确认无误后，可以自行设置一个不覆盖原命令的别名：

```zsh
alias claude-safe="$HOME/.local/bin/claude-locked"
```

## OAuth 登录

```zsh
claude-locked auth login
```

网络锁会阻止 Claude Code 自动调用默认浏览器。请复制终端中新生成的 OAuth URL，在**同样明确使用固定出口**的浏览器中打开。浏览器不在本项目的 Seatbelt 约束内，必须单独确认其出口。

## Claude Code 更新后

更新会改变路径或 SHA-256，旧锁会按设计拒绝启动。确认新版本来自可信来源后重新运行安装器：

```zsh
./scripts/install.zsh --proxy-port 7899
claude-locked --lock-self-test
```

安装器会备份旧配置，不会静默信任新二进制。

## 本地开发端口

默认不放行任何其他 localhost 端口。如 Claude Code 必须访问本地开发服务，在下面文件中每行写一个端口：

```text
~/.config/claude-network-lock/local-ports
```

例如：

```text
# 本地 Web 开发服务器
3000
```

不要把 HTTP/SOCKS 代理、任意转发器或不可信服务加入白名单，否则它可能成为绕过固定出口的通道。修改后必须重新执行完整自检。

## 卸载

```zsh
./scripts/uninstall.zsh
```

默认只删除启动器并保留本机配置。要同时移除配置：

```zsh
./scripts/uninstall.zsh --purge-config
```

## 安全边界

本项目能控制本机 Claude Code 进程树的网络路径，但不能：

- 删除或改变平台服务端已有记录；
- 让动态/共享出口变成稳定独享出口；
- 约束你手动打开的浏览器、IDE 插件或另一个 Claude 入口；
- 防止具有当前用户权限的恶意程序修改本地代理或配置；
- 承诺账号“永不封禁”。

详细威胁模型与发布前检查见 [SECURITY.md](SECURITY.md)。

## 开源发布前检查

```zsh
zsh tests/smoke.zsh
```

确认仓库中没有真实代理地址、账号、密码、出口 IP、个人路径或生成后的 `config` 文件，再提交到公开仓库。

## License

MIT，见 [LICENSE](LICENSE)。
