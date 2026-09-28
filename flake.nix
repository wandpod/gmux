{
  description = "gmux - stream multiplexer";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
      ];
      forAll = nixpkgs.lib.genAttrs systems;
      overlay = final: _: { gmux = final.callPackage ./nix/package.nix { }; };
      # gmux is unfree: allow exactly it, so `nix run` works without a global
      # allowUnfree.
      pkgsFor =
        system:
        import nixpkgs {
          inherit system;
          overlays = [ overlay ];
          config.allowUnfreePredicate = pkg: nixpkgs.lib.getName pkg == "gmux";
        };
      module =
        { pkgs, lib, ... }:
        {
          imports = [ ./nix/module.nix ];
          services.gmux.package = lib.mkDefault self.packages.${pkgs.stdenv.hostPlatform.system}.default;
        };
    in
    {
      overlays.default = overlay;
      nixosModules.default = module;
      packages = forAll (system: {
        default = (pkgsFor system).gmux;
      });
      checks = nixpkgs.lib.genAttrs [ "x86_64-linux" ] (system: {
        nixos = import ./nix/test.nix {
          pkgs = pkgsFor system;
          inherit module;
          package = (pkgsFor system).gmux;
        };
      });
    };
}
