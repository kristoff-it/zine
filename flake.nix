{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    zig2nix = {
      url = "github:Cloudef/zig2nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs =
    {
      self,
      nixpkgs,
      zig2nix,
      ...
    }:
    let
      inherit (nixpkgs) lib;
      forAllSystems =
        body: lib.genAttrs lib.systems.flakeExposed (system: body nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          env = zig2nix.outputs.zig-env.${pkgs.system} {
            nixpkgs = nixpkgs;
            zig = pkgs.zig;
          };
        in
        {
          zine = env.package {
            src = lib.cleanSource ./.;
            nativeBuildInputs = [ ];
            buildInputs = [ ];
            zigPreferMusl = false;
          };
          default = self.packages.${pkgs.system}.zine;
        }
      );
      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
    };
}
