#!/bin/bash
set -e

# ===== 配置区 =====
DEPLOY_USER="nginxdeploy"
DEPLOY_HOME="/home/$DEPLOY_USER"
PUBLIC_KEY_FILE="./nginxdeploy_id_rsa.pub"  # 请提前在本地生成并放置公钥文件
SUDO_COMMANDS="/usr/bin/docker exec nginx nginx -t, /opt/nginx/start.sh, /opt/nginx/stop.sh"

# ===== 检查公钥文件 =====
if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
  echo "❌ 公钥文件不存在: $PUBLIC_KEY_FILE"
  exit 1
fi

# ===== 创建用户，允许 shell（必要，CI 可执行命令）=====
echo "🧱 创建用户 $DEPLOY_USER ..."
sudo useradd -m -s /bin/bash "$DEPLOY_USER" || echo "⚠️ 用户已存在，跳过创建"

# ===== 设置 SSH 登录（仅密钥登录）=====
echo "🔐 配置 SSH 密钥登录 ..."
sudo mkdir -p "$DEPLOY_HOME/.ssh"
sudo cp "$PUBLIC_KEY_FILE" "$DEPLOY_HOME/.ssh/authorized_keys"
sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh"
sudo chmod 700 "$DEPLOY_HOME/.ssh"
sudo chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys"

# ===== 禁用密码登录，仅允许该用户用密钥 =====
echo "🔧 修改 sshd_config ..."
sudo sed -i.bak '/^AllowUsers /d' /etc/ssh/sshd_config
echo "AllowUsers root $DEPLOY_USER" | sudo tee -a /etc/ssh/sshd_config

sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

echo "Match User $DEPLOY_USER" | sudo tee -a /etc/ssh/sshd_config
echo "  PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config

sudo systemctl restart sshd

# ===== 设置 sudo 白名单命令 =====
echo "🛡️ 设置 sudo 白名单命令权限 ..."
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD: $SUDO_COMMANDS" | sudo tee /etc/sudoers.d/$DEPLOY_USER > /dev/null
sudo chmod 440 /etc/sudoers.d/$DEPLOY_USER

# ===== 设置启动脚本权限（root + nginxdeploy 可执行）=====
echo "🔒 限制脚本权限 ..."
sudo chown root:$DEPLOY_USER /opt/nginx/start.sh /opt/nginx/stop.sh
sudo chmod 750 /opt/nginx/start.sh /opt/nginx/stop.sh

echo ""
echo "✅ 用户 $DEPLOY_USER 创建成功，权限配置完成："
echo "  🔐 密钥登录 ✅"
echo "  ❌ 密码登录禁止"
echo "  ✅ 可执行 shell 命令"
echo "  ✅ 可 sudo 执行:"
echo "     - /usr/bin/docker exec nginx nginx -t"
echo "     - /opt/nginx/start.sh"
echo "     - /opt/nginx/stop.sh"
echo ""
echo "🧾 请将私钥添加至 GitLab CI/CD Variable：ECS_SSH_KEY（Base64 编码）"
