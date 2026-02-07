# Docker Registry 快速参考

## 快速开始

### 使用自动化脚本部署

```bash
cd docker
./setup-registry.sh
```

脚本会自动：
- 创建必要的目录结构
- 生成 SSL 证书（可选）
- 配置用户认证（可选）
- 启动 Registry 和 Web UI

### 手动部署

```bash
# 1. 创建目录
mkdir -p auth certs data

# 2. 创建用户（可选）
htpasswd -Bbn admin admin123 > auth/htpasswd

# 3. 启动服务
docker-compose up -d

# 4. 查看状态
docker-compose ps
```

## 常用命令

### 登录和推送

```bash
# 登录
docker login localhost:5000

# 推送镜像
docker tag nginx:latest localhost:5000/nginx:latest
docker push localhost:5000/nginx:latest

# 拉取镜像
docker pull localhost:5000/nginx:latest
```

### 查看和管理

```bash
# 查看所有镜像
curl http://localhost:5000/v2/_catalog

# 查看镜像标签
curl http://localhost:5000/v2/nginx/tags/list

# 访问 Web UI
open http://localhost:8080
```

### 服务管理

```bash
# 查看日志
docker-compose logs -f

# 重启服务
docker-compose restart

# 停止服务
docker-compose down

# 停止并删除数据
docker-compose down -v
```

## 配置说明

详细配置请参考 [docker-registry.md](./docker-registry.md)
