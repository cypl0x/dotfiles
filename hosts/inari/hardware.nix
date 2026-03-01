_: {
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = false;
      efiInstallAsRemovable = false;
    };

    initrd = {
      availableKernelModules = [
        "nvme"
        "ahci"
        "sd_mod"
        "xhci_pci"
        "usbhid"
        "usb_storage"
        "r8169"
      ];
      systemd.enable = true;
      network = {
        enable = true;
        ssh = {
          enable = true;
          port = 2222;
          authorizedKeys = [(builtins.readFile ../../modules/ssh-keys/homelab.pub)];
          hostKeys = ["/etc/secrets/initrd/ssh_host_ed25519_key"];
        };
      };
      luks.devices."cryptroot" = {
        device = "/dev/md/root";
        keyFile = "/boot/luks-keyfile";
        allowDiscards = true;
        bypassWorkqueues = true;
      };
    };

    kernelModules = ["kvm-amd"];
    kernelParams = ["ip=dhcp"];

    swraid = {
      enable = true;
      mdadmConf = "MAILADDR root";
    };
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
