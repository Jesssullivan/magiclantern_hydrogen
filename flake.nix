{
  description = "magiclantern_hydrogen — research fork of Magic Lantern firmware";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    # Zig comes from nixpkgs-unstable. zig-overlay was tried first but
    # building zig 0.14.1 from source on aarch64-darwin exhausted /tmp
    # and was a poor developer experience. nixpkgs-unstable carries a
    # cached binary release. If we need a specific Zig version pin in
    # the future, swap this back to zig-overlay with a working binary.
    nixpkgs-zig.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-zig,
    flake-utils,
    treefmt-nix,
  }:
    flake-utils.lib.eachDefaultSystem (system: let
      pkgs = import nixpkgs {inherit system;};
      pkgsZig = import nixpkgs-zig {inherit system;};

      # Zig from nixpkgs-unstable (binary release). Track whatever
      # version unstable ships; if we need to pin, switch to a
      # specific zig-overlay binary tag.
      zig = pkgsZig.zig;

      # arm-none-eabi cross toolchain for firmware.
      armEmbedded = pkgs.gcc-arm-embedded;

      treefmtEval = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs = {
          clang-format.enable = true;
          zig.enable = true;
          prettier.enable = true;
          alejandra.enable = true;
          taplo.enable = true;
          shfmt.enable = true;
        };
        settings = {
          formatter.clang-format.includes = [
            "*.c"
            "*.h"
            "*.cpp"
            "*.hpp"
          ];
          formatter.clang-format.excludes = [
            # Vendored third-party sources keep their own style until
            # we deliberately re-format them under workstream A6.
            "src/libs/**"
            "tcc/**"
            "minimal/qemu-*/**"
          ];
          formatter.prettier.excludes = [
            "developer_guide/*.html"
            "doc/*.tex"
          ];
        };
      };

      firmwareTools = [
        armEmbedded
        pkgs.gnumake
        pkgs.python3
        pkgs.lua5_1
        pkgs.gcc # host build of build_tools/
      ];

      zigTools = [zig];

      emulationTools = [
        # Host qemu for host-side unit tests. The patched qemu-eos
        # build lives in ../qemu-eos (reticulatedpines/qemu-eos) and
        # is not vendored here.
        pkgs.qemu
      ];

      formatTools = with pkgs; [
        treefmt
        clang-tools # clang-format + clang-tidy
        shfmt
        alejandra
        taplo
        nodePackages.prettier
      ];

      operatorTools = with pkgs; [
        just
        direnv
        nix-direnv
        git
        git-lfs # required: .gitattributes routes binaries through LFS
        git-cliff
        git-filter-repo
        pre-commit
        bazel-buildtools
        bazelisk
        jq
        yq-go
        gnused
        coreutils
      ];

      devTools =
        firmwareTools
        ++ zigTools
        ++ emulationTools
        ++ formatTools
        ++ operatorTools;
    in {
      devShells.default = pkgs.mkShell {
        name = "magiclantern_hydrogen";
        packages = devTools;

        shellHook = ''
          export PROJECT_ROOT="$PWD"
          export ARM_NONE_EABI_GCC="${armEmbedded}/bin/arm-none-eabi-gcc"
          # ML's existing Makefile.globals discovers the toolchain by
          # name; ensuring it is on PATH is sufficient. The export
          # above is informational for tooling that wants the absolute
          # path.
        '';
      };

      formatter = treefmtEval.config.build.wrapper;

      checks = {
        treefmt = treefmtEval.config.build.check self;
      };
    });
}
