FROM kalilinux/kali-rolling:latest

# 设置环境变量
ENV TZ=Asia/Shanghai
ENV PLAYWRIGHT_MCP_BROWSER=chromium

# 安装基础环境
RUN apt update && \
    apt -y install kali-linux-headless && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# 创建普通用户并赋予 sudo 免密权限
RUN useradd -m -s /bin/zsh kali && \
    echo "kali ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers
USER kali

# 安装 oh-my-zsh 及自动补全插件
RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
    git clone --depth=1 https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions && \
    git clone --depth=1 https://github.com/zsh-users/zsh-completions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-completions && \
    sed -i 's/plugins=(git)/plugins=(git zsh-autosuggestions zsh-completions)/' ~/.zshrc

# 安装依赖和 Playwright
RUN sudo apt update && \
    sudo apt install -y bsdextrautils npm jq iputils-ping sshpass ncat rlwrap && \
    sudo apt clean && \
    sudo rm -rf /var/lib/apt/lists/* && \
    sudo npm install -g @playwright/cli@latest && \
    cd /tmp && playwright-cli install

# 安装 fd 和 ripgrep (pi 依赖)，自动获取最新版本
RUN FD_TAG=$(curl -fsSL https://api.github.com/repos/sharkdp/fd/releases/latest | jq -r '.tag_name') && \
    echo "fd: ${FD_TAG}" && \
    sudo curl -fsSL https://github.com/sharkdp/fd/releases/download/${FD_TAG}/fd-${FD_TAG}-x86_64-unknown-linux-musl.tar.gz | \
        sudo tar xz -C /usr/local/bin --strip-components=1 fd-${FD_TAG}-x86_64-unknown-linux-musl/fd && \
    RG_TAG=$(curl -fsSL https://api.github.com/repos/BurntSushi/ripgrep/releases/latest | jq -r '.tag_name') && \
    echo "rg: ${RG_TAG}" && \
    sudo curl -fsSL https://github.com/BurntSushi/ripgrep/releases/download/${RG_TAG}/ripgrep-${RG_TAG}-x86_64-unknown-linux-musl.tar.gz | \
        sudo tar xz -C /usr/local/bin --strip-components=1 ripgrep-${RG_TAG}-x86_64-unknown-linux-musl/rg

# 安装各类 AI Agent CLI
RUN sudo npm install -g @openai/codex && \
    curl -fsSL https://claude.ai/install.sh | bash && \
    sudo npm install -g @earendil-works/pi-coding-agent && \
    sudo npm install -g @google/gemini-cli && \
    sudo npm install -g opencode-ai@latest
ENV PATH="/home/kali/.local/bin:${PATH}"

WORKDIR /home/kali
