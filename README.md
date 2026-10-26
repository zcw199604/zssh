# zssh

用 macOS 钥匙串（或 Windows 凭据管理器）保存 SSH 密码、通过系统 `ssh` 执行远程命令的小工具，适合交给 Claude Code 等 AI Agent 使用：Agent 只传主机别名，密码由钥匙串经 `SSH_ASKPASS` 直接交给 `ssh`，不出现在命令行参数、环境变量、输出和会话记录中。

## 工作原理

1. 主机信息写在 `~/.ssh/config` 的 `Host` 段里（不含密码）。
2. 密码存放在钥匙串，条目名称（service）为 `ssh_pass_<alias>`，账户（account）为 `<alias>`。
3. `zssh <alias> '<cmd>'` 发现钥匙串有该别名的密码时，把自身设为 `SSH_ASKPASS`（`SSH_ASKPASS_REQUIRE=force`），`ssh` 需要密码时回调它从钥匙串读取；只应答密码提示，主机指纹确认等其他提示一律拒绝。
4. 钥匙串没有该别名的条目时按密钥认证执行，并开启 `BatchMode`，不会卡在任何交互提示上。

默认 ssh 选项：`StrictHostKeyChecking=accept-new`、`NumberOfPasswordPrompts=1`、`ConnectTimeout=10`，并用 `ControlMaster` 复用连接 10 分钟。

## 环境要求

- macOS（依赖 `/usr/bin/security` 和钥匙串）
- OpenSSH ≥ 8.4（支持 `SSH_ASKPASS_REQUIRE`），macOS 自带版本即可

## 安装

```bash
git clone https://github.com/zcw199604/zssh.git ~/project/zssh
ln -sf ~/project/zssh/bin/zssh ~/.local/bin/zssh          # 确保 ~/.local/bin 在 PATH 中
ln -sfn ~/project/zssh/skills/zssh ~/.claude/skills/zssh  # 可选：安装 Claude Code skill
```

## 使用

```bash
zssh --add <alias> <user@host[:port]>   # 追加 ~/.ssh/config 的 Host 段，并可接着录入密码
zssh --set <alias>                      # 录入或更新密码（交互输入）
zssh --probe <alias>                    # 只握手不登录，检查老服务器需要补哪些算法配置
zssh <alias> '<remote command>'         # 执行远程命令，退出码即远程命令退出码；255 表示 ssh 自身失败
```

### 连接老版本 SSH 服务器

新版 OpenSSH 默认禁用了 `ssh-rsa`（SHA-1）等旧算法，连接 CentOS 6（OpenSSH 5.3）这类老服务器时会报 `no matching host key type found` 等错误。用 `--probe` 检查：

```text
$ zssh --probe old01
目标: deploy@192.0.2.20:22  服务器: OpenSSH_5.3
  主机密钥: 不可协商，需添加 HostKeyAlgorithms +ssh-rsa
  密钥交换: 可协商 (diffie-hellman-group-exchange-sha256)
  加密算法: 可协商 (aes128-ctr)
  MAC: 可协商 (hmac-sha2-256)
  注意: 服务器早于 OpenSSH 6.5，不支持 ed25519 密钥，密钥登录请使用 RSA 密钥

请在 ~/.ssh/config（或其 Include 的文件）的 Host old01 段中手动加入：
    HostKeyAlgorithms +ssh-rsa
    PubkeyAcceptedAlgorithms +ssh-rsa   # 仅使用 RSA 密钥登录时需要
```

- 探测时使用 `PreferredAuthentications=none` 只完成握手、不尝试登录，`UserKnownHostsFile=/dev/null` 不写入 known_hosts，只打印需要补充的配置，不修改任何文件。
- 按提示把配置手动加到对应的 Host 段，不要加到 `Host *`；带注释的项按需添加。
- 服务器只提供 `ssh-dss` 时，OpenSSH 10 已无法连接，只能升级服务器。

示例：

```bash
zssh --add web01 deploy@192.0.2.10
zssh web01 'uptime'
```

删除连接：

```bash
security delete-generic-password -s ssh_pass_web01 -a web01
# 再手动删除 ~/.ssh/config 中对应的 Host 段
```

## Windows 版

`windows/` 目录是 Git Bash 版本（Claude Code 在 Windows 上的 Bash 工具即 Git Bash），用法与 macOS 版相同：

| | macOS 版 `bin/zssh` | Windows 版 `windows/zssh` |
|---|---|---|
| 密码存放 | 钥匙串，service `ssh_pass_<alias>` | 凭据管理器 → Windows 凭据（普通凭据），目标名 `ssh_pass_<alias>` |
| 读写方式 | `/usr/bin/security` | 同目录的 `zssh-cred.ps1`（Windows PowerShell 调用 `CredRead/CredWrite`，无需额外模块） |
| ssh | `/usr/bin/ssh` | Git Bash 自带的 `/usr/bin/ssh`（不是 `C:\Windows\System32\OpenSSH`） |
| 连接复用 | ControlMaster 10 分钟 | 无（Git Bash 下 ControlMaster 不可靠），每次调用单独连接 |

安装（在 Git Bash 中执行）：

```bash
git clone https://github.com/zcw199604/zssh.git ~/project/zssh
echo 'export PATH="$HOME/project/zssh/windows:$PATH"' >> ~/.bashrc && source ~/.bashrc
cp -r ~/project/zssh/skills/zssh ~/.claude/skills/zssh   # 可选：安装 Claude Code skill
```

删除凭据：`MSYS_NO_PATHCONV=1 cmdkey /delete:ssh_pass_<alias>`，或在「控制面板 → 凭据管理器 → Windows 凭据」中删除。

要求：Git for Windows（自带 OpenSSH ≥ 8.4）和系统自带的 Windows PowerShell 5.1。

## Claude Code skill

`skills/zssh/SKILL.md` 约定 Agent 统一通过 `zssh <alias> '<cmd>'` 访问远程主机，不读写钥匙串、不运行 `zssh --set`，认证失败或主机指纹变化时停止并报告，变更类命令执行前先征得用户确认。

## 安全说明

- 默认情况下，以同一用户身份运行的任何程序都能读取由 `security` 创建的钥匙串条目，Agent 理论上也可以直接调用 `security` 读出密码；skill 的约束只是提示词层面的。Windows 凭据管理器同理，且没有逐次弹窗确认的选项。
- 如需人工把关，录入时去掉对 `security` 的默认信任，让每次读取都弹窗确认（连接复用期内不会重复弹出）：

  ```bash
  security add-generic-password -s ssh_pass_<alias> -a <alias> -U -T "" -w
  ```

- 能使用密钥登录的主机，优先使用密钥加 `ssh-agent`。
