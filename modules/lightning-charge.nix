{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.lightning-charge;
  inherit (config) nix-bitcoin-services;
in {
  options.services.lightning-charge = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the lightning-charge service will be installed.
      '';
    };
    clightning-datadir = mkOption {
      type = types.str;
      default = "/var/lib/clighting/";
      description = ''
        Data directory of the clightning service
      '';
    };
  };

  config = mkIf cfg.enable {
    users.users.lightning-charge = {
        description = "lightning-charge User";
        group = "lightning-charge";
        extraGroups = [ "clightning" ];
    };
    users.groups.lightning-charge = {};

    environment.systemPackages = [ pkgs.nix-bitcoin.lightning-charge ];
    systemd.services.lightning-charge = {
      description = "Run lightning-charge";
      wantedBy = [ "multi-user.target" ];
      requires = [ "clightning.service" ];
      after = [ "clightning.service" ];
      preStart = ''
        # Give existing lightning-charge.db right permissions
        if [[ -e ${config.services.clightning.dataDir}/lightning-charge.db ]]; then
          chown ${config.users.users.lightning-charge.name}:${config.users.users.lightning-charge.group} ${config.services.clightning.dataDir}/lightning-charge.db
          chmod 600 ${config.services.clightning.dataDir}/lightning-charge.db
        fi
        '';
      serviceConfig = nix-bitcoin-services.defaultHardening // {
          PermissionsStartOnly = "true";
          EnvironmentFile = "${config.nix-bitcoin.secretsDir}/lightning-charge-env";
          ExecStart = "${pkgs.nix-bitcoin.lightning-charge}/bin/charged -l ${config.services.clightning.dataDir}/bitcoin -d ${config.services.clightning.dataDir}/lightning-charge.db";
          User = "lightning-charge";
          Restart = "on-failure";
          RestartSec = "10s";
      } // nix-bitcoin-services.nodejs
        // nix-bitcoin-services.allowTor;
    };
    nix-bitcoin.secrets.lightning-charge-env.user = "lightning-charge";
  };
}
