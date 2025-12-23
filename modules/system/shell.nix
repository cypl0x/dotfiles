{ pkgs, ... }: {
  # Zsh configuration
  programs.zsh = {
    enable = true;
    # Completion and autosuggestions are helpful system-wide for root/other users
    # who might not have home-manager set up yet.
    enableCompletion = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  # Set default shell for users is handled in user modules, 
  # but enabling the shell package here ensures it is installed.
}
