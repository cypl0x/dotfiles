# Flutter and Dart for app development on this machine.
{pkgs, ...}: {
  environment.systemPackages = with pkgs; [
    dart
    flutter
  ];
}
