{
  description = "Homescale dev shell";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs = { nixpkgs, ... }: let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config.allowUnfree = true;
    };
  in {
    devShells.${system}.default = pkgs.mkShell {
      buildInputs = with pkgs; [
        bashInteractive
        bash-completion
        jq
        yq
        terraform
        kubectl
        kubecolor
        librespeed-cli
        pre-commit
        k9s
        argocd
        act
        fzf
        yamllint
        _1password-cli
      ];

      shellHook = ''
        export EDITOR=nvim
        export KUBECONFIG="$HOME/.kube/config-homescale"
        pre-commit.exe install
        export PATH=$PWD/tools:$PATH
        echo "HomeScale dev shell loaded"
      '';
    };
  };
}
