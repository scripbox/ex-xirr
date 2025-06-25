{ pkgs ? import <nixpkgs> { } }:
let elixir = (pkgs.beam.packagesWith pkgs.erlang_27).elixir_1_17;
in pkgs.mkShell {
  nativeBuildInputs = [
    pkgs.erlang_27
    elixir
    pkgs.postgresql
    pkgs.mariadb
    pkgs.ghostscript
    pkgs.imagemagick
    pkgs.git
    pkgs.elixir-ls
  ];

  shellHook = ''
    export ELS_INSTALL_PREFIX="$(nix-store -r $(which elixir-ls))/lib/"
    export PATH="$(nix-store -r $(which elixir-ls))/bin:$PATH"
  '';
}
