# Security Policy and Threat Model

## 保护目标

- Claude Code 只经指定的 localhost 代理端口访问网络；
- 启动时的出口必须与安装时记录的固定 IP 指纹一致；
- Claude Code 更新、替换或签名变化时拒绝启动；
- 代理退出、固定节点失效或出口变化时 fail-closed；
- Claude 子进程继承相同的 Seatbelt 网络限制。

## 不在保护范围内

- 平台服务端的账号、设备、付款或历史关联；
- 浏览器、Claude Desktop、IDE 插件或其他启动入口；
- 已控制当前 macOS 用户账号的恶意软件；
- 代理客户端自身的漏洞或错误回退规则；
- 本地白名单端口上运行的任意转发服务；
- macOS 将来移除或改变 Seatbelt/sandbox-exec 行为。

## 重要限制

Seatbelt 放行的是本地代理端口。网络锁无法从外部证明代理客户端内部没有回退路径，因此代理工具的配置及故障测试是整体安全性的一部分。

IP 查询服务也是外部依赖。双源一致能降低单点错误，但不能替代对代理链的审计。

## 发布者检查清单

- [ ] 没有真实代理 server、username、password 或订阅 URL；
- [ ] 没有明文出口 IP 或其可识别描述；
- [ ] 没有个人用户名、绝对路径、设备地址或本地端口用途；
- [ ] 没有生成后的 `~/.config/claude-network-lock/config`；
- [ ] 示例只使用 RFC 5737 文档地址或明显占位符；
- [ ] `zsh tests/smoke.zsh` 通过；
- [ ] 在干净 macOS 用户环境完成一次安装、自检、启动和卸载测试。

## 报告问题

公开报告请勿附带代理凭据、订阅内容、真实出口 IP 或 Claude 登录信息。若仓库启用了私密安全报告，请优先使用该渠道。
