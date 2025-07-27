# Vagrantfile “debug”: password + clave ed25519
VAGRANTFILE_API_VERSION = "2"

KEY_BASENAME = File.expand_path(".vagrant_ed25519")
unless File.exist?(KEY_BASENAME)
  system("ssh-keygen -t ed25519 -N '' -f #{KEY_BASENAME}") \
    or abort "No pude generar #{KEY_BASENAME}"
end
PRIVKEY_PATH = KEY_BASENAME
PUBKEY       = File.read("#{KEY_BASENAME}.pub").strip

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  config.vm.boot_timeout      = 600
  config.ssh.username         = "vagrant"
  config.ssh.insert_key       = false
  config.ssh.private_key_path = PRIVKEY_PATH

  nodes = [
    { name: "web01",     ssh_host_port: 2222 },
    { name: "web02",     ssh_host_port: 2223 },
    { name: "db01",      ssh_host_port: 2224 },
    { name: "monitor01", ssh_host_port: 2225 },
  ]

  nodes.each do |n|
    config.vm.define n[:name] do |node|
      node.vm.hostname = n[:name]

      node.vm.network :forwarded_port,
        guest: 22, host: n[:ssh_host_port], host_ip: "127.0.0.1",
        id: "ssh", auto_correct: false

      node.vm.provider "docker" do |d|
        d.image   = "ubuntu:22.04"
        d.has_ssh = true
        d.create_args = ["--hostname", n[:name]]

        d.cmd = ["bash", "-lc", <<~BASH]
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive

          apt-get update
          apt-get install -y openssh-server sudo python3 python3-apt

          # 1) Usuario vagrant con sudo sin password, desbloqueado
          id vagrant >/dev/null 2>&1 || useradd -m -s /bin/bash vagrant
          echo "vagrant ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/vagrant
          chmod 0440 /etc/sudoers.d/vagrant
          usermod -U vagrant

          # 2) Poner password “vagrant” (para debug)
          echo 'vagrant:vagrant' | chpasswd

          # 3) Inyectar la clave ed25519 también (por si quieres probarla)
          mkdir -p /home/vagrant/.ssh
          chmod 700 /home/vagrant/.ssh
          cat > /home/vagrant/.ssh/authorized_keys <<'EOF'
#{PUBKEY}
EOF
          chmod 600 /home/vagrant/.ssh/authorized_keys
          chown -R vagrant:vagrant /home/vagrant/.ssh

          # 4) Ajustes sshd: **permitir password** + clave + host keys + logs
          mkdir -p /run/sshd
          sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
          sed -i 's/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/' /etc/ssh/sshd_config
          sed -i 's/^#\\?UsePAM.*/UsePAM yes/' /etc/ssh/sshd_config
          ssh-keygen -A

          exec /usr/sbin/sshd -D -e
        BASH
      end

      node.vm.synced_folder ".", "/vagrant"
    end
  end
end
