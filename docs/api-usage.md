# Mihomo API 命令行工具

`clashapi` 是基于 Mihomo RESTful API 封装的命令行工具，无需 Web UI 即可管理代理节点、流量、连接和规则。

---

## 初始化

### 新安装用户

运行 `bash install.sh` 安装时会自动配置，安装完成后开启新终端即可使用。

### 已安装用户

如果已经安装了 clash-for-lab，需要更新脚本文件：

```bash
# 进入项目目录
cd /path/to/clash-for-lab

# 复制新脚本到安装目录
cp script/clashapi.sh ~/tools/mihomo/script/

# 更新 shell RC 加载配置（二选一）
# 方法一：手动在 ~/.bashrc 或 ~/.zshrc 中，将原有的 source 行替换为：
source ~/tools/mihomo/script/common.sh && source ~/tools/mihomo/script/clashapi.sh && source ~/tools/mihomo/script/clashctl.sh && watch_proxy

# 方法二：重新安装（会自动更新所有配置）
bash uninstall.sh && bash install.sh
```

更新后重新打开终端，或执行 `source ~/.bashrc` 生效。

### 依赖

- `curl` — HTTP 请求（系统通常已安装）
- `jq` — JSON 解析（必需）

```bash
# Debian/Ubuntu
apt install -y jq

# CentOS/RHEL
yum install -y jq

# macOS
brew install jq
```

### 验证

```bash
clashapi version     # 能正常返回版本号即初始化成功
clash api version    # 等价写法，通过 clash 主命令调用
```

---

## 使用方式

支持两种调用方式，效果完全相同：

```bash
clashapi <命令> [参数]     # 直接调用
clash api <命令> [参数]    # 通过 clash 主命令调用
```

---

## 命令参考

### 代理节点管理

#### 查看所有代理组及当前节点

```bash
clashapi groups
```

输出示例：

```
Proxies  →  香港-01
YouTube  →  美国-03
Telegram →  新加坡-02
OpenAI   →  日本-05
Final    →  Proxies
```

#### 查看代理组的可用节点

```bash
clashapi nodes              # 默认查看 Proxies 组
clashapi nodes YouTube      # 查看 YouTube 组
```

#### 查看当前选中的节点

```bash
clashapi now                # 查看所有组的当前节点
clashapi now Proxies        # 查看指定组的当前节点
```

#### 切换节点

```bash
clashapi select Proxies 香港-01
clashapi select YouTube 美国-03
```

#### 测试单个节点延迟

```bash
clashapi delay 香港-01           # 默认超时 5000ms
clashapi delay 香港-01 3000      # 指定超时 3000ms
```

#### 批量测速代理组

```bash
clashapi benchmark              # 默认测速 Proxies 组
clashapi benchmark YouTube      # 测速 YouTube 组
```

#### 自动选择最快节点

```bash
clashapi fastest                # Proxies 组自动选最快
clashapi fastest YouTube        # YouTube 组自动选最快
```

---

### 流量与连接

#### 查看活跃连接

```bash
clashapi connections
```

#### 关闭所有连接

```bash
clashapi flush
```

---

### 配置管理

#### 查看运行配置

```bash
clashapi config
```

#### 切换运行模式

```bash
clashapi mode rule      # 规则模式（按规则分流）
clashapi mode global    # 全局模式（所有流量走代理）
clashapi mode direct    # 直连模式（所有流量直连）
```

#### 重载配置文件

```bash
clashapi reload
```

---

### 规则查询

```bash
clashapi rules              # 查看规则总数和前 20 条
clashapi rules google       # 按关键词过滤规则
clashapi rules telegram     # 查找 telegram 相关规则
```

---

### DNS 查询

```bash
clashapi dns google.com         # 查询 A 记录
clashapi dns google.com AAAA    # 查询 AAAA 记录
```

---

### 实时日志

```bash
clashapi log            # 默认 info 级别
clashapi log debug      # debug 级别（最详细）
clashapi log warning    # warning 级别
```

按 `Ctrl+C` 退出日志流。

---

### 版本信息

```bash
clashapi version
```

---

## 常用场景

### 场景一：快速切换到最快节点

```bash
clashapi fastest
```

### 场景二：YouTube 走美国节点

```bash
clashapi nodes YouTube          # 查看可用节点
clashapi select YouTube 美国-03  # 切换节点
```

### 场景三：排查连接问题

```bash
clashapi rules google.com       # 检查域名匹配哪条规则
clashapi dns google.com         # 检查 DNS 解析结果
clashapi connections            # 查看活跃连接
clashapi log debug              # 查看详细日志
```

### 场景四：临时全局代理

```bash
clashapi mode global            # 开启全局代理
# ... 完成操作后 ...
clashapi mode rule              # 恢复规则模式
```

---

## 原始 API 参考

以上命令底层调用 Mihomo RESTful API，默认地址 `http://127.0.0.1:9090`。

如果配置了 `secret`（通过 `clash secret` 查看），直接使用 curl 时需加认证头：

```bash
curl -s -H 'Authorization: Bearer <SECRET>' http://127.0.0.1:9090/proxies | jq .
```

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | `/proxies` | 所有代理信息 |
| GET | `/proxies/:name` | 指定代理详情 |
| PUT | `/proxies/:name` | 切换 Selector 代理组节点 |
| GET | `/proxies/:name/delay` | 测试节点延迟 |
| GET | `/group/:name/delay` | 批量测速代理组 |
| GET | `/connections` | 活跃连接列表 |
| DELETE | `/connections` | 关闭所有连接 |
| DELETE | `/connections/:id` | 关闭指定连接 |
| GET | `/configs` | 当前运行配置 |
| PATCH | `/configs` | 更新部分配置（mode 等） |
| PUT | `/configs` | 重载配置文件 |
| GET | `/rules` | 规则列表 |
| GET | `/dns/query` | DNS 查询 |
| GET | `/logs` | 实时日志流 |
| GET | `/traffic` | 实时流量数据 |
| GET | `/version` | 版本信息 |
