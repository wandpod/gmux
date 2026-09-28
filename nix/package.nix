{
  lib,
  stdenvNoCC,
  fetchurl,
}:

let
  sources = lib.importJSON ./sources.json;
  # Nix system -> release target name.
  targets = {
    x86_64-linux = "linux-amd64";
    aarch64-linux = "linux-arm64";
    armv6l-linux = "linux-arm";
    armv7l-linux = "linux-arm";
    aarch64-darwin = "darwin-arm64";
  };
  system = stdenvNoCC.hostPlatform.system;
  target = targets.${system} or (throw "gmux: no release for ${system}");
  asset =
    name:
    fetchurl {
      url = "https://get.wandpod.com/gmux/${sources.version}/${name}";
      hash = sources.hashes.${name};
    };
in
stdenvNoCC.mkDerivation {
  pname = "gmux";
  inherit (sources) version;

  src = asset "gmux-${target}.tar.gz";
  bundle = asset "gmux-agent-binaries.tar.gz";
  sourceRoot = ".";

  # Static Go binaries: nothing to patch or strip.
  dontConfigure = true;
  dontBuild = true;
  dontFixup = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 gmux $out/bin/gmux
    ln -s gmux $out/bin/gmux-shell
    mkdir -p $out/lib/gmux
    tar xzf $bundle -C $out/lib/gmux
    install -Dm644 completions/gmux.bash $out/share/bash-completion/completions/gmux
    install -Dm644 completions/_gmux $out/share/zsh/site-functions/_gmux
    install -Dm644 completions/gmux.fish $out/share/fish/vendor_completions.d/gmux.fish
    install -Dm644 completions/gmux.nu $out/share/nushell/vendor/autoload/gmux.nu
    install -Dm644 completions/gmux.ps1 $out/share/gmux/completions/gmux.ps1
    install -Dm644 -t $out/share/licenses/gmux LICENSE THIRD_PARTY_NOTICES
    runHook postInstall
  '';

  passthru.releaseTargets = sources.releaseTargets;

  meta = {
    description = "Stream multiplexer";
    homepage = "https://github.com/wandpod/gmux";
    license = lib.licenses.unfreeRedistributable;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    mainProgram = "gmux";
    platforms = builtins.attrNames targets;
  };
}
