#!/bin/bash

# Docker Registry 快速部署脚本
# 用途：一键部署私有 Docker 镜像中心

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 打印信息
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
    exit 1
}

# 检查命令是否存在
check_command() {
    if ! command -v $1 &> /dev/null; then
        error "$1 未安装，请先安装 $1"
    fi
}

# 检查依赖
info "检查依赖..."
check_command docker
check_command docker-compose

# 创建目录结构
info "创建目录结构..."
mkdir -p auth certs data

# 配置选项
read -p "是否启用 HTTPS? (y/n, 默认: n): " enable_https
enable_https=${enable_https:-n}

read -p "是否启用用户认证? (y/n, 默认: y): " enable_auth
enable_auth=${enable_auth:-y}

# 生成 SSL 证书
if [[ "$enable_https" == "y" ]]; then
    info "生成自签名 SSL 证书..."
    read -p "请输入域名 (默认: registry.example.com): " domain
    domain=${domain:-registry.example.com}
    
    openssl req -newkey rsa:4096 -nodes -sha256 \
        -keyout certs/domain.key -x509 -days 365 \
        -out certs/domain.crt \
        -subj "/C=CN/ST=Beijing/L=Beijing/O=MyCompany/CN=$domain"
    
    info "SSL 证书已生成: certs/domain.crt"
fi

# 创建认证文件
if [[ "$enable_auth" == "y" ]]; then
    info "创建用户认证..."
    
    # 检查 htpasswd 工具
    if ! command -v htpasswd &> /dev/null; then
        warn "htpasswd 未安装，尝试自动安装..."
        if [[ "$OSTYPE" == "linux-gnu"* ]]; then
            if command -v apt-get &> /dev/null; then
                sudo apt-get update && sudo apt-get install -y apache2-utils
            elif command -v yum &> /dev/null; then
                sudo yum install -y httpd-tools
            fi
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            if command -v brew &> /dev/null; then
                brew install httpd
            else
                error "请先安装 Homebrew: https://brew.sh/"
            fi
        fi
    fi
    
    read -p "请输入管理员用户名 (默认: admin): " username
    username=${username:-admin}
    
    read -s -p "请输入管理员密码 (默认: admin123): " password
    echo
    password=${password:-admin123}
    
    htpasswd -Bbn "$username" "$password" > auth/htpasswd
    info "用户认证已创建: auth/htpasswd"
fi

# 更新 docker-compose.yml
info "配置 docker-compose.yml..."

if [[ "$enable_https" == "y" ]]; then
    # 启用 HTTPS 配置
    sed -i.bak 's|# REGISTRY_HTTP_TLS_CERTIFICATE|REGISTRY_HTTP_TLS_CERTIFICATE|g' docker-compose.yml
    sed -i.bak 's|# REGISTRY_HTTP_TLS_KEY|REGISTRY_HTTP_TLS_KEY|g' docker-compose.yml
    sed -i.bak 's|# - ./certs:/certs|- ./certs:/certs|g' docker-compose.yml
    sed -i.bak 's|http://registry:5000|https://registry:5000|g' docker-compose.yml
    rm -f docker-compose.yml.bak
fi

if [[ "$enable_auth" == "n" ]]; then
    # 禁用认证
    sed -i.bak '/REGISTRY_AUTH/d' docker-compose.yml
    rm -f docker-compose.yml.bak
fi

# 启动服务
info "启动 Docker Registry..."
docker-compose up -d

# 等待服务启动
info "等待服务启动..."
sleep 5

# 检查服务状态
if docker-compose ps | grep -q "Up"; then
    info "Docker Registry 启动成功！"
    echo
    echo "========================================="
    echo "  Docker Registry 部署完成"
    echo "========================================="
    echo
    
    if [[ "$enable_https" == "y" ]]; then
        echo "Registry 地址: https://$domain:5000"
    else
        echo "Registry 地址: http://localhost:5000"
    fi
    
    echo "Web UI 地址: http://localhost:8080"
    echo
    
    if [[ "$enable_auth" == "y" ]]; then
        echo "用户名: $username"
        echo "密码: $password"
        echo
        echo "登录命令:"
        if [[ "$enable_https" == "y" ]]; then
            echo "  docker login $domain:5000"
        else
            echo "  docker login localhost:5000"
        fi
    fi
    
    echo
    echo "测试推送镜像:"
    echo "  docker pull nginx:latest"
    if [[ "$enable_https" == "y" ]]; then
        echo "  docker tag nginx:latest $domain:5000/nginx:latest"
        echo "  docker push $domain:5000/nginx:latest"
    else
        echo "  docker tag nginx:latest localhost:5000/nginx:latest"
        echo "  docker push localhost:5000/nginx:latest"
    fi
    echo
    echo "查看日志:"
    echo "  docker-compose logs -f"
    echo
    echo "停止服务:"
    echo "  docker-compose down"
    echo "========================================="
else
    error "Docker Registry 启动失败，请查看日志: docker-compose logs"
fi
