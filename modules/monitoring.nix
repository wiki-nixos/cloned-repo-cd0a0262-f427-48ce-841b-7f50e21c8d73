{ config, lib, pkgs, ... }:
let
  cfg = config.my.services.monitoring;
  MONIT_PORT = 2812;

  checkSystemdService = pkgs.writeScript "check-systemd-service" ''
    #!/bin/sh
    LOGS=$(${pkgs.systemd}/bin/systemctl status "$1")
    if [ $? == 0 ]; then
      echo "Running"
      echo "''${LOGS}"
      exit 0
    else
      if $(echo "''${LOGS}" | ${pkgs.gnugrep}/bin/grep --quiet 'Active: activating'); then
        echo "Starting up"
        echo "''${LOGS}"
        exit 0
      fi
      if [ "$2" == "running" ]; then
        echo "Stopped"
        echo "''${LOGS}"
        exit 1
      elif [ "$2" == "succeeded" ]; then
        if $(echo "''${LOGS}" | ${pkgs.gnugrep}/bin/grep --quiet 'Deactivated successfully'); then
          echo "Last run ok"
          echo "''${LOGS}"
          exit 0
        fi
        echo "Last run failed"
        echo "''${LOGS}"
        exit 1
      else
        echo "Invalid expected state"
        exit 2
      fi
    fi
  '';

in {
  options.my.services.monitoring = {
    enable = lib.mkEnableOption "valvonta palvelu";
    checks = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
    };
    virtualHost = lib.mkOption {
      type = lib.types.str;
    };
  };

  config.services.monit = lib.mkIf cfg.enable {
    enable = true;
    config = builtins.concatStringsSep "\n" (
      [''
        set daemon 60
        set limits { programoutput: 5 kB }
        set httpd port ${toString MONIT_PORT}
            allow localhost
      '']
      ++
      (builtins.map (check: 
        if check.type == "systemd service" then
          ''
            check program "${if check ? description then check.description else check.name}" with path "${checkSystemdService} ${check.name} ${check.expected}"
              if status != 0 then alert
          ''
        else if check.type == "program" then
          ''
            check program "${check.description}" with path "${check.path}"
              if status != 0 then alert
          ''
        else if check.type == "http check" then
          ''
            check host "${check.description}" with address ${check.domain}
              if failed
                port ${if check.secure then "443" else "80"}
                ${if check.secure then "certificate valid > 30 days" else ""}
                protocol ${if check.secure then "https" else "http"}
                  ${if check ? path then "request ${check.path}" else ""}
                  ${if check ? response.code then "status ${toString check.response.code}" else ""}
              then alert
          ''
        else abort "Unknown check type for monioring: ${check.type}"
      ) cfg.checks)
    );
  };

  config.services.nginx = lib.mkIf cfg.enable {
    enable = true;
    virtualHosts.${cfg.virtualHost} = {
      locations."/" = {
        proxyPass = "http://127.0.0.1:${toString MONIT_PORT}";
        recommendedProxySettings = true;
      };
      # Käytä Let's Encrypt sertifikaattia
      addSSL = true;
      useACMEHost = "jhakonen.com";
    };
  };
}
