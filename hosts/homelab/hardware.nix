{ modulesPath, ... }: {
  imports = [ (modulesPath + "/profiles/qemu-guest.nix") ];

  # Boot loader (hardware-specific)
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
    device = "nodev";
  };

  # File systems
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/ADE0-02DF";
    fsType = "vfat";
  };

  fileSystems."/" = {
    device = "/dev/vda2";
    fsType = "ext4";
  };

  # Kernel modules
  boot.initrd.availableKernelModules = [ "ata_piix" "uhci_hcd" "xen_blkfront" "vmw_pvscsi" ];
  boot.initrd.kernelModules = [ "nvme" ];
}
