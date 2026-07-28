{
  config,
  pkgs,
  ...
}: {
  # Graphics stack for the ThinkPad's Optimus pair:
  #   00:02.0  Intel HD Graphics 530 (Skylake-H GT2, Gen9)  -> i915
  #   01:00.0  NVIDIA Quadro M2000M (GM107, Maxwell)        -> see below
  #
  # hardware.graphics.enable is already true (programs.hyprland sets it); what
  # was missing is a VA-API driver, so every video decode ran on the CPU.

  hardware.graphics = {
    extraPackages = with pkgs; [
      # iHD — the modern Intel media driver. Covers Gen8+, so Skylake's Gen9
      # is in range. The older i965 (intel-vaapi-driver) is unmaintained and
      # decodes fewer formats on this generation.
      intel-media-driver
      # VP9/AV1 hybrid decode paths and the OpenCL runtime the media driver
      # falls back to for some filters.
      intel-compute-runtime
    ];
  };

  # NVIDIA Quadro M2000M — proprietary driver with PRIME render offload.
  #
  # 580 is the LAST branch supporting Maxwell/Pascal/Volta; 595 and 610 dropped
  # them. So this pin is permanent, not a "catch up later" placeholder.
  services.xserver.videoDrivers = ["nvidia"];

  hardware.nvidia = {
    package = config.boot.kernelPackages.nvidiaPackages.legacy_580;

    # GM107 is Maxwell. The open kernel module requires Turing or newer, so the
    # proprietary blob is the only option here.
    open = false;

    # nvidia-drm.modeset=1. Required for anything Wayland to talk to the card.
    modesetting.enable = true;

    # Saves/restores VRAM across suspend. Worth having on a laptop even when
    # the dGPU is idle, since the blob otherwise corrupts state on resume.
    powerManagement.enable = true;

    # NOT enabled: powerManagement.finegrained. That is PCIe Runtime D3 (RTD3),
    # which NVIDIA only supports on Turing and newer. On Maxwell it does
    # nothing at best and hangs resume at worst.
    #
    # Consequence, stated plainly: with offload but no RTD3 the Quadro stays
    # powered whenever the nvidia module is loaded — roughly 5-10 W idle on
    # this chip. If battery life matters more than dGPU access, set
    # services.xserver.videoDrivers = ["modesetting"] and drop hardware.nvidia;
    # nothing else here depends on it.
    powerManagement.finegrained = false;

    prime = {
      # Bus IDs from lspci: Intel 00:02.0, NVIDIA 01:00.0.
      intelBusId = "PCI:0:2:0";
      nvidiaBusId = "PCI:1:0:0";

      # Render offload, not sync: the Intel iGPU drives all displays (it owns
      # eDP-1 and both HDMI ports), and only commands prefixed with
      # `nvidia-offload` execute on the Quadro.
      offload = {
        enable = true;
        enableOffloadCmd = true; # provides the `nvidia-offload` wrapper
      };
    };
  };

  # Firefox and mpv both probe LIBVA_DRIVER_NAME before guessing. Pinning it
  # avoids a fallback to i965 when both drivers are present in the store.
  environment.sessionVariables = {
    LIBVA_DRIVER_NAME = "iHD";

    # Pin Hyprland/aquamarine to the Intel card. DRM card numbers are assigned
    # in probe order and come up scrambled on this machine (the Quadro takes
    # card0, i915 card1), so a stable reference is needed — without one,
    # aquamarine can select the Quadro, which drives no connectors here.
    #
    # It must be the colon-free symlink from the udev rule below, NOT the
    # /dev/dri/by-path/ name: AQ_DRM_DEVICES is a colon-separated *list*, and a
    # PCI by-path contains colons, so aquamarine splits "pci-0000:00:02.0-card"
    # into three nonexistent paths and aborts with "Found no gpus to use".
    AQ_DRM_DEVICES = "/dev/dri/intel-gpu";
  };

  # Colon-free stable name for the Intel GPU. Both AQ_DRM_DEVICES (aquamarine)
  # and WLR_DRM_DEVICES (wlroots) parse their value as a colon-separated list,
  # which rules out /dev/dri/by-path/ names for this purpose. ID_PATH_TAG is
  # udev's punctuation-safe form of ID_PATH — here pci-0000_00_02_0.
  services.udev.extraRules = ''
    SUBSYSTEM=="drm", KERNEL=="card[0-9]*", ENV{ID_PATH_TAG}=="pci-0000_00_02_0", SYMLINK+="dri/intel-gpu"
  '';

  environment.systemPackages = with pkgs; [
    libva-utils # vainfo — verify decode/encode entrypoints
    vulkan-tools # vulkaninfo
    mesa-demos # glxinfo/eglinfo (glxinfo was folded into mesa-demos)
    intel-gpu-tools # intel_gpu_top — confirm decode is actually on the GPU
  ];
}
