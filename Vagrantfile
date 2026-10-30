Vagrant.configure("2") do |config|
  config.vm.box = "net9/ubuntu-24.04-arm64"
  config.vm.box_version = "1.1"

  config.vm.hostname = "lab"
  config.vm.network "private_network", ip: "192.168.56.10"

  config.vm.provider "virtualbox" do |vb|
    vb.name = "linux-troubleshooting-lab"
    vb.memory = "2048"
    vb.cpus = 2
  end
  config.vm.synced_folder ".", "/vagrant"

  # Настройка машины
  
  config.vm.provision "shell", inline: <<-SHELL
    set -e

    echo "=== Обновление системы ==="
    apt-get update -y
    
    echo "=== Установка необходимых пакетов ==="
    apt-get install -y \
      git \
      curl \
      wget \
      vim \
      htop \
      tree \
      net-tools \
      iputils-ping \
      dnsutils \
      traceroute \
      tcpdump \
      netcat-openbsd \
      jq \
      unzip \
      ca-certificates

    echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
    chmod 440 /etc/sudoers.d/vagrant

    chmod +x /vagrant/scripts/*.sh 2>/dev/null || true
    chmod +x /vagrant/labs/01-network-dns/*.sh 2>/dev/null || true

    echo
    echo "========================================"
    echo "  Машина готова!"
    echo "  Проект находится в: /vagrant"
    echo "  Зайти в проект:     cd /vagrant"
    echo "========================================"
  SHELL
end