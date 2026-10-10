{ config, lib, pkgs, ... }:

let
  cfg = config.services.kyria-layer;
  ledMap = builtins.fromJSON (builtins.readFile ../host/led-map.json);
  defaults = builtins.fromJSON (builtins.readFile ../host/defaults.json);
  appletPackage = pkgs.callPackage ./applet.nix { inherit (cfg) statusFile; };
  styleType = lib.types.submodule {
    options = {
      color = lib.mkOption {
        type = lib.types.strMatching "#[0-9a-fA-F]{6}";
        description = "RGB color in #RRGGBB format.";
      };
      brightness = lib.mkOption {
        type = lib.types.ints.between 0 255;
        default = 255;
        description = "Brightness from 0 to 255, multiplied by Vial's global brightness.";
      };
    };
  };
  layerType = lib.types.submodule {
    options = {
      name = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Optional layer name. Null shows a numbered icon; a name shows number: name (1–8).";
      };
      keys = lib.mkOption {
        type = lib.types.attrsOf styleType;
        default = { };
        description = ''
          Physical key colors. Use base QWERTY names (H, M, Comma, etc.),
          matrix coordinates such as "5,1", or "*" for all key LEDs.
          Individual entries override "*". Unspecified keys are dark.
        '';
      };
      underglow = lib.mkOption {
        type = styleType;
        default = { color = "#000000"; brightness = 0; };
        description = "Color and brightness of the six installed right-half underglow LEDs.";
      };
    };
  };
  settings = pkgs.writeText "kyria-layer.json" (builtins.toJSON {
    inherit (cfg) layers vendorId productId pollIntervalMs;
  });
  package = pkgs.runCommand "kyria-layer" { } ''
    mkdir -p $out/bin $out/share/kyria-layer
    cp ${../host/kyria_layer.py} $out/share/kyria-layer/kyria_layer.py
    cp ${../host/led-map.json} $out/share/kyria-layer/led-map.json
    printf '#!${pkgs.runtimeShell}\nexec ${pkgs.python3}/bin/python3 %s "$@"\n' \
      "$out/share/kyria-layer/kyria_layer.py" > $out/bin/kyria-layer
    chmod +x $out/bin/kyria-layer
  '';
in {
  options.services.kyria-layer = {
    enable = lib.mkEnableOption "Kyria rev3 host layer status and lighting";
    user = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Restrict the user service to this account; null allows any logged-in user.";
    };
    applet = {
      enable = lib.mkEnableOption "COSMIC panel layer indicator";
      installToPanel = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Add the applet to the panel at login, preserving existing plugins.";
      };
      panel = lib.mkOption {
        type = lib.types.strMatching "[a-zA-Z0-9_-]+";
        default = "Panel";
        description = "COSMIC panel name to install the applet into.";
      };
      package = lib.mkOption {
        type = lib.types.package;
        default = appletPackage;
        readOnly = true;
        description = "Native COSMIC layer indicator applet.";
      };
    };
    layers = lib.mkOption {
      type = lib.types.attrsOf layerType;
      default = { };
      description = "Lighting schemes keyed by layer number, 0 through 7.";
    };
    vendorId = lib.mkOption {
      type = lib.types.ints.between 0 65535;
      default = 36125; # 0x8D1D
      description = "Kyria USB vendor ID.";
    };
    productId = lib.mkOption {
      type = lib.types.ints.between 0 65535;
      default = 53060; # 0xCF44
      description = "Kyria rev3 USB product ID.";
    };
    pollIntervalMs = lib.mkOption {
      type = lib.types.ints.between 10 250;
      default = 50;
      description = "Interval for reading the firmware's actual layer state.";
    };
    statusFile = lib.mkOption {
      type = lib.types.str;
      default = "%t/kyria-layer.json";
      description = "Atomic JSON status file; %t expands to the user's runtime directory.";
    };
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      readOnly = true;
      description = "Packaged CLI, including the --probe command.";
    };
    configFile = lib.mkOption {
      type = lib.types.path;
      default = settings;
      readOnly = true;
      description = "Generated lighting configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.kyria-layer.layers = lib.mapAttrs (_: scheme: {
      keys = lib.mapAttrs (_: style: {
        color = lib.mkDefault style.color;
        brightness = lib.mkDefault style.brightness;
      }) scheme.keys;
      underglow = {
        color = lib.mkDefault scheme.underglow.color;
        brightness = lib.mkDefault scheme.underglow.brightness;
      };
    }) defaults;

    assertions = lib.mapAttrsToList (layer: scheme: {
      assertion = builtins.match "[0-7]" layer != null
        && lib.all (key: key == "*" || builtins.hasAttr key ledMap.keyLeds) (builtins.attrNames scheme.keys);
      message = "services.kyria-layer.layers.${layer}: use a layer 0–7 and valid physical key names or matrix coordinates.";
    }) cfg.layers;

    environment.systemPackages = [ package ] ++ lib.optional cfg.applet.enable appletPackage;
    systemd.user.services.kyria-layer-panel = lib.mkIf (cfg.applet.enable && cfg.applet.installToPanel) {
      description = "Add Kyria layer indicator to the COSMIC panel";
      wantedBy = [ "graphical-session.target" ];
      partOf = [ "graphical-session.target" ];
      unitConfig = lib.optionalAttrs (cfg.user != null) { ConditionUser = cfg.user; };
      serviceConfig = {
        Type = "oneshot";
        ExecStartPre = pkgs.writeShellScript "register-kyria-layer-applet" ''
          desktopDir="''${XDG_DATA_HOME:-$HOME/.local/share}/applications"
          mkdir -p "$desktopDir"
          ln -sfn ${appletPackage}/share/applications/io.github.SMFloris.KyriaLayer.desktop \
            "$desktopDir/io.github.SMFloris.KyriaLayer.desktop"
        '';
        ExecStart = "${appletPackage}/bin/cosmic-applet-kyria-layer --install-panel ${cfg.applet.panel}";
        RemainAfterExit = true;
      };
    };
    services.udev.extraRules = ''
      SUBSYSTEM=="hidraw", ATTRS{idVendor}=="${lib.toLower (lib.fixedWidthString 4 "0" (lib.toHexString cfg.vendorId))}", ATTRS{idProduct}=="${lib.toLower (lib.fixedWidthString 4 "0" (lib.toHexString cfg.productId))}", TAG+="uaccess"
    '';
    systemd.user.services.kyria-layer = {
      description = "Kyria active layer and host-controlled lighting";
      wantedBy = [ "default.target" ];
      unitConfig = lib.optionalAttrs (cfg.user != null) { ConditionUser = cfg.user; };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${package}/bin/kyria-layer --config ${settings} --status-file ${lib.escapeShellArg cfg.statusFile}";
        Restart = "on-failure";
        RestartSec = 2;
        TimeoutStopSec = 3;
        NoNewPrivileges = true;
        UMask = "0077";
      };
    };
  };
}
