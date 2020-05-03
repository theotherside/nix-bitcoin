{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.nodeinfo;
  inherit (config) nix-bitcoin-services;
  dataDir = "/var/lib/nodeinfo/";
  nodeinfo-script = pkgs.writeScript "nodeinfo.sh" ''
    set -e
    set -o pipefail

    BITCOIND_ONION="$(cat /var/lib/onion-chef/${config.users.users.operator.name}/bitcoind)"
    echo BITCOIND_ONION="$BITCOIND_ONION"

    if systemctl is-active --quiet clightning; then
      CLIGHTNING_NODEID=$(lightning-cli getinfo | jq -r '.id')
      CLIGHTNING_ONION="$(cat /var/lib/onion-chef/${config.users.users.operator.name}/clightning)"
      CLIGHTNING_ID="$CLIGHTNING_NODEID@$CLIGHTNING_ONION:9735"
      echo CLIGHTNING_NODEID="$CLIGHTNING_NODEID"
      echo CLIGHTNING_ONION="$CLIGHTNING_ONION"
      echo CLIGHTNING_ID="$CLIGHTNING_ID"
    fi

    if systemctl is-active --quiet lnd; then
      LND_NODEID=$(lncli getinfo | jq -r '.uris[0]')
      echo LND_NODEID="$LND_NODEID"
    fi

    NGINX_ONION_FILE=/var/lib/onion-chef/${config.users.users.operator.name}/nginx
    if [ -e "$NGINX_ONION_FILE" ]; then
      NGINX_ONION="$(cat $NGINX_ONION_FILE)"
      echo NGINX_ONION="$NGINX_ONION"
    fi

    LIQUIDD_ONION_FILE=/var/lib/onion-chef/${config.users.users.operator.name}/liquidd
    if [ -e "$LIQUIDD_ONION_FILE" ]; then
      LIQUIDD_ONION="$(cat $LIQUIDD_ONION_FILE)"
      echo LIQUIDD_ONION="$LIQUIDD_ONION"
    fi

    SPARKWALLET_ONION_FILE=/var/lib/onion-chef/${config.users.users.operator.name}/spark-wallet
    if [ -e "$SPARKWALLET_ONION_FILE" ]; then
      SPARKWALLET_ONION="$(cat $SPARKWALLET_ONION_FILE)"
      echo SPARKWALLET_ONION="http://$SPARKWALLET_ONION"
    fi

    ELECTRS_ONION_FILE=/var/lib/onion-chef/${config.users.users.operator.name}/electrs
    if [ -e "$ELECTRS_ONION_FILE" ]; then
      ELECTRS_ONION="$(cat $ELECTRS_ONION_FILE)"
      echo ELECTRS_ONION="$ELECTRS_ONION"
    fi

    SSHD_ONION_FILE=/var/lib/onion-chef/${config.users.users.operator.name}/sshd
    if [ -e "$SSHD_ONION_FILE" ]; then
    SSHD_ONION="$(cat $SSHD_ONION_FILE)"
    echo SSHD_ONION="$SSHD_ONION"
    fi
  '';
in {
  options.services.nodeinfo = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = ''
        If enabled, the nodeinfo script will be installed.
      '';
    };
    cli = mkOption {
      readOnly = true;
      default = pkgs.writeScriptBin "nodeinfo"
      ''
        exec ${pkgs.bash}/bin/bash ${nodeinfo-script} "$@"
      '';
      description = "Script to execute nodeinfo.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [ (hiPrio cfg.cli) ];
  };  
}
