{ lib, stdenv, fetchurl, autoPatchelfHook, udev }:

let
  hashes = {
    x86_64-linux = "49593a0cca4a6d8212bf28147902d75ba59c326aebb2110a44cebf1edf4bdbff";
    aarch64-linux = "85e5cffbddbc6e255178ec7d8d423d0ad3e55bbc27683b3324a10b21b5cd36fe";
  };
  target = stdenv.hostPlatform.rust.rustcTarget;
in stdenv.mkDerivation {
  pname = "vitaly";
  version = "0.1.32";
  src = fetchurl {
    url = "https://github.com/bskaplou/vitaly/releases/download/v0.1.32/vitaly-${target}.tar.xz";
    sha256 = hashes.${stdenv.hostPlatform.system};
  };
  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ udev stdenv.cc.cc.lib ];
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm755 vitaly $out/bin/vitaly
    runHook postInstall
  '';
  meta = {
    description = "VIA/Vial keyboard command-line client";
    homepage = "https://github.com/bskaplou/vitaly";
    license = lib.licenses.mit;
    platforms = builtins.attrNames hashes;
    mainProgram = "vitaly";
  };
}
