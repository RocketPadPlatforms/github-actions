{
  description = "Test dev shell for actions/nix-develop";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { nixpkgs, ... }:
    let
      pkgs = nixpkgs.legacyPackages.x86_64-linux;
    in
    {
      packages.x86_64-linux.hello = pkgs.hello;
      devShells.x86_64-linux.default = pkgs.mkShell {
        packages = [ pkgs.hello ];
        SINGLE = "one";
        MULTI = "line1\nline2";
        shellHook = ''
          echo "hook=printed"
        '';
      };
    };
}
