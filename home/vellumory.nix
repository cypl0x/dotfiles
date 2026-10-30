{
  config,
  lib,
  pkgs,
  vellumory,
  ...
}:
# Vellumory, the PDF reader for Emacs (github.com/cypl0x/vellumory), for wap:
# its worker on PATH, which runs its own qpdf, veraPDF and OCRmyPDF (so none of
# them is needed here), and its Doom module, enabled as `:tools vellumory' in
# home/doom/init.el. Doom's package manager installs the Lisp from the same
# source (home/doom/packages.el). After a switch, run `doom sync'.
lib.mkIf (config.home.username == "wap") {
  # OCR in English and German only: all of Tesseract's languages take 1 GB.
  home.packages = [
    (vellumory.packages.${pkgs.stdenv.hostPlatform.system}.vellumory.override {
      tesseractLanguages = ["eng" "deu"];
    })
  ];
  home.file.".config/doom/modules/tools/vellumory".source = "${vellumory}/doom/tools/vellumory";
}
