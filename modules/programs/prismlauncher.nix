{ config, lib, pkgs, ... }:

let
  cfg = config.programs.prismlauncher;

  configPath = "${config.xdg.dataHome}/PrismLauncher";
in {
  meta.maintainers = [ lib.hm.maintainers.zorrobert ];

  options.programs.prismlauncher = {
    enable = lib.mkEnableOption "prismlauncher";

    package = lib.mkPackageOption pkgs "prismlauncher" { };

    ### Launcher
    launcher = {
      instances = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "instances";
        description = "The folder used by PrismLauncher to store instances.";
      };
      mods = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "mods";
        description = "The folder where PrismLauncher searches for local mods.";
      };
      icons = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "icons";
        description = "The folder where PrismLauncher stores custom icons";
      };
      downloads = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "/home/username/Downloads";
        description = "The folder PrismLauncher uses for downloads.";
      };
    };

    ### Minecraft

    ### Java
    java = {
      maximumMemoryAllocation = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 4096;
        description = ''
          The maximim amount of memory Minecraft is allowed to use.
        '';
      };
    };

    ### Language
    language = {
      language = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "en_GB";
        description = "The language used by PrismLauncher";
      };

      useSystemLocales = lib.mkOption {
        type = lib.types.nullOr lib.types.bool;
        default = null;
        description = "Set the language automatically to the system default";
      };
    };

    ### Custom Commands

    ### Environment Variables

    ### Proxy

    ### External Tools

    ### Accounts

    ### APIs

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = {
        General = {
          ApplicationTheme = "system";
          AutoCloseConsole = false;
          BackgroundCat = "kitteh";
          CentralModsDir = "mods";
        };
      };
      description = ''
        Additional settings for prismlauncher.cfg
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.activation = {
      createPrismLauncherConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] (
        lib.concatStringsSep "\n" (
          # map defined options to setting names in prismlauncher.cfg and filter out undefined options
          (lib.attrsets.mapAttrsToList (name: value: ''
            ${pkgs.libsForQt5.kconfig}/bin/kwriteconfig5 --file ${configPath}/prismlauncher.cfg --group 'General' --key '${name}' '${builtins.toString value}'
          '') (lib.attrsets.filterAttrsRecursive (n: v: v != null) {
            ### Launcher
            InstanceDir = cfg.launcher.instances;
            CentralModsDir = cfg.launcher.mods;
            IconsDir = cfg.launcher.icons;
            DownloadsDir = cfg.launcher.downloads;
            ### Minecraft

            ### Java
            MaxMemAlloc = cfg.java.maximumMemoryAllocation;
            ### Language
            Language = cfg.language.language;
            UseSystemLocale = cfg.language.useSystemLocales;

            ### Custom Commands

            ### Environment Variables

            ### Proxy

            ### External Tools

            ### Accounts

            ### APIs
          }))
          # add settings from extraConfig
          ++
          (builtins.map (group:
            lib.concatStringsSep "\n" (
              (lib.attrsets.mapAttrsToList (name: value: ''
                ${pkgs.libsForQt5.kconfig}/bin/kwriteconfig5 --file ${configPath}/prismlauncher.cfg --group '${group}' --key '${name}' '${value}'
              '') cfg.extraConfig.${group})
            )
          ) (builtins.attrNames cfg.extraConfig))
        )
      );
    };
  };
}
