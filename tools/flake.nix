{
  description = "Homescale development environment for tools";

  # Define inputs (dependencies)
  inputs = {
    # Use a specific branch or version of nixpkgs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  # Outputs section defines the dev shell environment
  outputs = { nixpkgs, ... }: let
    # Make sure to define the path correctly, assuming it's in the same directory as the flake.nix
    toolsPath = ./.tools;
  in {
    devShells.x86_64-linux.tools = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = [
        nixpkgs.legacyPackages.x86_64-linux.bash          # Bash
        nixpkgs.legacyPackages.x86_64-linux.coreutils     # Core utilities like `cp`, `mv`, etc.
        nixpkgs.legacyPackages.x86_64-linux.opentofu      # Opentofu (for homescale-tofu.sh)
      ];

      # Optional: set environment variables if needed
    };
  };
}
