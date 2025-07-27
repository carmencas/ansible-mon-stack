VAGRANTFILE_API_VERSION = "2"

# 1) Generate an ed25519 keypair if you don’t already have one
KEY_BASENAME = File.expand_path(".vagrant_ed25519")
unless File.exist?(KEY_BASENAME)
  system("ssh-keygen -t ed25519 -N '' -f #{KEY_BASENAME}") \
    or abort "Failed to generate #{KEY_BASENAME}"
end
PUBKEY = File.read("#{KEY_BASENAME}.pub").strip

Vagrant.configure(VAGRANTFILE_API_VERSION) do |config|
  # Give SSH lots of time (up to 10m) for container to come up
  config.vm.boot_timeout      = 600
  config.ssh.username         = "vagrant"
  config.ssh.insert_key       = false
  config.ssh.private_key_path = KEY_BASENAME

  # Make sure the Docker bridge already exists:
  # docker network create --driver bridge --subnet 10.0.1.0/24 vagrantnet

  nodes = [
    { name: "web01",     ssh_port: 2222, ip: "10.0.1.10" },
    { name: "web02",     ssh_port: 2223, ip: "10.0.1.11" },
    { name: "db01",      ssh_port: 2224, ip: "10.0.1.20" },
    { name: "monitor01", ssh_port: 2225, ip: "10.0.1.30" },
  ]

  nodes.each do |n|
    config.vm.define n[:name] do |node|
      node.vm.hostname = n[:name]

      # 1) SSH forwarding
      node.vm.network :forwarded_port,
        guest: 22, host: n[:ssh_port], host_ip: "127.0.0.1",
        id: "ssh", auto_correct: false

      # 2) Attach container to vagrantnet bridge with its static IP
      node.vm.network "private_network",
        name: "vagrantnet",
        ip:   n[:ip]

      node.vm.provider "docker" do |d|
        d.image       = "ubuntu:22.04"
        d.has_ssh     = true
        d.create_args = ["--hostname", n[:name]]

        # 3) Expose UIs in monitor01
        if n[:name] == "monitor01"
          d.ports = ["9090:9090", "8086:8086"]
        end

        d.cmd = ["bash", "-lc", <<~BASH]
          set -euo pipefail
          export DEBIAN_FRONTEND=noninteractive

          apt-get update
          apt-get install -y openssh-server sudo python3 python3-apt netcat

          # create & unlock vagrant user
          id vagrant >/dev/null 2>&1 || useradd -m -s /bin/bash vagrant
          echo "vagrant ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/vagrant
          chmod 0440 /etc/sudoers.d/vagrant
          usermod -U vagrant
          echo 'vagrant:vagrant' | chpasswd

          # inject your ed25519 public key
          mkdir -p /home/vagrant/.ssh
          chmod 700 /home/vagrant/.ssh
          cat >/home/vagrant/.ssh/authorized_keys <<EOF
#{PUBKEY}
EOF
          chmod 600 /home/vagrant/.ssh/authorized_keys
          chown -R vagrant:vagrant /home/vagrant/.ssh

          # enable both password & pubkey auth in SSHD
          mkdir -p /run/sshd
          sed -i 's/^#\\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
          sed -i 's/^#\\?PubkeyAuthentication.*/PubkeyAuthentication yes/'   /etc/ssh/sshd_config
          sed -i 's/^#\\?UsePAM.*/UsePAM yes/'                               /etc/ssh/sshd_config
          ssh-keygen -A

          exec /usr/sbin/sshd -D -e
        BASH
      end

      # 4) Synced folder for your playbooks
      node.vm.synced_folder ".", "/vagrant"
    end
  end
end
