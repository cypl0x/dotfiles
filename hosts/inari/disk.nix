{lib, ...}: {
  disko.devices = {
    disk = {
      nvme0 = {
        type = "disk";
        device = lib.mkDefault "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            boot-raid = {
              size = "1G";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            root-raid = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
      nvme1 = {
        type = "disk";
        device = lib.mkDefault "/dev/nvme1n1";
        content = {
          type = "gpt";
          partitions = {
            bios = {
              size = "1M";
              type = "EF02";
            };
            boot-raid = {
              size = "1G";
              content = {
                type = "mdraid";
                name = "boot";
              };
            };
            root-raid = {
              size = "100%";
              content = {
                type = "mdraid";
                name = "root";
              };
            };
          };
        };
      };
    };
    mdadm = {
      boot = {
        type = "mdadm";
        level = 1;
        metadata = "1.0";
        content = {
          type = "filesystem";
          format = "ext4";
          mountpoint = "/boot";
          mountOptions = ["noatime"];
        };
      };
      root = {
        type = "mdadm";
        level = 1;
        content = {
          type = "luks";
          name = "cryptroot";
          passwordFile = "/tmp/disk-password";
          settings = {
            allowDiscards = true;
            bypassWorkqueues = true;
          };
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = ["noatime"];
          };
        };
      };
    };
  };
}
