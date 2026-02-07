# Docker 镜像中心搭建指南

本文档介绍如何在 Docker 上搭建私有镜像中心（Docker Registry），实现镜像的存储、管理和分发。

## 目录

- [概述](#概述)
- [方案选择](#方案选择)
- [快速开始](#快速开始)
- [生产环境部署](#生产环境部署)
- [其他方案参考](#其他方案参考)
- [镜像管理](#镜像管理)
- [安全配置](#安全配置)
- [常见问题](#常见问题)

---

## 概述

Docker 镜像中心（Registry）是用于存储和分发 Docker 镜像的服务。搭建私有镜像中心的主要优势：

- **安全性**：镜像存储在内部网络，避免敏感信息泄露
- **速度**：内网传输速度快，减少外网依赖
- **控制**：完全控制镜像的版本和访问权限
- **成本**：避免公有云镜像仓库的费用

---

## 方案选择

### 推荐方案：Docker Registry（官方基础版）⭐

**本文档主要介绍 Docker Registry 的部署和使用**

**适用场景**：
- 小团队、开发测试环境
- 需要轻量级私有镜像仓库
- 对高级功能要求不高的场景

**优点**：
- ✅ 轻量级，部署简单
- ✅ 官方维护，稳定可靠
- ✅ 资源占用少
- ✅ 配置灵活，易于定制

**局限性**：
- 功能相对简单，无内置 Web UI（可通过第三方 UI 补充）
- 基础的用户认证（通过 htpasswd）
- 无内置镜像扫描功能

---

### 其他方案参考

> [!NOTE]
> 以下方案仅作为参考，如果您需要更高级的功能，可以考虑这些方案。

#### Harbor（企业级方案）

**适用场景**：生产环境、大型团队、需要完整权限管理和镜像扫描

**特点**：
- 完整的 Web 管理界面
- 用户权限管理（RBAC）
- 镜像漏洞扫描
- 镜像签名和复制
- 支持 Helm Chart 存储

**缺点**：部署相对复杂，资源占用较大

#### Nexus Repository（多格式仓库）

**适用场景**：需要统一管理多种制品（Maven、npm、Docker等）

**特点**：支持多种仓库格式，统一管理平台

---

## 快速开始

### 方式一：使用 Docker Registry（最简单）

#### 1. 启动 Registry 容器

```bash
# 创建数据存储目录
mkdir -p /data/docker-registry

# 启动 Registry（HTTP，仅用于测试）
docker run -d \
  --name registry \
  --restart=always \
  -p 5000:5000 \
  -v /data/docker-registry:/var/lib/registry \
  registry:2
```

#### 2. 验证服务

```bash
# 检查服务状态
curl http://localhost:5000/v2/_catalog

# 应该返回：{"repositories":[]}
```

#### 3. 推送镜像到私有仓库

```bash
# 拉取一个测试镜像
docker pull ubuntu:20.04

# 标记镜像
docker tag ubuntu:20.04 localhost:5000/ubuntu:20.04

# 推送到私有仓库
docker push localhost:5000/ubuntu:20.04

# 验证推送成功
curl http://localhost:5000/v2/_catalog
# 返回：{"repositories":["ubuntu"]}
```

#### 4. 从私有仓库拉取镜像

```bash
# 删除本地镜像
docker rmi localhost:5000/ubuntu:20.04

# 从私有仓库拉取
docker pull localhost:5000/ubuntu:20.04
```

---

## 生产环境部署

### 使用 Docker Compose 部署（带 HTTPS 和认证）

#### 1. 创建项目目录结构

```bash
mkdir -p ~/docker-registry/{auth,certs,data}
cd ~/docker-registry
```

#### 2. 生成 SSL 证书

```bash
# 生成自签名证书（生产环境建议使用正式证书）
openssl req -newkey rsa:4096 -nodes -sha256 \
  -keyout certs/domain.key -x509 -days 365 \
  -out certs/domain.crt \
  -subj "/C=CN/ST=Beijing/L=Beijing/O=MyCompany/CN=registry.example.com"
```

#### 3. 创建认证文件

```bash
# 安装 htpasswd 工具（如果没有）
# Ubuntu/Debian: apt-get install apache2-utils
# CentOS/RHEL: yum install httpd-tools
# macOS: brew install httpd

# 创建用户（用户名：admin，密码：admin123）
htpasswd -Bbn admin admin123 > auth/htpasswd

# 添加更多用户
htpasswd -Bb auth/htpasswd user1 password1
```

#### 4. 创建 docker-compose.yml

```yaml
version: '3.8'

services:
  registry:
    image: registry:2
    container_name: docker-registry
    restart: always
    ports:
      - "5000:5000"
    environment:
      # 启用删除功能
      REGISTRY_STORAGE_DELETE_ENABLED: "true"
      # 认证配置
      REGISTRY_AUTH: htpasswd
      REGISTRY_AUTH_HTPASSWD_REALM: Registry Realm
      REGISTRY_AUTH_HTPASSWD_PATH: /auth/htpasswd
      # HTTPS 配置
      REGISTRY_HTTP_TLS_CERTIFICATE: /certs/domain.crt
      REGISTRY_HTTP_TLS_KEY: /certs/domain.key
    volumes:
      - ./data:/var/lib/registry
      - ./auth:/auth
      - ./certs:/certs
    networks:
      - registry-net

  # 可选：添加 Web UI（registry-ui）
  registry-ui:
    image: joxit/docker-registry-ui:latest
    container_name: registry-ui
    restart: always
    ports:
      - "8080:80"
    environment:
      - REGISTRY_TITLE=My Docker Registry
      - REGISTRY_URL=https://registry:5000
      - DELETE_IMAGES=true
      - SHOW_CONTENT_DIGEST=true
      - NGINX_PROXY_PASS_URL=https://registry:5000
      - SINGLE_REGISTRY=true
    depends_on:
      - registry
    networks:
      - registry-net

networks:
  registry-net:
    driver: bridge
```

#### 5. 启动服务

```bash
# 启动服务
docker-compose up -d

# 查看日志
docker-compose logs -f

# 检查服务状态
docker-compose ps
```

#### 6. 配置客户端

```bash
# 方式一：将证书添加到系统信任（推荐）
# Linux
sudo mkdir -p /etc/docker/certs.d/registry.example.com:5000
sudo cp certs/domain.crt /etc/docker/certs.d/registry.example.com:5000/ca.crt
sudo systemctl restart docker

# macOS
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain certs/domain.crt

# 方式二：配置 Docker 允许不安全的仓库（不推荐生产环境）
# 编辑 /etc/docker/daemon.json
{
  "insecure-registries": ["registry.example.com:5000"]
}
# 重启 Docker
sudo systemctl restart docker
```

#### 7. 登录并使用

```bash
# 登录私有仓库
docker login registry.example.com:5000
# 输入用户名：admin
# 输入密码：admin123

# 推送镜像
docker tag nginx:latest registry.example.com:5000/nginx:latest
docker push registry.example.com:5000/nginx:latest

# 拉取镜像
docker pull registry.example.com:5000/nginx:latest

# 访问 Web UI
# 浏览器打开：http://localhost:8080
```

---

## 其他方案参考

> [!TIP]
> **本节仅供参考**。如果您只需要基础的镜像仓库功能,使用上面的 Docker Registry 方案即可。

### Harbor（企业级方案）

Harbor 是由 VMware 开源的企业级 Docker Registry 服务器，提供了比官方 Registry 更丰富的功能。

**适用场景**：
- 大型团队需要完整的用户权限管理（RBAC）
- 需要镜像漏洞扫描和安全合规
- 需要多数据中心镜像复制和同步
- 需要 Helm Chart 仓库支持

**主要特性**：
- 🎨 完整的 Web 管理界面
- 👥 基于角色的访问控制（RBAC）
- 🔍 镜像漏洞扫描（集成 Trivy）
- ✍️ 镜像签名和内容信任
- 🔄 镜像复制和同步
- 📦 Helm Chart 仓库
- 📊 审计日志和操作记录

**参考资源**：
- [Harbor 官方文档](https://goharbor.io/docs/)
- [Harbor GitHub](https://github.com/goharbor/harbor)
- [Harbor 安装指南](https://goharbor.io/docs/latest/install-config/)

### Nexus Repository

Nexus Repository 是一个通用的制品仓库管理器，支持多种格式。

**适用场景**：
- 需要统一管理多种制品（Maven、npm、Docker、PyPI 等）
- 已经在使用 Nexus 管理其他制品，希望统一平台

**主要特性**：
- 支持多种仓库格式（Maven、npm、Docker、PyPI、RubyGems 等）
- 统一的管理界面
- 代理和缓存功能
- 细粒度的权限控制

**参考资源**：
- [Nexus Repository 官方文档](https://help.sonatype.com/repomanager3)



---

## 镜像管理

### 查看镜像列表

```bash
# 使用 API 查看所有镜像
curl -u admin:admin123 https://registry.example.com:5000/v2/_catalog

# 查看镜像标签
curl -u admin:admin123 https://registry.example.com:5000/v2/nginx/tags/list
```

### 删除镜像

```bash
# 需要启用 REGISTRY_STORAGE_DELETE_ENABLED
# 1. 获取镜像 digest
curl -I -H "Accept: application/vnd.docker.distribution.manifest.v2+json" \
  https://registry.example.com:5000/v2/nginx/manifests/latest

# 2. 删除镜像
curl -X DELETE https://registry.example.com:5000/v2/nginx/manifests/sha256:xxx

# 3. 运行垃圾回收
docker exec registry bin/registry garbage-collect /etc/docker/registry/config.yml
```

### 镜像标签管理

```bash
# 列出所有标签
docker images registry.example.com:5000/nginx

# 删除本地标签
docker rmi registry.example.com:5000/nginx:old-tag

# 重新标记
docker tag registry.example.com:5000/nginx:latest \
  registry.example.com:5000/nginx:v1.0
```

---

## 安全配置

### 1. 网络安全

```bash
# 使用防火墙限制访问
# 仅允许内网访问
sudo ufw allow from 192.168.1.0/24 to any port 5000

# 使用 Nginx 反向代理
# /etc/nginx/sites-available/registry
upstream docker-registry {
    server localhost:5000;
}

server {
    listen 443 ssl;
    server_name registry.example.com;

    ssl_certificate /path/to/cert.crt;
    ssl_certificate_key /path/to/cert.key;

    client_max_body_size 0;
    chunked_transfer_encoding on;

    location / {
        proxy_pass http://docker-registry;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_read_timeout 900;
    }
}
```

### 2. 镜像签名（内容信任）

```bash
# 启用 Docker Content Trust
export DOCKER_CONTENT_TRUST=1
export DOCKER_CONTENT_TRUST_SERVER=https://notary.example.com

# 推送签名镜像
docker push registry.example.com:5000/nginx:latest
# 会提示输入签名密钥密码

# 拉取时自动验证签名
docker pull registry.example.com:5000/nginx:latest
```

### 3. 定期安全审计

```bash
# 查看访问日志
docker logs registry | grep "GET\|POST\|DELETE"

# 查看详细日志
docker-compose logs -f registry
```

---

## 常见问题

### 1. 推送镜像时报错：x509: certificate signed by unknown authority

**解决方案**：

```bash
# 将自签名证书添加到系统信任
# Linux
sudo cp domain.crt /usr/local/share/ca-certificates/
sudo update-ca-certificates

# 或配置 Docker daemon
# /etc/docker/daemon.json
{
  "insecure-registries": ["registry.example.com:5000"]
}
sudo systemctl restart docker
```

### 2. 磁盘空间不足

**解决方案**：

```bash
# 清理未使用的镜像
docker system prune -a

# Registry 垃圾回收
docker exec registry bin/registry garbage-collect \
  /etc/docker/registry/config.yml
```

### 3. 无法删除镜像

**解决方案**：

```bash
# 确保启用了删除功能
# docker-compose.yml
environment:
  REGISTRY_STORAGE_DELETE_ENABLED: "true"

# 重启服务
docker-compose restart
```

### 4. 推送大镜像超时

**解决方案**：

```bash
# 增加 Nginx 超时时间
# /etc/nginx/nginx.conf
http {
    client_max_body_size 0;
    proxy_read_timeout 900s;
    proxy_send_timeout 900s;
}

# Docker daemon 配置
# /etc/docker/daemon.json
{
  "max-concurrent-uploads": 5,
  "max-concurrent-downloads": 5
}
```

---

## 性能优化

### 1. 存储优化

```bash
# 使用 SSD 存储
# 配置存储驱动
# docker-compose.yml
volumes:
  - /ssd/docker-registry:/var/lib/registry

# 启用存储缓存
environment:
  REGISTRY_STORAGE_CACHE_BLOBDESCRIPTOR: redis
  REGISTRY_REDIS_ADDR: redis:6379
```

### 2. 网络优化

```bash
# 启用 CDN 加速
# 使用对象存储（S3、OSS）
environment:
  REGISTRY_STORAGE: s3
  REGISTRY_STORAGE_S3_REGION: us-east-1
  REGISTRY_STORAGE_S3_BUCKET: my-registry
  REGISTRY_STORAGE_S3_ACCESSKEY: xxx
  REGISTRY_STORAGE_S3_SECRETKEY: xxx
```

---

## 监控和告警

### 使用 Prometheus 监控

```yaml
# docker-compose.yml 添加
services:
  prometheus:
    image: prom/prometheus
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
```

**prometheus.yml**:

```yaml
scrape_configs:
  - job_name: 'registry'
    static_configs:
      - targets: ['registry:5000']
```

---

## 参考资源

### Docker Registry
- [Docker Registry 官方文档](https://docs.docker.com/registry/)
- [Docker Registry API](https://docs.docker.com/registry/spec/api/)
- [Docker Registry UI (joxit)](https://github.com/Joxit/docker-registry-ui)

### 其他方案（参考）
- [Harbor 官方文档](https://goharbor.io/docs/)
- [Nexus Repository 文档](https://help.sonatype.com/repomanager3)

---

## 总结

### 推荐使用 Docker Registry

**本文档主要推荐使用 Docker Registry**，它能满足大多数场景的需求：

- ✅ **开发测试环境**：使用基础 Docker Registry（HTTP + 基础认证）
- ✅ **小团队/内网环境**：Docker Registry + Web UI（本文档的生产环境部署方案）
- ✅ **对外服务/严格安全要求**：Docker Registry + HTTPS + 认证

### 何时考虑 Harbor？

仅在以下情况下才需要考虑 Harbor（参考方案）：
- 需要复杂的多用户权限管理（RBAC）
- 需要镜像漏洞扫描和安全合规
- 需要多数据中心镜像同步
- 需要 Helm Chart 仓库

### 生产环境最佳实践

使用 Docker Registry 时建议：
- ✅ 使用 HTTPS（通过 Nginx 反向代理或直接配置）
- ✅ 启用用户认证（htpasswd）
- ✅ 定期备份数据目录
- ✅ 监控磁盘空间
- ✅ 配置日志轮转
