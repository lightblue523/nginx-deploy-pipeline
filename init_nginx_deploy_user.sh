#!/bin/bash
set -e

# ===== 配置區 =====
DEPLOY_USER="nginxdeploy"
DEPLOY_HOME="/home/$DEPLOY_USER"
PUBLIC_KEY_FILE="./nginxdeploy_id_rsa.pub"  # 請提前在本地生成並放置公鑰文件
SUDO_COMMANDS="/usr/bin/docker exec nginx nginx -t, /opt/nginx/start.sh, /opt/nginx/stop.sh"

# ===== 檢查公鑰文件 =====
if [[ ! -f "$PUBLIC_KEY_FILE" ]]; then
  echo "❌ 公鑰文件不存在: $PUBLIC_KEY_FILE"
  exit 1
fi

# ===== 創建使用者，允許 shell（必要，CI 可執行命令）=====
echo "🧱 創建使用者 $DEPLOY_USER ..."
sudo useradd -m -s /bin/bash "$DEPLOY_USER" || echo "⚠️ 使用者已存在，跳過創建"

# ===== 設定 SSH 登錄（僅密鑰登錄）=====
echo "🔐 配置 SSH 密鑰登錄 ..."
sudo mkdir -p "$DEPLOY_HOME/.ssh"
sudo cp "$PUBLIC_KEY_FILE" "$DEPLOY_HOME/.ssh/authorized_keys"
sudo chown -R "$DEPLOY_USER:$DEPLOY_USER" "$DEPLOY_HOME/.ssh"
sudo chmod 700 "$DEPLOY_HOME/.ssh"
sudo chmod 600 "$DEPLOY_HOME/.ssh/authorized_keys"

# ===== 禁用密碼登錄，僅允許該使用者用密鑰 =====
echo "🔧 修改 sshd_config ..."
sudo sed -i.bak '/^AllowUsers /d' /etc/ssh/sshd_config
echo "AllowUsers root $DEPLOY_USER" | sudo tee -a /etc/ssh/sshd_config

sudo sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config

echo "Match User $DEPLOY_USER" | sudo tee -a /etc/ssh/sshd_config
echo "  PasswordAuthentication no" | sudo tee -a /etc/ssh/sshd_config

sudo systemctl restart sshd

# ===== 設定 sudo 白名單命令 =====
echo "🛡️ 設定 sudo 白名單命令權限 ..."
echo "$DEPLOY_USER ALL=(ALL) NOPASSWD: $SUDO_COMMANDS" | sudo tee /etc/sudoers.d/$DEPLOY_USER > /dev/null
sudo chmod 440 /etc/sudoers.d/$DEPLOY_USER

# ===== 設定啟動腳本權限（root + nginxdeploy 可執行）=====
echo "🔒 限制腳本權限 ..."
sudo chown root:$DEPLOY_USER /opt/nginx/start.sh /opt/nginx/stop.sh
sudo chmod 750 /opt/nginx/start.sh /opt/nginx/stop.sh

echo ""
echo "✅ 使用者 $DEPLOY_USER 創建成功，權限配置完成："
echo "  🔐 密鑰登錄 ✅"
echo "  ❌ 密碼登錄禁止"
echo "  ✅ 可執行 shell 命令"
echo "  ✅ 可 sudo 執行:"
echo "     - /usr/bin/docker exec nginx nginx -t"
echo "     - /opt/nginx/start.sh"
echo "     - /opt/nginx/stop.sh"
echo ""
echo "🧾 請將私鑰新增至 GitLab CI/CD Variable：ECS_SSH_KEY（Base64 編碼）"
