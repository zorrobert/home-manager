{ config, lib, pkgs, ... }:

let
  cfg = config.programs.digikam;

  #configPath = "${config.xdg.configHome}/digikam_systemrc";
in {
  meta.maintainers = [ lib.hm.maintainers.zorrobert ];

  options.programs.digikam = {
    enable = lib.mkEnableOption "digikam";

    package = lib.mkPackageOption pkgs "digikam" { };

    extraConfig = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      example = { };
      description = ''
        Additional settings for Digikam
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = [ cfg.package ];

    home.activation = {
      createDigikamConfig = lib.hm.dag.entryAfter [ "linkGeneration" ] ();
    };
  };
}
