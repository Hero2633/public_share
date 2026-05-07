
**环境说明：**

- **操作系统**：Ubuntu 22.04 Server (无图形界面)
- **系统架构**：amd64
- **核心软件**：Mihomo (Clash Meta)
- **前端面板**：MetaCubeXD
- **核心功能**：全局透明代理 (TUN 模式)、本地 Web UI 控制、国内外流量自动分流。

---

**本教程只配置 TUN 模式，不配置系统代理！**

---

# 第一部分：手动安装

适用于需要完全理解安装过程、或有特殊定制需求的用户。

## 一、安装 Mihomo 内核

**1. 下载并解压核心文件**

```Bash
# 下载指定版本的压缩包
wget https://github.com/MetaCubeX/mihomo/releases/download/v1.19.24/mihomo-linux-amd64-v1.19.24.gz -O mihomo.gz

# 解压文件
gunzip mihomo.gz

# 移动到系统可执行目录并重命名
sudo mv mihomo /usr/local/bin/mihomo

# 赋予执行权限
sudo chmod +x /usr/local/bin/mihomo

# 检查安装是否成功
mihomo -v
```

> **版本查询**：访问 [Mihomo Releases](https://github.com/MetaCubeX/mihomo/releases) 获取最新版本号，替换上述 URL 中的版本。
> **下载困难？** 如果国内网络无法直接下载，可尝试使用代理或镜像站，如 `https://ghfast.top/https://github.com/...`。

## 二、配置 Systemd 后台服务

**1. 创建服务配置文件**

```Bash
sudo nano /etc/systemd/system/mihomo.service
```

**2. 填入进阶权限配置 (支持 TUN 及高级网络接管)**

```ini
[Unit]
Description=mihomo Daemon, Another Clash Kernel.
After=network.target NetworkManager.service systemd-networkd.service iwd.service

[Service]
Type=simple
LimitNPROC=500
LimitNOFILE=1000000
CapabilityBoundingSet=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
AmbientCapabilities=CAP_NET_ADMIN CAP_NET_RAW CAP_NET_BIND_SERVICE CAP_SYS_TIME CAP_SYS_PTRACE CAP_DAC_READ_SEARCH CAP_DAC_OVERRIDE
Restart=always
ExecStartPre=/usr/bin/sleep 1s
ExecStart=/usr/local/bin/mihomo -d /etc/mihomo
ExecReload=/bin/kill -HUP $MAINPID

[Install]
WantedBy=multi-user.target
```

_(保存并退出：`Ctrl+O`, `Enter`, `Ctrl+X`)_

## 三、配置 Mihomo (`config.yaml`)

**1. 创建配置目录**

```Bash
sudo mkdir -p /etc/mihomo
```

**2. 下载主配置文件**

```Bash
curl -L -o /etc/mihomo/config.yaml "你的订阅链接!"
```

![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121136474.png)

注意**选择 Mihomo 内核**！不要选择"复制订阅"！

> 如果没有`选择Mihomo内核`这一个选项，可以直接从 Windows 下的 clash 软件中导出 yaml 文件，再上传到服务器：
> ![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121127178.png)
> 然后就会跳转到对应的 yaml 文件：
> ![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121104195.png)

**3. 修改 config.yaml 文件中的基础配置**

_(注意：以下配置仅包含 TUN、DNS、sniffer 等基础设置，具体的 `proxies`、`proxy-groups` 和 `rules` 请保留你订阅配置中的内容)_

如果有字段冲突，以下面的配置为准：

```yaml
# 1. 开启外部控制台（方便后续看延迟和切节点）
external-controller: '0.0.0.0:9090' # 允许外部访问控制 API
external-ui: /etc/mihomo/ui         # 指定前端面板文件路径，访问地址为 API地址/ui
secret: '你的自定义密码'             # 必填！设置一个密码防止别人控制你的代理

# 2. 开启 DNS 劫持（TUN 模式必须配合 DNS 劫持才能完美工作）
dns:
  enable: true
  listen: 0.0.0.0:53
  ipv6: false
  enhanced-mode: fake-ip            # 强烈建议使用 fake-ip 模式，解析速度极快
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 114.114.114.114
    - tls://dns.alidns.com

# 3. 开启 TUN 模式核心配置
tun:
  enable: true
  stack: mixed                     # 网络栈，推荐 system 或 mixed
  dns-hijack:
    - any:53                        # 劫持所有 DNS 请求
  auto-route: true                  # 自动设置全局路由，接管全部流量
  auto-detect-interface: true       # 自动识别出口网卡

# 4. 流量嗅探（从纯 IP 的网络包里提取真实域名，让分流规则不失效）
sniffer:
  enable: true
  force-dns-mapping: true
  parse-pure-ip: true
  override-destination: true
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
```

> **密码设置提示**：建议使用字母和数字组合，避免使用 `'`、`"`、`:` 等特殊字符，以免 YAML 解析出错。

**端口说明**：
- `external-controller: 0.0.0.0:9090` - API 控制端口，用于远程管理
- 访问面板时使用 `http://服务器IP:9090/ui/`

**常用命令**：

```Bash
# 测试配置文件语法（极度常用！每次修改 config.yaml 后务必先执行）
sudo mihomo -d /etc/mihomo -t

# 预期输出：configuration file /etc/mihomo/config.yaml test is successful
```

## 四、本地部署 MetaCubeXD 前端面板

为了避免因节点不通导致外部面板无法加载的问题，我们将 UI 部署在本地。

**1. 下载并解压面板资源**

```Bash
cd /etc/mihomo

# 下载最新编译版（版本号请从 GitHub Releases 获取）
sudo wget https://github.com/MetaCubeX/metacubexd/releases/download/v1.246.3/compressed-dist.tgz -O ui.tgz

# 创建 ui 文件夹并解压
sudo mkdir -p ui
sudo tar -xzvf ui.tgz -C ui

# 清理压缩包
sudo rm ui.tgz
```

> **版本查询**：访问 [MetaCubeXD Releases](https://github.com/MetaCubeX/metacubexd/releases) 获取最新版本号。
> **下载困难？** 如果国内网络无法直接下载，可尝试使用代理或镜像站，如 `https://ghfast.top/https://github.com/...`。

**2. 修复权限 (极其重要，避免 404)**

```Bash
sudo chown -R root:root /etc/mihomo/ui
sudo chmod -R 755 /etc/mihomo/ui
```

## 五、启动并验证服务

**1. 测试配置语法是否正确**

```Bash
sudo mihomo -d /etc/mihomo -t
# 预期输出：configuration file /etc/mihomo/config.yaml test is successful
```

**2. 重载 systemd 并启动服务**

```Bash
sudo systemctl daemon-reload
sudo systemctl enable mihomo  # 设置开机自启
sudo systemctl start mihomo   # 启动服务
sudo systemctl status mihomo  # 查看运行状态
```

## 六、访问控制台与日常测试

**1. 访问面板**

在同局域网的浏览器中打开（注意结尾的 `/` 不可省略）：

👉 **`http://你的服务器IP:9090/ui/`**

- **API Base URL**: `http://你的服务器IP:9090`
- **Secret**: 你在 config.yaml 中设置的密码

**2. 连通性测试命令**

```Bash
# 验证直连 (国内 IP)
curl cip.cc

# 验证代理 (海外 IP)
curl ifconfig.me
# 或
curl ipinfo.io
```

---

# 第二部分：自动化安装 (mihomo-manager)

使用一键化管理脚本，自动完成安装、更新、卸载等操作。脚本位于 `scripts/mihomo-manager.sh`。

## 一、脚本功能介绍

| 功能 | 说明 |
|------|------|
| `--install, -i` | 安装 Mihomo 和 MetaCubeXD（支持订阅链接或本地配置文件） |
| `--update, -u` | 更新到最新版本或指定版本 |
| `--uninstall` | 完全卸载 Mihomo 和所有配置 |
| `--version, -V` | 显示当前安装的版本信息 |
| `--check, -c` | 检查是否有新版本可用 |
| `--proxy, -p` | 指定代理地址（格式：端口 或 IP:端口） |
| `--verbose` | 显示详细执行过程 |
| `--quiet` | 静默模式（只显示错误） |
| `--help, -h` | 显示帮助信息 |

## 二、使用方法

### 1. 安装 Mihomo 和 MetaCubeXD

**使用本地配置文件安装：**

```Bash
# 配置文件可以是任意路径
sudo ./scripts/mihomo-manager.sh --install -i /path/to/your/config.yaml
```

**使用订阅链接安装：**

```Bash
sudo ./scripts/mihomo-manager.sh --install -i "https://你的订阅链接"
```

**安装过程说明：**

脚本会自动执行以下步骤：
1. 检查系统环境（Ubuntu, amd64）
2. 获取最新版本并与已安装版本对比
3. **已是最新** → 直接跳过，不做任何备份
4. **需要更新** → 备份配置文件和旧版本
5. 下载所有资源（Mihomo、MetaCubeXD）
6. 停止服务、安装新版本
7. 合并配置文件（与 `conf/merge.yaml` 合并）
8. 预下载 GeoIP 数据库并启动服务
9. 清理备份文件

> **按需升级**：已安装的组件版本与最新版本一致时会跳过下载和安装。
> **下载优先**：脚本会先下载所有资源，确认下载成功后再执行安装，避免因下载失败导致系统处于不一致状态。

**安装完成后，脚本会显示：**

```
========================================
  安装完成！
========================================

  Mihomo 版本:     v1.19.24
  MetaCubeXD 版本: v1.246.3

  配置文件:        /etc/mihomo/config.yaml
  面板地址:        http://192.168.1.100:9090/ui/
  面板密码:        mihomo2024 (请尽快修改)

  测试命令:
    直连测试: curl cip.cc
    代理测试: curl ifconfig.me

========================================
```

### 2. 更新 Mihomo 和 MetaCubeXD

**更新到最新版本：**

```Bash
sudo ./scripts/mihomo-manager.sh --update
```

**更新到指定版本：**

```Bash
sudo ./scripts/mihomo-manager.sh --update -v v1.19.22
```

**更新过程说明：**

脚本会自动执行以下步骤：
1. 获取最新版本信息
2. 检查是否需要更新（已是最新则跳过）
3. 备份配置文件
4. 下载所有资源（Mihomo 和 MetaCubeXD）
5. 停止 Mihomo 服务
6. 替换内核文件和面板文件
7. 重启服务

> 更新失败时会自动回滚到更新前的状态。

**更新完成后，脚本会显示：**

```
========================================
  更新完成！
========================================

  Mihomo:     v1.19.22 -> v1.19.24
  MetaCubeXD: v1.241.3 -> v1.246.3

  请在浏览器按 Ctrl+F5 强制刷新面板缓存
========================================
```

### 3. 卸载 Mihomo 和 MetaCubeXD

```Bash
sudo ./scripts/mihomo-manager.sh --uninstall
```

**卸载过程说明：**

脚本会直接执行卸载，不做备份。卸载步骤：
1. 停止 Mihomo 服务
2. 禁用 systemd 服务
3. 删除服务文件
4. 删除 Mihomo 可执行文件
5. 删除配置目录
6. 清理缓存文件

### 4. 检查版本更新

```Bash
./scripts/mihomo-manager.sh --check
```

**输出示例：**

```
[INFO] 检查最新版本...

组件            当前版本        最新版本        状态
--------------------------------------------------------
Mihomo         v1.19.24        v1.19.24        已是最新
MetaCubeXD     v1.246.3        v1.246.3        已是最新
```

### 5. 查看版本信息

```Bash
./scripts/mihomo-manager.sh --version
```

**输出示例：**

```
mihomo-manager: 1.1.0
Mihomo:         v1.19.24
MetaCubeXD:     v1.246.3
```

## 三、使用代理

如果网络环境需要代理才能访问 GitHub，可以使用 `--proxy` 参数指定代理地址：

**使用本地代理（只指定端口）：**

```Bash
# 使用本地 7890 端口的代理
sudo ./scripts/mihomo-manager.sh --update --proxy 7890

# 检查更新时使用代理
./scripts/mihomo-manager.sh --check --proxy 7890
```

**使用远程代理（指定 IP 和端口）：**

```Bash
# 使用远程代理服务器
sudo ./scripts/mihomo-manager.sh --update --proxy 192.168.1.100:7890
```

**代理说明：**
- 支持 HTTP 和 SOCKS5 代理协议
- 代理地址格式：`端口` 或 `IP:端口`
- 脚本会自动检测本地 Mihomo 代理，也可手动指定

## 四、参数说明

| 参数 | 说明 |
|------|------|
| `--install, -i <url\|file.yaml>` | 安装 Mihomo 和 MetaCubeXD |
| `--update, -u` | 更新到最新版本 |
| `--update, -u -v <version>` | 更新到指定版本（如 `v1.19.22`） |
| `--uninstall` | 完全卸载 |
| `--version, -V` | 显示版本信息 |
| `--check, -c` | 检查是否有新版本 |
| `--proxy, -p <port\|host:port>` | 指定代理地址 |
| `--verbose` | 显示详细执行过程 |
| `--quiet` | 静默模式（只显示错误） |
| `--help, -h` | 显示帮助信息 |

## 五、故障排除

### 1. 脚本无法运行

```Bash
# 检查脚本权限
ls -la scripts/mihomo-manager.sh

# 如果没有执行权限，添加权限
chmod +x scripts/mihomo-manager.sh
```

### 2. 下载失败

如果下载失败，脚本会自动重试 3 次。如果仍然失败，请检查：
- 网络连接是否正常
- 是否需要配置代理（使用 `--proxy` 参数）
- GitHub 是否可访问

### 3. 更新时代理不可用

脚本会自动检测当前运行的 Mihomo 代理，并使用它下载更新资源。如果代理不可用，脚本会回退到直连下载。

### 4. 安装后无法访问面板

```Bash
# 检查 Mihomo 服务状态
sudo systemctl status mihomo

# 检查配置文件语法
sudo mihomo -d /etc/mihomo -t

# 检查防火墙设置
sudo ufw status
sudo ufw allow 9090/tcp
```

### 5. 查看详细日志

```Bash
# 查看 Mihomo 服务日志
sudo journalctl -u mihomo -f

# 使用 --verbose 查看脚本详细执行过程
sudo ./scripts/mihomo-manager.sh --install -i config.yaml --verbose
```

## 六、配置文件位置

| 文件 | 说明 |
|------|------|
| `scripts/mihomo-manager.sh` | 管理脚本 |
| `conf/merge.yaml` | 默认合并配置（TUN、DNS、sniffer 等） |
| `/usr/local/bin/mihomo` | Mihomo 可执行文件 |
| `/etc/mihomo/config.yaml` | Mihomo 运行配置文件 |
| `/etc/mihomo/ui/` | MetaCubeXD 前端面板文件 |
| `/etc/systemd/system/mihomo.service` | systemd 服务文件 |

## 七、备份与恢复

**自动备份：**

脚本在更新前会自动备份配置文件到 `/tmp/mihomo-backup-YYYYMMDDHHMMSS/` 目录，更新成功后自动删除。

**手动备份：**

```Bash
sudo cp -r /etc/mihomo ~/mihomo-backup-$(date +%Y%m%d%H%M%S)
```

**恢复配置：**

```Bash
# 停止服务
sudo systemctl stop mihomo

# 恢复配置文件
sudo cp -r ~/mihomo-backup-YYYYMMDDHHMMSS/config.yaml /etc/mihomo/

# 验证配置
sudo mihomo -d /etc/mihomo -t

# 重启服务
sudo systemctl restart mihomo
```
