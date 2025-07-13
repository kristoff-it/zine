{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = {
    self,
    nixpkgs,
    zig2nix,
    ...
  }: let
    inherit (nixpkgs) lib;
    forAllSystems = body:
      lib.genAttrs lib.systems.flakeExposed (system:
        body {
          inherit system;
          pkgs = nixpkgs.legacyPackages.${system};
          env = zig2nix.outputs.zig-env.${system} {
            nixpkgs = nixpkgs;
          };
        });
  in {
    packages = forAllSystems (
      {
        system,
        env,
        ...
      }: {
        zine = env.package {
          src = lib.cleanSource ./.;
          nativeBuildInputs = [ nixpkgs.legacyPackages.${system}.autoPatchelfHook ];
          buildInputs = [];
          zigPreferMusl = false;
        };
        default = self.packages.${system}.zine;
      }
    );
    devShells = forAllSystems (
      {env, ...}: {
        default = env.mkShell {};
      }
    );
  };
}
