{ lib, stdenv, cosmic-applets, symlinkJoin, makeWrapper, statusFile ? "%t/kyria-layer.json" }:

# Reuse Nixpkgs' pinned COSMIC workspace and vendored dependencies. Adding a
# member offline keeps this applet compatible with the installed desktop.
let
  appletSource = builtins.path { path = ../applet; name = "kyria-layer-applet"; };
  native = cosmic-applets.overrideAttrs (old: {
    pname = "cosmic-applet-kyria-layer";
    version = "0.1.0";
    src = cosmic-applets.src;
    cargoDeps = cosmic-applets.cargoDeps;
    preBuild = (old.preBuild or "") + ''
      cp -r ${appletSource} cosmic-applet-kyria-layer
      chmod -R u+w cosmic-applet-kyria-layer
      sed -i '/^members = \[/a\    "cosmic-applet-kyria-layer",' Cargo.toml
      cat >> Cargo.lock <<'EOF'

      [[package]]
      name = "cosmic-applet-kyria-layer"
      version = "0.1.0"
      dependencies = ["libcosmic", "serde", "serde_json"]
      EOF
    '';
    cargoBuildFlags = [ "-p" "cosmic-applet-kyria-layer" ];
    cargoTestFlags = [ "-p" "cosmic-applet-kyria-layer" ];
    preFixup = (old.preFixup or "") + ''
      libcosmicAppWrapperArgs+=(--set KYRIA_LAYER_STATUS_FILE ${lib.escapeShellArg statusFile})
    '';
    installPhase = ''
      prefix="$out"
      runHook preInstall
      install -Dm755 target/${stdenv.hostPlatform.rust.cargoShortTarget}/release/cosmic-applet-kyria-layer $out/bin/cosmic-applet-kyria-layer
      install -Dm644 cosmic-applet-kyria-layer/io.github.SMFloris.KyriaLayer.desktop $out/share/applications/io.github.SMFloris.KyriaLayer.desktop
      substituteInPlace $out/share/applications/io.github.SMFloris.KyriaLayer.desktop \
        --replace-fail 'Exec=cosmic-applet-kyria-layer' "Exec=$out/bin/cosmic-applet-kyria-layer"
      runHook postInstall
    '';
    meta = {
      description = "COSMIC panel applet showing the active Kyria layer";
      license = lib.licenses.gpl3Only;
      platforms = lib.platforms.linux;
      mainProgram = "cosmic-applet-kyria-layer";
    };
  });
in
symlinkJoin {
  name = native.name;
  paths = [ native ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    # Wrap explicitly: COSMIC's hook can skip the executable when separate
    # debug output is processed before the main output.
    wrapProgram $out/bin/cosmic-applet-kyria-layer \
      --set KYRIA_LAYER_STATUS_FILE ${lib.escapeShellArg statusFile} \
      --suffix XDG_DATA_DIRS : "$out/share"
    desktop=share/applications/io.github.SMFloris.KyriaLayer.desktop
    rm $out/$desktop
    cp ${native}/$desktop $out/$desktop
    chmod u+w $out/$desktop
    substituteInPlace $out/$desktop \
      --replace-fail "Exec=${native}/bin/" "Exec=$out/bin/"
  '';
  meta = native.meta;
}
