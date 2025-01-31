{ pkgs ? import (fetchTarball "https://github.com/NixOS/nixpkgs/tarball/nixos-24.05") {}, ... }:
rec {
  package = pkgs.callPackage ./koti.nix { };
  shell = pkgs.mkShellNoCC {
    packages = with pkgs; [
      bashly
    ];
  };
}
