{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services;

  mkHiddenService = map: {
    map = [ map ];
    version = 3;
  };
in {
  imports = [ ../modules.nix ];

  options = {
    services.clightning.onionport = mkOption {
      type = types.ints.u16;
      default = 9735;
      description = "Port on which to listen for tor client connections.";
    };

    services.electrs.onionport = mkOption {
      type = types.ints.u16;
      default = 50002;
      description = "Port on which to listen for tor client connections.";
    };
  };

  config =  {
    # For backwards compatibility only
    nix-bitcoin.secretsDir = mkDefault "/secrets";

    networking.firewall.enable = true;

    # Tor
    services.tor = {
      enable = true;
      client.enable = true;
      # LND uses ControlPort to create onion services
      controlPort = mkIf cfg.lnd.enable 9051;

      hiddenServices.sshd = mkHiddenService { port = 22; };
    };

    # bitcoind
    services.bitcoind = {
      enable = true;
      listen = true;
      dataDirReadableByGroup = mkIf cfg.electrs.high-memory true;
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      port = 8333;
      zmqpubrawblock = "tcp://127.0.0.1:28332";
      zmqpubrawtx = "tcp://127.0.0.1:28333";
      assumevalid = "00000000000000000000e5abc3a74fe27dc0ead9c70ea1deb456f11c15fd7bc6";
      addnodes = [ "ecoc5q34tmbq54wl.onion" ];
      discover = false;
      addresstype = "bech32";
      prune = 0;
      dbCache = 1000;
    };
    services.tor.hiddenServices.bitcoind = mkHiddenService { port = cfg.bitcoind.port; };

    # clightning
    services.clightning = {
      bitcoin-rpcuser = cfg.bitcoind.rpcuser;
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      always-use-proxy = true;
      bind-addr = "127.0.0.1:${toString cfg.clightning.onionport}";
    };
    services.tor.hiddenServices.clightning = mkHiddenService { port = cfg.clightning.onionport; };

    # lnd
    services.lnd.enforceTor = true;

    # liquidd
    services.liquidd = {
      rpcuser = "liquidrpc";
      prune = 1000;
      extraConfig = ''
        mainchainrpcuser=${cfg.bitcoind.rpcuser}
        mainchainrpcport=8332
      '';
      validatepegin = true;
      listen = true;
      proxy = cfg.tor.client.socksListenAddress;
      enforceTor = true;
      port = 7042;
    };
    services.tor.hiddenServices.liquidd = mkHiddenService { port = cfg.liquidd.port; };

    # electrs
    services.electrs = {
      port = 50001;
      enforceTor = true;
      TLSProxy.enable = true;
      TLSProxy.port = 50003;
    };
    services.tor.hiddenServices.electrs = mkHiddenService {
      port = cfg.electrs.onionport;
      toPort = if cfg.electrs.TLSProxy.enable then cfg.electrs.TLSProxy.port else cfg.electrs.port;
    };

    services.spark-wallet.onion-service = true;

    services.nix-bitcoin-webindex.enforceTor = true;


    environment.systemPackages = with pkgs; [
      tor
      jq
      qrencode
      nix-bitcoin.nodeinfo
    ];

    # Create user 'operator' which can access the node's services
    users.users.operator = {
      isNormalUser = true;
      extraGroups = [
          "systemd-journal"
          cfg.bitcoind.group
        ]
        ++ (optionals cfg.clightning.enable [ "clightning" ])
        ++ (optionals cfg.lnd.enable [ "lnd" ])
        ++ (optionals cfg.liquidd.enable [ cfg.liquidd.group ])
        ++ (optionals (cfg.hardware-wallets.ledger || cfg.hardware-wallets.trezor)
            [ cfg.hardware-wallets.group ]);
      openssh.authorizedKeys.keys = config.users.users.root.openssh.authorizedKeys.keys;
    };
    # Give operator access to onion hostnames
    services.onion-chef.enable = true;
    services.onion-chef.access.operator = [ "bitcoind" "clightning" "nginx" "liquidd" "spark-wallet" "electrs" "sshd" ];

    security.sudo.configFile =
     (optionalString cfg.clightning.enable ''
       operator    ALL=(clightning) NOPASSWD: ALL
     '') +
     (optionalString cfg.lnd.enable ''
       operator    ALL=(lnd) NOPASSWD: ALL
     '');

    # Enable nixops ssh for operator (`nixops ssh operator@mynode`) on nixops-vbox deployments
    systemd.services.get-vbox-nixops-client-key =
      mkIf (builtins.elem ".vbox-nixops-client-key" config.services.openssh.authorizedKeysFiles) {
        postStart = ''
          cp "${config.users.users.root.home}/.vbox-nixops-client-key" "${config.users.users.operator.home}"
        '';
      };
  };
}
