# -*- mode: ruby -*-
# vi: set ft=ruby :

MAAS_IP = "10.1.0.1"
MAAS_NETMASK = "255.255.255.0"
KVM_HOST_IP = "192.168.1.100"
KVM_HOST_USER = "przem"

Vagrant.configure("2") do |config|

  config.ssh.insert_key = false
  config.ssh.private_key_path = ["id_rsa", "~/.vagrant.d/insecure_private_key"]
  config.vm.provision "file", source: "id_rsa.pub", destination: "~/.ssh/authorized_keys"

  # MAAS Server
  config.vm.define "maas-server", primary: true do |maas|
    maas.vm.box = "generic/ubuntu1804"
    maas.vm.hostname = "maas-server"
    maas.vm.network "private_network", ip: MAAS_IP,
      :libvirt__netmask => MAAS_NETMASK,
      :libvirt__forward_mode => 'veryisolated',
      :libvirt__network_name => 'maas-mgmt-network',
      :libvirt__dhcp_enabled => false,
      :dhcp_enabled => false,
      :autostart => true

    maas.vm.provider :libvirt do |domain|
      domain.default_prefix = ""
      domain.management_network_name = "libvirt-mgmt-network"
      domain.cpus = "2"
      domain.memory = "4096"
    end

    maas.vm.provision "ansible" do |ansible|
      ansible.compatibility_mode = "2.0"
      ansible.playbook = "playbook.yml"
      ansible.extra_vars = { 
        "default_maas_url" => MAAS_IP,
        "kvm_host_user" => KVM_HOST_USER,
        "kvm_host_ip" => KVM_HOST_IP
      }
    end
  end

  # PXE nodes
  (1..4).each do |i|
    config.vm.define "node-#{i}" do |node|

      node.vm.network :private_network, ip: "10.14.0.#{i+100}",
        :libvirt__forward_mode => 'veryisolated',
        :libvirt__network_name => 'maas-mgmt-network',
        :libvirt__dhcp_enabled => false,
        :dhcp_enabled => false,
        :autostart => true

      node.vm.provider :libvirt do |domain|
        domain.default_prefix = ""
        domain.cpus = "2"
        domain.memory = "4096"
        domain.storage :file, :size => '16G', :type => 'qcow2'
        boot_network = {'network' => 'maas-mgmt-network'}
        domain.boot boot_network
        domain.boot 'hd'
        domain.management_network_name = "libvirt-mgmt-network"
        domain.autostart = true

        # Pass node name as QEMU parameter so that the node can set it's 
        # power parameters during enlistment
        domain.qemuargs :value => "-smbios"
        domain.qemuargs :value => "type=1,serial=node-#{i}"
      end

    end
  end

end
