{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.services.gmux;
  toml = pkgs.formats.toml { };

  configFile =
    mode:
    if mode.configFile != null then mode.configFile else toml.generate "gmux-${mode.unit}.toml" mode.settings;

  # Mirrors the generated agent installer's unit: the runtime directory gives a
  # HOME-less service a private control socket directory.
  commonService = mode: {
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = [ pkgs.bashInteractive ] ++ mode.extraPackages;
    environment.GMUX_SOCKET_DIR = "%t/${mode.unit}";
    serviceConfig = {
      Restart = "always";
      RestartSec = 5;
      RuntimeDirectory = mode.unit;
      RuntimeDirectoryMode = "0700";
      StateDirectory = mode.unit;
      StateDirectoryMode = "0700";
      EnvironmentFile = lib.optional (mode.environmentFile != null) mode.environmentFile;
    };
  };

  modeOptions = unit: {
    settings = lib.mkOption {
      inherit (toml) type;
      default = { };
      description = ''
        gmux TOML configuration. `''${VAR}` placeholders are expanded from the
        environment, so secrets belong in {option}`environmentFile`.
      '';
    };
    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "Existing TOML config file; overrides {option}`settings`.";
    };
    environmentFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      description = "systemd EnvironmentFile read by the service, kept out of the Nix store.";
    };
    extraPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [ ];
      description = "Packages on PATH for commands the streams run.";
    };
    unit = lib.mkOption {
      type = lib.types.str;
      default = unit;
      internal = true;
    };
  };
in
{
  options.services.gmux = {
    package = lib.mkOption {
      type = lib.types.package;
      description = "gmux package.";
    };

    serve = modeOptions "gmux" // {
      enable = lib.mkEnableOption "a long-lived gmux hub (`gmux serve`)";
      web = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        example = "127.0.0.1:8088";
        description = ''
          Dashboard listener address. A non-loopback address requires users or
          OAuth in the configuration.
        '';
      };
    };

    agent = modeOptions "gmux-agent" // {
      enable = lib.mkEnableOption "a gmux federation agent (`gmux agent run`)";
      name = lib.mkOption {
        type = lib.types.str;
        default = config.networking.hostName;
        defaultText = lib.literalExpression "config.networking.hostName";
        description = "Agent name; must match the token record on the central.";
      };
      url = lib.mkOption {
        type = lib.types.str;
        example = "wss://gmux.example.com/api/agent/ws";
        description = "Carrier URL of the central.";
      };
      tokenFile = lib.mkOption {
        type = lib.types.path;
        description = "File holding only the agent token issued by the central.";
      };
      ca = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        description = "Additional PEM roots for a tls:// carrier.";
      };
      serverName = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Verified TLS server name override for a tls:// carrier.";
      };
      insecureTransport = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Lab only: allow ws:// off loopback or tcp:// on loopback.";
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf (cfg.serve.enable || cfg.agent.enable) {
      environment.systemPackages = [ cfg.package ];
    })

    (lib.mkIf cfg.serve.enable {
      services.gmux.serve.settings.state_dir = lib.mkDefault "/var/lib/gmux";
      systemd.services.gmux = lib.recursiveUpdate (commonService cfg.serve) {
        description = "gmux hub";
        serviceConfig.ExecStart = lib.escapeShellArgs (
          [
            (lib.getExe cfg.package)
            "serve"
            "--config"
            (configFile cfg.serve)
            "--no-update-check"
          ]
          ++ lib.optionals (cfg.serve.web != null) [
            "--web"
            cfg.serve.web
          ]
        );
      };
    })

    (lib.mkIf cfg.agent.enable {
      services.gmux.agent.settings = {
        state_dir = lib.mkDefault "/var/lib/gmux-agent";
        stream = lib.mkDefault [
          {
            name = "host-shell";
            type = "cmd";
            command = "bash";
          }
        ];
      };
      systemd.services.gmux-agent = lib.recursiveUpdate (commonService cfg.agent) {
        description = "gmux federation agent";
        serviceConfig.LoadCredential = [ "token:${cfg.agent.tokenFile}" ];
        # The token is read at start so it never lands in the Nix store or unit.
        script = ''
          exec ${lib.getExe cfg.package} agent run \
            --name ${lib.escapeShellArg cfg.agent.name} \
            --url ${lib.escapeShellArg cfg.agent.url} \
            --token "$(< "$CREDENTIALS_DIRECTORY/token")" \
            --config ${configFile cfg.agent} \
            --no-update-check ${
              lib.escapeShellArgs (
                lib.optionals (cfg.agent.ca != null) [
                  "--ca"
                  cfg.agent.ca
                ]
                ++ lib.optionals (cfg.agent.serverName != null) [
                  "--server-name"
                  cfg.agent.serverName
                ]
                ++ lib.optional cfg.agent.insecureTransport "--insecure-transport"
              )
            }
        '';
      };
    })
  ];
}
