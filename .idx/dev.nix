# To learn more about how to use Nix to configure your environment
# see: https://developers.google.com/idx/guides/customize-idx-env
{ pkgs, ... }: {
  # Which nixpkgs channel to use.
  channel = "stable-23.11"; # or "unstable"
  # Use https://search.nixos.org/packages to find packages
  packages = [
    pkgs.nodePackages.firebase-tools
    pkgs.jdk17
    pkgs.unzip
  ];
  # Sets environment variables in the workspace
  env = {};
  idx = {
    # Search for the extensions you want on https://open-vsx.org/ and use "publisher.id"
    extensions = [
      "Dart-Code.dart-code"
      "Dart-Code.flutter"
    ];
    # Workspace lifecycle hooks
    workspace = {
      # Runs when a workspace is first created
      onCreate = {
        # Bootstrap Melos and generate code
        melos-bootstrap = "melos bootstrap";
        melos-generate = "melos run generate";
      };
      # Runs when the workspace is (re)started
      onStart = {
        # Ensure dependencies are synced on restart
        melos-bootstrap = "melos bootstrap";
      };
    };
    # Preview configuration
    previews = {
      enable = true;
      previews = {
        web = {
          command = ["flutter" "run" "--machine" "-d" "web-server" "--web-port" "$PORT" "packages/xene_app/lib/main.dart"];
          manager = "flutter";
        };
      };
    };
  };
}
