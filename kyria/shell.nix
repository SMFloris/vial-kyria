{ pkgs ? import <nixpkgs> { } }:

let
  python = pkgs.python3.withPackages (ps: with ps; [
    qmk appdirs argcomplete colorama dotty-dict hid hjson jsonschema milc
    pygments pyserial pyusb pillow
  ]);
  entry = pkgs.writeText "qmk-cli.py" ''
    import site
    site.addsitedir("${pkgs.qmk}/${pkgs.python3.sitePackages}")
    from qmk_cli.script_qmk import main
    raise SystemExit(main())
  '';
  qmk = pkgs.writeShellScriptBin "qmk" ''
    exec ${python}/bin/python3 ${entry} "$@"
  '';
in pkgs.mkShell {
  packages = [ qmk python pkgs.gcc-arm-embedded pkgs.gnumake pkgs.git pkgs.stdenv.cc ];
  QMK_BIN = "${qmk}/bin/qmk";
}
