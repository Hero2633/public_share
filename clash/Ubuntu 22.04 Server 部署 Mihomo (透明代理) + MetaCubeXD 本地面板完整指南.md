
**环境说明：**

- **操作系统**：Ubuntu 22.04 Server (无图形界面)
    
- **系统架构**：amd64
    
- **核心软件**：Mihomo (Clash Meta) `v1.19.21`
    
- **前端面板**：MetaCubeXD `v1.241.3`
    
- **核心功能**：全局透明代理 (TUN 模式)、本地 Web UI 控制、国内外流量自动分流。
---
**本教程只配置TUN模式，不配置系统代理！！！！！！！！！**
## 一、 安装 Mihomo 内核

**1. 下载并解压核心文件**

```Bash
# 下载指定版本的压缩包 (使用 ghproxy 加速)
wget https://mirror.ghproxy.com/https://github.com/MetaCubeX/mihomo/releases/download/v1.19.21/mihomo-linux-amd64-v1.19.21.gz -O mihomo.gz

# 解压文件
gunzip mihomo.gz

# 移动到系统可执行目录并重命名
sudo mv mihomo /usr/local/bin/mihomo

# 赋予执行权限
sudo chmod +x /usr/local/bin/mihomo

# 检查安装是否成功
mihomo -v
```

## 二、 配置 Systemd 后台服务

**1. 创建服务配置文件**

```Bash
sudo nano /etc/systemd/system/mihomo.service
```

**2. 填入进阶权限配置 (支持 TUN 及高级网络接管)**

```sh
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

## 三、 配置 Mihomo (`config.yaml`)

**1. 创建配置目录**

```Bash
sudo mkdir -p /etc/mihomo
```

**2. 编辑主配置文件**

```Bash
curl -L -o /etc/mihomo/config.yaml "你的订阅连接!"
```
![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121136474.png)
注意选**择Mihomo内核**！不要选择“复制订阅”！

>如果没有`选择Mihomo内核`这一个选项，可以直接从Windows下的clash软件中导出yaml文件，然再上传到服务器，eg:
>![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121127178.png)
>然后就会跳转到对应的yaml文件，具体如下:
>![](attachments/Ubuntu%2022.04%20Server%20部署%20Mihomo%20(透明代理)%20+%20MetaCubeXD%20本地面板完整指南/file-20260326121104195.png)

**3. 修改config.yaml文件中的一些配置**

_(注意：此配置已包含 TUN、Fake-IP 以及绝对路径的 UI 指向，具体的 `proxies`、`proxy-groups` 和 `rules` 请保留你之前导入的内容)_

以下yaml文件可以直接导入config.yaml文件中，如果有字段冲突，可以以下面的配置为准!
```YAML
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
  
# 4. 流量嗅探的作用就是从纯 IP 的网络包里“抠”出真实的域名，让你的按域名分流规则（走代理或直连）绝不失效。
sniffer:
  enable: true                 # 开启嗅探开关
  force-dns-mapping: true      # 强制使用 DNS 映射（解决部分应用直接请求 IP 的问题）
  parse-pure-ip: true          # 启用纯 IP 嗅探（提取出域名后覆盖）
  override-destination: true   # 全局覆盖目标 IP 为嗅探出的真实域名
  sniff:
    HTTP:
      ports: [80, 8080-8880]
      override-destination: true
    TLS:
      ports: [443, 8443]
    QUIC:
      ports: [443, 8443]
```

**端口说明**：
- `external-controller: 0.0.0.0:9090` - API 控制端口，用于远程管理
- 访问面板时使用 `http://服务器IP:9090/ui/`

Mihomo 本身命令：
`mihomo -d /etc/mihomo -t` **(极度常用！)** 测试配置文件是否有语法错误。每次你修改了 `config.yaml`，在重启服务前**一定要**运行这个命令。如果输出 `configuration file /etc/mihomo/config.yaml test is successful`，再执行重启操作，防止配置文件写错导致断网。
## 四、 本地部署 MetaCubeXD 前端面板

为了避免因节点不通导致外部面板无法加载的问题，我们将 UI 部署在本地。

**1. 下载并解压面板资源**

```Bash
cd /etc/mihomo
# 下载最新的 v1.241.3 编译版
sudo wget https://mirror.ghproxy.com/https://github.com/MetaCubeX/metacubexd/releases/download/v1.241.3/compressed-dist.tgz -O ui.tgz

# 创建 ui 文件夹并解压
sudo mkdir -p ui
sudo tar -xzvf ui.tgz -C ui

# 清理压缩包
sudo rm ui.tgz
```

**2. 修复权限 (极其重要，避免 404)**

```Bash
sudo chown -R root:root /etc/mihomo/ui
sudo chmod -R 755 /etc/mihomo/ui
```

## 五、 启动并验证服务

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

## 六、 访问控制台与日常测试

**1. 访问面板**

在同局域网的浏览器中打开（注意结尾的 `/` 不可省略）：

👉 **`http://你的服务器IP:9090/ui/`**

- **API Base URL**: `http://你的服务器IP:9090`
    
- **Secret**: 你在 config.yaml 中设置的密码
    

**2. 连通性测试命令**

- 验证直连 (国内 IP)：`curl cip.cc`
    
- 验证代理 (海外 IP)：`curl ifconfig.me` 或 `curl ipinfo.io`
    
