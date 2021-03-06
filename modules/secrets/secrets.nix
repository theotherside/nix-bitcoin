{ config, pkgs, lib, ... }:

with lib;
let
  cfg = config.nix-bitcoin;
  setupSecrets = concatStrings (mapAttrsToList (n: v: ''
    setupSecret ${n} ${v.user} ${v.group} ${v.permissions} }
  '') cfg.secrets);
in
{
  options.nix-bitcoin = {
    secretsDir = mkOption {
      type = types.path;
      default = "/etc/nix-bitcoin-secrets";
      description = "Directory to store secrets";
    };

    deployment.secretsDir = mkOption {
      type = types.path;
      description = ''
        Directory of local secrets that are transfered to the nix-bitcoin node on deployment
      '';
    };

    secrets = mkOption {
      default = {};
      type = with types; attrsOf (submodule (
        { config, ... }: {
          options = {
            user = mkOption {
              type = str;
              default = "root";
            };
            group = mkOption {
              type = str;
              default = config.user;
            };
            permissions = mkOption {
              type = str;
              default = "0440";
            };
          };
        }
      ));
    };

    setup-secrets = mkEnableOption "Set permissions for secrets generated by 'generate-secrets.sh'";
  };

  config = mkIf cfg.setup-secrets {
    systemd.targets.nix-bitcoin-secrets = {
      requires = [ "setup-secrets.service" ];
      after = [ "setup-secrets.service" ];
    };

    # Operation of this service:
    #  - Set owner and permissions for all used secrets
    #  - Make all other secrets accessible to root only
    # For all steps make sure that no secrets are copied to the nix store.
    #
    systemd.services.setup-secrets = {
      serviceConfig = {
         Type = "oneshot";
         RemainAfterExit = true;
      };
      script = ''
        setupSecret() {
            file="$1"
            user="$2"
            group="$3"
            permissions="$4"
            if [[ ! -e $file ]]; then
              echo "Error: Secret file '$file' is missing"
              exit 1
            fi
            chown "$user:$group" "$file"
            chmod "$permissions" "$file"
            processedFiles+=("$file")
        }

        dir="${cfg.secretsDir}"
        if [[ ! -e $dir ]]; then
          echo "Error: Secrets dir '$dir' is missing"
          exit 1
        fi
        chown root: "$dir"
        cd "$dir"

        processedFiles=()
        ${setupSecrets}

        # Make all other files accessible to root only
        unprocessedFiles=$(comm -23 <(printf '%s\n' *) <(printf '%s\n' "''${processedFiles[@]}" | sort))
        IFS=$'\n'
        chown root: $unprocessedFiles
        chmod 0440 $unprocessedFiles

        # Now make the secrets dir accessible to other users
        chmod 0751 "$dir"
      '';
    };
  };
}
