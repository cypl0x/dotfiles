# Mail: mu (index and search) with mu4e for Emacs (Doom's :email mu4e),
# mbsync (isync) and offlineimap to fetch. System-wide, so every host and
# user that imports it has the same tools; mu4e's Lisp lands in
# /run/current-system/sw/share/emacs/site-lisp/mu4e, where Doom finds it.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    mu
    mu.mu4e
    isync
    offlineimap
  ];
}
