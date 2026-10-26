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
- 传文件（基于 `scp -r`，文件和目录都适用，退出码非 0 即失败）：
  - 下载：`zssh --get <alias> <remote path> <local path>`，属于只读操作，可直接执行。
  - 上传：`zssh --put <alias> <local path> <remote path>`，会创建或覆盖远程文件，属于变更操作，执行前先说明目标路径并等用户确认。

## 日志检索

只列容易导致漏查或误判的点：

1. **“没找到”要有依据**：说明检索了哪些文件、哪个时间段。出现超时（`timeout` 退出码 `124`）、`Permission denied`/`权限不够`、`No such file`，或定位不到时间点时，该部分算**未检索**，不能算“没有”。管道最后一级的退出码会掩盖前面的错误，要同时看 stderr。
2. **截断只放在管道最后一级**：`-m`、`head` 放在中间会漏掉后面的匹配。
3. **多行日志按行号窗口检索**：Java 堆栈等续行没有时间戳，按时间前缀逐行过滤会漏掉。先用 `grep -n -m 1` 定位起止时间的行号，再 `sed -n 'a,bp'` 取出窗口后检索；精确时间点不存在时放宽前缀，或取到文件末尾（`$`）。
4. **别忘了轮转日志**：事发时间早于当前文件开头时，同时检索 `*.1`、`*.gz` 等归档（`zgrep`）。
5. **控制资源**：扫描大文件时加 `timeout <秒> nice -n 19 ionice -c3`；准备扫描的总量超过约 5GB 时先告知用户。

```bash
zssh web01 'f=/app/logs/app.log; a=$(grep -n -m 1 -F "2026-10-26 14:30" "$f" | cut -d: -f1); b=$(grep -n -m 1 -F "2026-10-26 14:40" "$f" | cut -d: -f1)
  [ -n "$a" ] && [ -n "$b" ] || { echo "未定位到时间窗口 a=$a b=$b"; exit 3; }
  sed -n "${a},${b}p" "$f" | grep -n -C 5 -F "OrderTimeoutException" | head -n 200'
```

## 添加连接

用户要求添加主机时可以执行 `zssh --add <alias> <user@host[:port]> </dev/null`：它只追加 `~/.ssh/config`，别名已存在会拒绝；无终端时自动跳过录入密码。之后请用户在自己的终端执行 `zssh --set <alias>` 录入密码（钥匙串/凭据管理器中的条目名为 `ssh_pass_<alias>`）。

## 连接失败排查

出现 `no matching host key type / key exchange method / cipher found` 等协商失败时，执行 `zssh --probe <alias>`：它只握手不登录、不写 known_hosts、不修改任何文件，输出服务器 SSH 版本和需要在该 Host 段中补充的配置。把需要补充的配置展示给用户，由用户手动添加；不要自行编辑 ssh 配置，也不要加到 `Host *`。

## 禁止

- 不直接运行 `ssh`/`scp`/`sshpass` 去连接需要密码的主机。
- 不读取、打印、创建或删除钥匙串/凭据管理器条目（`security find-generic-password`、`add-generic-password`、`cmdkey`、`zssh-cred.ps1` 等），不设置 `ZSSH_ASKPASS_ALIAS`、`SSH_ASKPASS`。
- 不使用 `zssh -t`（交互式登录）和 `zssh --forward`（端口转发，会一直运行到 Ctrl-C），它们仅供用户在自己的终端使用，无终端时会直接报错。需要端口转发时，把命令给用户自己运行。
- 不运行 `zssh --set`，也不在有终端输入的情况下运行 `zssh --add`。缺密码时，请用户在自己的终端执行 `zssh --set <alias>`。
- 认证失败（`Permission denied`）或主机指纹变化（`REMOTE HOST IDENTIFICATION HAS CHANGED`）时不要重试、不要绕过，直接报告给用户。

## 变更操作

重启服务、删除文件、修改配置、kill 进程等会改变远程状态的命令，执行前先说明命令和影响并等用户确认；只读排查可以直接执行。
