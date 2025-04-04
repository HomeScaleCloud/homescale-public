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
        opentofu
        kubectl
        kubecolor
        talosctl
        omnictl
        librespeed-cli
        pre-commit
        k9s
        argocd
        teleport_17
        act
        fzf
        yamllint
        _1password-cli
      ];

      shellHook = ''
        export EDITOR=nvim
        export KUBECONFIG="$HOME/.kube/config-homescale"
        export TALOSCONFIG="$HOME/.talos/config-homescale"
        export OMNICONFIG="$HOME/.omni/config-homescale"
        export TELEPORT_HOME="$HOME/.tsh-homescale"
        export TELEPORT_PROXY="teleport.homescale.cloud:443"
        pre-commit.exe install
        export PATH=$PWD/tools:$PATH
        echo "HomeScale dev shell loaded"
      '';
    };
  };
}
