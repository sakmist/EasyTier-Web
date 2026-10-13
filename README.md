# EasyTier-Web (Docker)

把飞牛 OS(fnOS)的 **EasyTier-Web** 套件(.fpk)转成 Docker 镜像的版本，可以直接跑在任何支持 Docker 的
Linux 主机上(群晖、威联通、fnOS、Ubuntu/Debian、树莓派等)。

- **EasyTier** 是一个由 Rust + Tokio 驱动的简单、安全、去中心化的异地组网(内网穿透)方案。
- **EasyTier-Web** 为 EasyTier 提供 Web 管理页面和 REST API，让组网配置可视化。

镜像里包含原套件的两个程序:

| 程序 | 作用 | 端口 |
| --- | --- | --- |
| `easytier-web-embed` | Web 管理页面 + REST API + 配置下发服务 | `11211/tcp`(页面/API)、`22020/udp`(配置服务，仅本机) |
| `easytier-core` | EasyTier 组网守护进程，从上面的配置服务拉取配置 | `11010`、`11011`(tcp/udp 监听) |

版本: EasyTier `2.4.5`(与原套件二进制一致)。

---

## 快速开始

### 方式一: docker compose(推荐)

```bash
git clone <本仓库地址> EasyTier-Web
cd EasyTier-Web
docker compose up -d --build
```

浏览器打开 `http://<主机IP>:11211`，初始用户名和密码都是 **admin**，登录后即可在左侧
「设备列表」里添加网络。

> 页面里的「API 主机」会自动指向本容器，无需手动填写。若显示的是
> `config-server.easytier.cn`，说明自动探测没生效，见下方「关于『API 主机』」。

### 方式二: docker run

```bash
docker build -t easytier-web:2.4.5 .

docker run -d \
  --name easytier-web \
  --restart unless-stopped \
  --network host \
  --cap-add NET_ADMIN --cap-add NET_RAW \
  --device /dev/net/tun:/dev/net/tun \
  -v "$PWD/data:/data" \
  -e TZ=Asia/Shanghai \
  easytier-web:2.4.5
```

### 方式三: 直接用现成镜像

```bash
# 从 GitHub Container Registry 拉取(如果已发布)
docker pull ghcr.io/<你的用户名>/easytier-web:2.4.5
```

---

## 为什么默认用 host 网络

EasyTier 需要 **创建 TUN 虚拟网卡、写系统路由表、做 UDP NAT 打洞**。这些操作只有在容器与宿主机
共享网络命名空间(`network_mode: host`)时才最可靠，这也是 EasyTier 官方镜像的做法。

因此本容器同时需要:

- `cap_add: NET_ADMIN`(建 TUN、改路由)、`NET_RAW`(打洞)
- `--device /dev/net/tun`

如果你必须用 bridge 网络，请改用 `docker-compose.bridge.yml`，它默认开启 `NO_TUN=1`
并映射端口。注意 bridge 模式下宿主机无法自动通过容器访问 VPN 内的其他节点，需要配合
EasyTier 的子网代理(subnet proxy)使用。

---

## 配置

### 端口

Web 端口有两种改法，优先级从高到低:

1. 环境变量 `UIPORT`(compose 里取消注释 `UIPORT: "11211"`)
2. 数据目录下的 `config.json` 里的 `uiport` 字段
3. 默认 `11211`

`config.json` 会在首次启动时自动生成:

```json
{
  "uiport": "11211"
}
```

> 改了端口后，healthcheck 会自动读取 `config.json` 里的新端口，无需额外配置。

### 环境变量

| 变量 | 默认值 | 说明 |
| --- | --- | --- |
| `TZ` | `Asia/Shanghai` | 时区 |
| `UIPORT` | (空) | Web/API 端口，覆盖 `config.json` |
| `CONFIG_SERVER_PORT` | `22020` | web 与 core 之间的配置下发端口 |
| `NO_TUN` | `0` | 设为 `1` 时 core 不创建 TUN 设备 |
| `API_HOST` | 自动检测 | 页面里「API 主机」指向的地址，如 `http://192.168.1.12:11211` |
| `AUTO_API_HOST` | `1` | 设为 `0` 关闭 `API_HOST` 自动检测 |
| `ET_CORE_EXTRA_ARGS` | (空) | 追加给 `easytier-core` 的参数 |
| `ET_WEB_EXTRA_ARGS` | (空) | 追加给 `easytier-web-embed` 的参数 |

### 关于「API 主机」

原 fnOS 套件的说明里要求用户手动把 API 主机改成 `http://<本机IP>:11211`，因为打包进前端的
默认值指向 EasyTier 的官方服务器 `config-server.easytier.cn`。

