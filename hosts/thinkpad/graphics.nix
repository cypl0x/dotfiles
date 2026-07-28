{pkgs, ...}: {
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

  # Firefox and mpv both probe LIBVA_DRIVER_NAME before guessing. Pinning it
  # avoids a fallback to i965 when both drivers are present in the store.
  environment.sessionVariables.LIBVA_DRIVER_NAME = "iHD";

  environment.systemPackages = with pkgs; [
    libva-utils # vainfo — verify decode/encode entrypoints
    vulkan-tools # vulkaninfo
    mesa-demos # glxinfo/eglinfo (glxinfo was folded into mesa-demos)
    intel-gpu-tools # intel_gpu_top — confirm decode is actually on the GPU
  ];
}
