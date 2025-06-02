{
  description = "API key management and RBAC for PostgreSQL";

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
          docker-compose
          postgresql
          pgcli
        ];
      in
      rec
      {
        devShell = pkgs.mkShell {
          inherit buildInputs;
          shellHook = ''
            echo "KeyHippo development environment"
            echo "Available commands:"
            echo "  make setup     - Start PostgreSQL with Docker"
            echo "  make test      - Run tests"
            echo "  make benchmark - Run benchmarks"
            echo "  make reset     - Reset database"
          '';
        };
      }
    );
}
