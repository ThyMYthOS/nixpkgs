{
  stdenv,
  lib,
  fetchurl,
  php,
}:

let
  source =
    {
      "x86_64-linux" = {
        arch = "x86_64";
        hash = "sha256-TQD7ykcanmDSyAFkPMOuA80Na+EaD2NScKb6g4sPvdw=";
        supportedPhpVersions = [
          "5.3"
          "5.4"
          "5.5"
          "5.6"
          "7.0"
          "7.1"
          "7.2"
          "7.3"
          "7.4"
          "8.0"
          "8.1"
          "8.2"
          "8.3"
          "8.4"
          "8.5"
        ];
      };
      "aarch64-linux" = {
        arch = "aarch64";
        hash = "sha256-iApKOaOACrlV57GsYsHa2YwG94KjkLwF2sB2Zej97oA=";
        supportedPhpVersions = [
          "7.4"
          "8.0"
          "8.1"
          "8.2"
          "8.3"
          "8.4"
          "8.5"
        ];
      };
      "armv7l-linux" = {
        arch = "armhf";
        hash = "sha256-5CDfla8V0lEi/JTtWQOeqf8y2Yz4HbNRtvFxQBUfQL8=";
        supportedPhpVersions = [
          "7.4"
          "8.0"
          "8.1"
          "8.2"
          "8.3"
          "8.4"
          "8.5"
        ];
      };
    }
    .${stdenv.hostPlatform.system};

  phpVersion = lib.versions.majorMinor php.version;
  filename = "ixed.${phpVersion}${lib.optionalString php.ztsSupport "ts"}.lin";
in
assert lib.assertMsg (
  source ? supportedPhpVersions && lib.elem phpVersion source.supportedPhpVersions
) "sourceguardian-loader does not support PHP ${phpVersion} on ${stdenv.hostPlatform.system}";
stdenv.mkDerivation {
  pname = "sourceguardian-loader";
  version = "17.0.0";

  extensionName = "sourceguardian";

  src = fetchurl {
    url = "https://www.sourceguardian.com/loaders/download/loaders.linux-${source.arch}.tar.gz";
    inherit (source) hash;
  };

  installPhase = ''
    runHook preInstall
    install -Dm755 '${filename}' $out/lib/php/extensions/sourceguardian.so
    runHook postInstall
  '';

  meta = {
    description = "PHP loader for SourceGuardian encoded scripts";
    homepage = "https://www.sourceguardian.com/loaders.html";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    license = lib.licenses.unfree;
    maintainers = with lib.maintainers; [ ThyMYthOS ];
    platforms = builtins.attrNames {
      "x86_64-linux" = null;
      "aarch64-linux" = null;
      "armv7l-linux" = null;
    };
  };
}
