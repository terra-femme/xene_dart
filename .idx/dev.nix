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
    # ADDED: Flutter and Dart SDK
    pkgs.flutter
    # ADDED: iOS development tools
    pkgs.xcodebuild # Provides Xcode command-line tools
    pkgs.cocoapods
    # ADDED: Android development tools (adjust as needed based on Nixpkgs)
    pkgs.android-tools
  ];
  # Sets environment variables in the workspace
  env = {
    # It's often helpful to explicitly set ANDROID_HOME
    ANDROID_HOME = "${pkgs.android-tools}/libexec/android-sdk";
  };
  idx = {
    # Search for the extensions you want on https://open-vsx.org/ and use "publisher.id"
    extensions = [
      "Dart-Code.dart-code"
      "Dart-Code.flutter"
    ];
    # Workspace lifecycle hooks
    workspace = {
      # onCreate only runs once when the environment is first created.
      onCreate = {
        # Initialize web support for the app (needed for IDX preview)
        # It's better to run `flutter create .` from the app directory after Flutter is installed.
        # This will recreate the necessary web files with the correct Flutter version.
        web-setup = "cd packages/xene_app && flutter create --platforms web .";
        # Bootstrap Melos and generate code
        melos-bootstrap = "melos bootstrap";
        melos-generate = "melos run generate";
        # After everything is set up, run flutter doctor to catch any remaining issues
        flutter-doctor = "flutter doctor";
      };
      # onStart runs every time the workspace starts up.
      onStart = {
        # Ensure dependencies are synced on restart
        melos-bootstrap = "melos bootstrap";
        # Also run generate on start in case files were deleted or changed
        melos-generate = "melos run generate";
        # Run flutter doctor on start too
        flutter-doctor = "flutter doctor";
        # Ensure web/ios support and generated files exist for existing workspaces
        setup = ''
          if [ ! -d "packages/xene_app/web" ] || [ ! -d "packages/xene_app/ios" ]; then
            cd packages/xene_app && flutter create --platforms web,ios . && cd ../..
          fi
          
          # Always bootstrap to ensure links are correct
          melos bootstrap
          
          # Generate code if missing
          if [ ! -f "packages/xene_domain/lib/src/models/artist.freezed.dart" ]; then
            melos run generate
          fi
        '';
      };
    };
    # Preview configuration
    previews = {
      enable = true;
      previews = {
        web = {
          # Run from the app directory to ensure package resolution works correctly
          command = ["flutter" "run" "--machine" "-d" "web-server" "--web-port" "$PORT" "--target" "lib/main.dart"];
          cwd = "packages/xene_app";
          manager = "flutter";
        };
      };
    };
  };
}
