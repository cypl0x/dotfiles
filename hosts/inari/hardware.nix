{modulesPath, ...}: {
  imports = [
    (modulesPath + "/profiles/hardened.nix")
  ];

  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
      mirroredBoots = [
        {
          devices = ["nodev"];
          path = "/boot";
        }
        {
          devices = ["nodev"];
          path = "/boot/efi";
        }
      ];
    };

    initrd = {
      availableKernelModules = [
        "xhci_pci"
        "ahci"
        "nvme"
        "usb_storage"
        "usbhid"
        "sd_mod"
      ];
      kernelModules = ["dm-snapshot" "raid1" "md-mod"];

      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          authorizedKeys = [(builtins.readFile ../../modules/ssh-keys/homelab.pub)];
          hostKeys = ["/etc/secrets/initrd/ssh_host_ed25519_key"];
        };
      };
    };

    kernelModules = ["kvm-amd"];
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
