# The onion chef module allows unprivileged users to read onion hostnames.
# By default the onion hostnames in /var/lib/tor/onion are only readable by the
# tor user. The onion chef copies the onion hostnames into into
# /var/lib/onion-chef and sets permissions according to the access option.

{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.onion-chef;
  inherit (config) nix-bitcoin-services;
  dataDir = "/var/lib/onion-chef/";
  onion-chef-script = pkgs.writeScript "onion-chef.sh" ''
    # wait until tor is up
    until ls -l /var/lib/tor/state; do sleep 1; done

    mkdir -p -m 0755 ${dataDir}
    cd ${dataDir}

    # Create directory for every user and set permissions
    ${ builtins.foldl'
      (x: user: x +
        ''
        mkdir -p -m 0700 ${user}
        chown ${user} ${user}
          # Copy onion hostnames into the user's directory
          ${ builtins.foldl'
            (x: onion: x +
              ''
              ONION_FILE=/var/lib/tor/onion/${onion}/hostname
              if [ -e "$ONION_FILE" ]; then
                cp $ONION_FILE ${user}/${onion}
                chown ${user} ${user}/${onion}
              fi
              '')
            ""
            (builtins.getAttr user cfg.access)
          }
        '')
      ""
      (builtins.attrNames cfg.access)
    }
  '';
in {
  options.services.onion-chef = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the onion-chef service will be installed.
      '';
    };
    access = mkOption {
      type = types.attrs;
      default = {};
      description = ''
        This option controls who is allowed to access onion hostnames.  For
        example the following allows the user operator to access the bitcoind
        and clightning onion.
        {
          "operator" = [ "bitcoind" "clightning" ];
        };
        The onion hostnames can then be read from
        /var/lib/onion-chef/<user>.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.services.onion-chef = {
      description = "Run onion-chef";
      wantedBy = [ "tor.service" ];
      bindsTo = [ "tor.service" ];
      after = [ "tor.service" ];
      serviceConfig = nix-bitcoin-services.defaultHardening // {
        ExecStart = "${pkgs.bash}/bin/bash ${onion-chef-script}";
        Type = "oneshot";
        RemainAfterExit = true;
        PrivateNetwork = "true";
        ReadWritePaths = "${dataDir}";
        CapabilityBoundingSet = "~CAP_SETUID CAP_SETGID CAP_SETPCAP CAP_SYS_ADMIN CAP_SYS_PTRACE CAP_NET_ADMIN CAP_SYS_TIME CAP_AUDIT_CONTROL CAP_AUDIT_READ CAP_AUDIT_WRITE CAP_KILL CAP_MKNOD CAP_NET_BIND_SERVICE CAP_NET_BROADCAST CAP_NET_RAW CAP_SYSLOG CAP_SYS_NICE CAP_SYS_RESOURCE CAP_MAC_ADMIN CAP_MAC_OVERRIDE CAP_SYS_BOOT CAP_LINUX_IMMUTABLE CAP_IPC_LOCK CAP_SYS_CHROOT CAP_BLOCK_SUSPEND CAP_LEASE CAP_SYS_PACCT CAP_SYS_TTY_CONFIG CAP_WAKE_ALARM";
      };
    };
  };
}