## 七、 后续无损更新指南 (内核与面板)

随着代理协议的升级和前端功能的迭代，定期更新可以获得更好的性能和稳定性。以下提供“手动逐条执行”和“一键全自动脚本”两种更新方式。

### 方法一：手动更新 (适用于了解具体步骤的进阶操作)

**1. 更新 Mihomo 内核 (Core)** 当 Github 发布了新版本（假设为 `vX.X.X`），依次执行：

```Bash
# 停止当前服务释放文件占用
sudo systemctl stop mihomo

# 下载新版内核 (注意替换链接中的版本号)
wget https://mirror.ghproxy.com/https://github.com/MetaCubeX/mihomo/releases/download/vX.X.X/mihomo-linux-amd64-vX.X.X.gz -O mihomo.gz

# 解压并替换旧核心
gunzip mihomo.gz
sudo mv mihomo /usr/local/bin/mihomo
sudo chmod +x /usr/local/bin/mihomo

# 重启服务并检查版本
sudo systemctl start mihomo
mihomo -v
```

**2. 更新 MetaCubeXD 前端面板 (UI)** 当面板发布了新版本（假设为 `vY.Y.Y`），依次执行：

```Bash
# 清空旧的前端文件 (安全操作，不会删掉 config.yaml)
sudo rm -rf /etc/mihomo/ui/*

# 下载新版面板压缩包 (注意替换链接中的版本号)
wget https://mirror.ghproxy.com/https://github.com/MetaCubeX/metacubexd/releases/download/vY.Y.Y/compressed-dist.tgz -O /etc/mihomo/ui.tgz

# 解压到 ui 目录并清理压缩包
sudo tar -xzvf /etc/mihomo/ui.tgz -C /etc/mihomo/ui
sudo rm /etc/mihomo/ui.tgz

# 修复权限并重启服务加载新网页
sudo chown -R root:root /etc/mihomo/ui
sudo chmod -R 755 /etc/mihomo/ui
sudo systemctl restart mihomo
```

_(注意：更新面板后，务必在浏览器中按下 `Ctrl + F5` 强制刷新缓存，否则可能显示错位。)_

---

### 方法二：一键自动更新脚本 (强烈推荐)

为了省去每次复制粘贴命令的麻烦，你可以创建一个自动化 Shell 脚本，以后只需运行这个脚本，输入你想更新的版本号即可自动完成全套流程。

**1. 创建脚本文件**

```Bash
nano ~/update_mihomo.sh
```

**2. 粘贴以下脚本代码**

```Bash
#!/bin/bash
# Mihomo & UI 一键无损更新脚本

echo "====================================="
echo "  Mihomo & MetaCubeXD 一键更新工具"
echo "====================================="
echo "请选择你要更新的组件:"
echo "1) 更新 Mihomo 内核 (Core)"
echo "2) 更新 MetaCubeXD 面板 (UI)"
echo "3) 退出"
read -p "请输入选项 [1-3]: " choice

if [ "$choice" == "1" ]; then
    read -p "请输入你要更新的 Mihomo 版本号 (例如 v1.19.22): " core_version
    echo "[1/4] 停止 Mihomo 服务..."
    sudo systemctl stop mihomo
    echo "[2/4] 正在下载 Mihomo $core_version ..."
    wget "https://mirror.ghproxy.com/https://github.com/MetaCubeX/mihomo/releases/download/${core_version}/mihomo-linux-amd64-${core_version}.gz" -O /tmp/mihomo.gz
    echo "[3/4] 解压并替换核心..."
    gunzip -f /tmp/mihomo.gz
    sudo mv /tmp/mihomo /usr/local/bin/mihomo
    sudo chmod +x /usr/local/bin/mihomo
    echo "[4/4] 启动服务..."
    sudo systemctl start mihomo
    echo "✅ Mihomo 内核更新完成！当前版本："
    mihomo -v

elif [ "$choice" == "2" ]; then
    read -p "请输入你要更新的 UI 面板版本号 (例如 v1.242.0): " ui_version
    echo "[1/4] 清理旧版本 UI 文件..."
    sudo rm -rf /etc/mihomo/ui/*
    echo "[2/4] 正在下载 MetaCubeXD $ui_version ..."
    wget "https://mirror.ghproxy.com/https://github.com/MetaCubeX/metacubexd/releases/download/${ui_version}/compressed-dist.tgz" -O /tmp/ui.tgz
    echo "[3/4] 解压并配置权限..."
    sudo tar -xzvf /tmp/ui.tgz -C /etc/mihomo/ui
    sudo chown -R root:root /etc/mihomo/ui
    sudo chmod -R 755 /etc/mihomo/ui
    rm /tmp/ui.tgz
    echo "[4/4] 重启 Mihomo 服务..."
    sudo systemctl restart mihomo
    echo "✅ 前端面板更新完成！请在浏览器使用 Ctrl+F5 强制刷新网页。"

else
    echo "已退出更新。"
fi
```

_(保存并退出：`Ctrl+O`, `Enter`, `Ctrl+X`)_

**3. 赋予执行权限**

```Bash
chmod +x ~/update_mihomo.sh
```

**4. 日常使用方法** 以后当需要更新时，只需在终端执行：

```Bash
./update_mihomo.sh
```

按照屏幕上的中文提示输入对应的数字和版本号，脚本就会在后台帮你搞定一切。