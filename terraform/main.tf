terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.9.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

# Base Ubuntu Server cloud image stored in the default pool.
resource "libvirt_volume" "ubuntu_base" {
  name   = "ubuntu-24.04-base.qcow2"
  pool   = "default"
  format = "qcow2"
  create = {
    content = {
      url = "https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img"
    }
  }
}

# Writable copy-on-write layer for the VM.
resource "libvirt_volume" "ubuntu_disk" {
  name     = "ubuntu-vm.qcow2"
  pool     = "default"
  format   = "qcow2"
  capacity = 21474836480
  backing_store = {
    path   = libvirt_volume.ubuntu_base.path
    format = "qcow2"
  }
}

# Cloud-init seed ISO.
resource "libvirt_cloudinit_disk" "ubuntu_seed" {

  name = "ubuntu-cloudinit"

  user_data = <<-EOF
    #cloud-config
    users:
      - default
      - name: user
        hashed_passwd: ${var.hashed_passwd}
        lock_passwd: false
        sudo: ['ALL=(ALL) NOPASSWD:ALL']
        ssh_authorized_keys:
          - ${var.ssh_public_key}
  
    packages:
      - openssh-server
      - qemu-guest-agent
    timezone: UTC

    runcmd:
    - systemctl enable qemu-guest-agent
    - systemctl start qemu-guest-agent

  
  EOF

  meta_data = <<-EOF
    instance-id: ubuntu-001
    local-hostname: ubuntu-vm
  EOF

  network_config = <<-EOF
    version: 2
    ethernets:
      enp1s0:
        dhcp4: true
  EOF
}


# Upload the cloud-init ISO into the pool.

resource "libvirt_volume" "ubuntu_seed_volume" {
  name = "ubuntu-cloudinit.iso"
  pool = "default"
  create = {
    content = {
      url = libvirt_cloudinit_disk.ubuntu_seed.path
    }
  }
}


# Virtual machine definition.

resource "libvirt_domain" "ubuntu" {
  name   = "ubuntu-vm"
  memory = 4194304
  vcpu   = 2
  os = {
    type    = "hvm"
    arch    = "x86_64"
    machine = "q35"
  }
  features = {
    acpi = true
  }
  devices = {
    disks = [
      {
        source = {
          pool   = libvirt_volume.ubuntu_disk.pool
          volume = libvirt_volume.ubuntu_disk.name
        }
        target = {
          dev = "vda"
          bus = "virtio"
        }
      },
      {
        device = "cdrom"
        source = {
          pool   = libvirt_volume.ubuntu_seed_volume.pool
          volume = libvirt_volume.ubuntu_seed_volume.name
        }
        target = {
          dev = "sdb"
          bus = "sata"
        }
      }
    ]
    interfaces = [
      {
        type  = "network"
        model = "virtio"
        source = {
          network = "default"
        }
        # TODO: wait_for_ip not implemented yet (Phase 2)
        # This will wait during creation until the interface gets an IP
        wait_for_ip = {
          timeout = 300   # seconds, default 300
          source  = "any" # "lease" (DHCP), "agent" (qemu-guest-agent), or "any" (try both)
        }
      }
    ]
    graphics = {
      vnc = {
        autoport = "yes"
        listen   = "127.0.0.1"
      }
    }
  }
  running = true
}


# Query the domain's interface addresses
# This data source can be used at any time to retrieve current IP addresses
# without blocking operations like Delete
data "libvirt_domain_interface_addresses" "ubuntu" {
  domain = libvirt_domain.ubuntu.name
  source = "lease" # optional: "lease" (DHCP), "agent" (qemu-guest-agent), or "any"
}

# Output all interface information
output "vm_interfaces" {
  description = "All network interfaces with their IP addresses"
  value       = data.libvirt_domain_interface_addresses.ubuntu.interfaces
}

# Output the first IP address found
output "vm_ip" {
  description = "First IP address of the VM"
  value       = length(data.libvirt_domain_interface_addresses.ubuntu.interfaces) > 0 && length(data.libvirt_domain_interface_addresses.ubuntu.interfaces[0].addrs) > 0 ? data.libvirt_domain_interface_addresses.ubuntu.interfaces[0].addrs[0].addr : "No IP address found"
}

# Output all IP addresses across all interfaces
output "vm_all_ips" {
  description = "All IP addresses across all interfaces"
  value = flatten([
    for iface in data.libvirt_domain_interface_addresses.ubuntu.interfaces : [
      for addr in iface.addrs : addr.addr
    ]
  ])
}