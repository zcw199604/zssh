---
name: zssh
description: 需要在远程服务器上执行命令时使用（SSH、远程节点、登录服务器、远程排查、查看远程日志/配置/进程、主机别名如 web01）。统一通过 `zssh <alias> '<cmd>'` 调用系统 ssh，密码由本机 macOS 钥匙串或 Windows 凭据管理器提供，模型永远接触不到密码。不用于本地命令、本机 Docker 或 git 远程操作。
---

# zssh

## 用法

```bash
zssh <alias> '<remote command>'
```

- `alias` 是 `~/.ssh/config` 中的 `Host`。不确定时用 `grep -E '^Host ' ~/.ssh/config` 列出，不要用 IP 或相似名字去猜。
- 远程命令整体作为一个参数，用单引号包住；多条相关的只读检查可以用 `;` / `&&` 合并成一次调用。
- 退出码就是远程命令的退出码；`255` 表示 ssh 自身失败（连接、认证、主机指纹）。
- macOS 上连接会复用 10 分钟（ControlMaster），连续调用不会重复认证；Windows（Git Bash）版每次调用单独连接。
- 传文件：读取用 `zssh host 'cat /path'`；小文件写入用 `cat local | zssh host 'cat > /path'`。大文件或目录交给用户处理。

## 添加连接

用户要求添加主机时可以执行 `zssh --add <alias> <user@host[:port]> </dev/null`：它只追加 `~/.ssh/config`，别名已存在会拒绝；无终端时自动跳过录入密码。之后请用户在自己的终端执行 `zssh --set <alias>` 录入密码（钥匙串/凭据管理器中的条目名为 `ssh_pass_<alias>`）。

## 禁止

- 不直接运行 `ssh`/`scp`/`sshpass` 去连接需要密码的主机。
- 不读取、打印、创建或删除钥匙串/凭据管理器条目（`security find-generic-password`、`add-generic-password`、`cmdkey`、`zssh-cred.ps1` 等），不设置 `ZSSH_ASKPASS_ALIAS`、`SSH_ASKPASS`。
- 不运行 `zssh --set`，也不在有终端输入的情况下运行 `zssh --add`。缺密码时，请用户在自己的终端执行 `zssh --set <alias>`。
- 认证失败（`Permission denied`）或主机指纹变化（`REMOTE HOST IDENTIFICATION HAS CHANGED`）时不要重试、不要绕过，直接报告给用户。

## 变更操作

重启服务、删除文件、修改配置、kill 进程等会改变远程状态的命令，执行前先说明命令和影响并等用户确认；只读排查可以直接执行。
