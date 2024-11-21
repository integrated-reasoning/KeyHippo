{
  description = "Issue API keys for your Supabase app with one line of SQL";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/master";
    flake-utils.url = "github:numtide/flake-utils/v1.0.0";
    gitignore = {
      url = "github:hercules-ci/gitignore.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: with inputs;
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ ];
        };
        buildInputs = with pkgs; [
          supabase-cli
        ];
      in
      rec
      {
        devShell = pkgs.mkShell {
          inherit buildInputs;
        };
      }
    );
}
