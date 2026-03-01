_: {
  boot = {
    loader.grub = {
      enable = true;
      efiSupport = true;
      efiInstallAsRemovable = true;
      device = "nodev";
      extraConfig = ''
        search --no-floppy --label --set=drive1 disk-nvme0-ESP
      '';
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
        "r8169"
      ];
      kernelModules = ["dm-snapshot" "raid1" "md-mod"];
    };

    kernelModules = ["kvm-amd"];
  };

  nixpkgs.hostPlatform = "x86_64-linux";
}