本镜像在启动时会自动探测宿主机 IP 并加上 `--api-host`，让页面开箱即用、直接连到本容器。
探测逻辑取默认路由的源地址(host 网络下即宿主机的局域网 IP)；如果探测结果不对(bridge 网络、
反向代理、多网卡等场景)，显式设置 `API_HOST` 即可，或设 `AUTO_API_HOST=0` 关闭自动探测。

`easytier-core` 的绝大多数参数都支持 `ET_*` 形式的环境变量，例如
`ET_NETWORK_NAME`、`ET_NETWORK_SECRET`、`ET_PEERS`、`ET_HOSTNAME` 等，
可以直接通过 compose 的 `environment` 传入。

### 数据持久化

所有状态都放在挂载到 `/data` 的目录里:

```
data/
├── config.json   # 端口等配置
├── et.db         # sqlite 数据库(用户、设备、网络配置)
└── logs/         # 运行日志
```

备份/迁移时整个 `data/` 目录拷走即可。

---

## 部署到 NAS

### 1Panel

1. 把本仓库放到 NAS 上，或用 1Panel 的「文件」上传。
2. 在 1Panel 的「容器 → 编排」中新建编排，粘贴 `docker-compose.yml` 内容，
   或直接选择仓库目录下的 compose 文件。
3. 构建并启动，然后在浏览器访问 `http://<NAS IP>:11211`。

因为 1Panel 以 root 管理 Docker，host 网络、`NET_ADMIN`、`/dev/net/tun` 都能正常授予。

### 命令行部署

仓库里的 `scripts/deploy.sh` 封装了「构建 → 启动 → 健康检查」流程:

```bash
# 在 NAS 上(需要能访问 docker)
sudo ./scripts/deploy.sh
```

若 NAS 上不方便构建，可以在本机构建后导出镜像再导入:

```bash
# 本机
docker build -t easytier-web:2.4.5 .
docker save easytier-web:2.4.5 | gzip > easytier-web-2.4.5.tar.gz
scp easytier-web-2.4.5.tar.gz user@nas:/tmp/

# NAS
gunzip -c /tmp/easytier-web-2.4.5.tar.gz | docker load
docker compose up -d
```

---

## 与原 .fpk 套件的对应关系

| 原套件 | 本镜像 |
| --- | --- |
| `cmd/main` 里的两个后台进程 | `docker/entrypoint.sh` 统一拉起并做信号转发 |
| `app/server/easytier-*` 二进制 | 原样复制到镜像 `/app/server/` |
| `TRIM_APPDEST/server/data/et.db` | `/data/et.db`(挂载卷) |
| 数据目录下的 `config.json` | `/data/config.json`(逻辑一致) |
| `run-as: root` 权限 | 容器内 root + `NET_ADMIN`/`NET_RAW` + `/dev/net/tun` |
| 「无 tun 模式非 root」版本 | 设置 `NO_TUN=1` |

原始 fnOS 打包文件(cmd、config、manifest、ui)保留在 `fnos/` 目录下，方便对照。

---

## 端口一览

| 端口 | 协议 | 用途 |
| --- | --- | --- |
| 11211 | tcp | Web 管理页面 + REST API |
| 22020 | udp | 配置下发服务(容器内部 loopback，无需对外暴露) |
| 11010 | tcp/udp | EasyTier 默认监听端口，需要对外放行才能被其他节点连上 |
| 11011 | tcp/udp | ws / wireguard 监听端口 |
| 15888 | tcp | RPC portal(默认只监听 localhost) |

> 11010 是 EasyTier 的默认端口。如果宿主机上已经跑着别的 EasyTier 实例或容器，请先停掉，
> 否则会端口冲突。

---

## 常见问题

**页面打不开?**
`docker logs easytier-web` 看日志；确认 `11211` 没有被占用，且防火墙放行。

**其他节点连不上本机?**
确认宿主机的 `11010`(tcp/udp)在防火墙/路由器上已放行，并且容器是 host 网络。

**想用非 root / 无 TUN?**
设置 `NO_TUN=1`。此时 core 不建 TUN，需要通过子网代理访问其他节点。

**日志太大?**
compose 里已经限制容器 stdout 日志为 10MB × 3 个文件；`/data/logs/` 下的文件日志由
`--file-log-size` 控制(默认 100MB)。

---

## 许可

本仓库只是把上游 EasyTier 的二进制重新打包成 Docker 镜像。
EasyTier 本身使用 **LGPL-3.0** 许可，详见 <https://github.com/EasyTier/EasyTier>。

原始 fnOS 套件来自 <https://github.com/FNOSP/App.Bin.EasyTier-Web>。
