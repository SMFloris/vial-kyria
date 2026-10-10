{ nixpkgs ? <nixpkgs> }:
let
  evaluated = import (nixpkgs + "/nixos/lib/eval-config.nix") {
    modules = [
      ../nix/module.nix
      {
        services.kyria-layer = {
          enable = true;
          user = "flow";
          layers."2".underglow.color = "#123456";
          layers."2".keys.H.brightness = 7;
        };
        system.stateVersion = "26.05";
      }
    ];
  };
  cfg = evaluated.config.services.kyria-layer;
in
assert cfg.layers."1".underglow.color == "#ff9600";
assert cfg.layers."2".keys.H.color == "#92dce5";
assert cfg.layers."2".keys.H.brightness == 7;
assert cfg.layers."2".underglow.color == "#123456";
assert builtins.length (builtins.attrNames cfg.layers) == 8;
{
  inherit (cfg) package configFile;
  unit = evaluated.config.systemd.user.units."kyria-layer.service".unit;
}
