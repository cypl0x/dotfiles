{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
# wacli — scriptable WhatsApp client (built on whatsmeow) from the OpenClaw
# project. Not packaged in nixpkgs or nix-openclaw; this is a from-source build.
# Runtime: `wacli auth` pairs a linked device via QR, then messages sync into a
# local SQLite (FTS5) database for offline search/send.
buildGoModule rec {
  pname = "wacli";
  version = "0.13.0";

  src = fetchFromGitHub {
    owner = "openclaw";
    repo = "wacli";
    rev = "v${version}";
    hash = "sha256-T43ICOBMPt0w1xELaZQhGzAX0Bx3T8ksNWqLGOB5H1k=";
  };

  vendorHash = "sha256-ZDmnGEPV0pCB++D3R6RZ3+BGOft64R6x0vy7FZQAcZs=";

  subPackages = ["cmd/wacli"];

  # whatsmeow stores messages in SQLite with full-text search; cgo and the
  # sqlite_fts5 build tag are mandatory. The cflag silences a clang error that
  # upstream documents for the from-source build.
  env.CGO_ENABLED = "1";
  env.CGO_CFLAGS = "-Wno-error=missing-braces";
  tags = ["sqlite_fts5"];

  meta = {
    description = "Scriptable WhatsApp client (whatsmeow) — sync, search, send from the CLI";
    homepage = "https://github.com/openclaw/wacli";
    license = lib.licenses.mit;
    mainProgram = "wacli";
    platforms = lib.platforms.linux;
  };
}
