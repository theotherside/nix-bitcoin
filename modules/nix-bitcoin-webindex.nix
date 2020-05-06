{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nix-bitcoin-webindex;
  inherit (config) nix-bitcoin-services;
  indexFile = pkgs.writeText "index.html" ''
    <html>
      <body>
        <p>
          <h1>
            nix-bitcoin
          </h1>
        </p>
        <p>
        <h2>
          <a href="store/">store</a>
        </h2>
        </p>
        <p>
        <h3>
          lightning node: CLIGHTNING_ID
        </h3>
        </p>
      </body>
    </html>
  '';
  createWebIndex = pkgs.writeText "make-index.sh" ''
    set -e
    cp ${indexFile} /var/www/index.html
    chown -R nginx /var/www/
    nodeinfo
    . <(nodeinfo)
    sed -i "s/CLIGHTNING_ID/$CLIGHTNING_ID/g" /var/www/index.html
  '';
in {
  options.services.nix-bitcoin-webindex = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the webindex service will be installed.
      '';
    };
    enforceTor =  nix-bitcoin-services.enforceTor;
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d '/var/www' 0755 nginx root - -"
    ];

    services.nginx = {
      enable = true;
      virtualHosts."_" = {
        root = "/var/www";
        extraConfig = ''
          location /store/ {
            proxy_pass http://127.0.0.1:${toString config.services.nanopos.port};
            rewrite /store/(.*) /$1 break;
          }
        '';
      };
    };
    services.tor.hiddenServices.nginx = {
      map = [{
        port = 80;
      } {
        port = 443;
      }];
      version = 3;
    };

    # create-web-index
    systemd.services.create-web-index = {
      description = "Get node info";
      wantedBy = [ "multi-user.target" ];
      after = [ "nodeinfo.service" ];
      path  = with pkgs; [
        config.services.nodeinfo.cli
        config.services.clightning.cli
        config.services.lnd.cli
        jq
        sudo
      ];
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        ExecStart="${pkgs.bash}/bin/bash ${createWebIndex}";
        User = "root";
        Type = "simple";
        RemainAfterExit="yes";
        Restart = "on-failure";
        RestartSec = "10s";
        PrivateNetwork = "true";
        PrivateUsers = "false";
        ReadWritePaths = "/var/www";
        CapabilityBoundingSet = "~CAP_SYS_PTRACE CAP_NET_ADMIN CAP_SYS_TIME CAP_AUDIT_CONTROL CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_BROADCAST CAP_NET_RAW CAP_SYSLOG CAP_SYS_NICE CAP_SYS_RESOURCE CAP_MAC_ADMIN CAP_MAC_OVERRIDE CAP_SYS_BOOT CAP_LINUX_IMMUTABLE CAP_IPC_LOCK CAP_SYS_CHROOT CAP_BLOCK_SUSPEND CAP_LEASE CAP_SYS_PACCT CAP_SYS_TTY_CONFIG CAP_WAKE_ALARM";
      } // (if cfg.enforceTor
          then nix-bitcoin-services.allowTor
          else nix-bitcoin-services.allowAnyIP
        );
    };
  };
}
