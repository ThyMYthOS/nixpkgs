{
  lib,
  pkgs,
  stdenv,
  fetchurl,
  makeWrapper,
  php84,
  coreutils,
  gnugrep,
  gnutar,
  zip,
  unzip,
  tnef,
  nixosTests,
  withSourceGuardian ? false,
}:

let
  php = php84.buildEnv {
    extensions =
      { enabled, all }:
      enabled
      ++ (with all; [
        apcu
        bcmath
        calendar
        curl
        dom
        exif
        gd
        intl
        ldap
        mbstring
        mysqli
        mysqlnd
        opcache
        pcntl
        pdo
        pdo_mysql
        posix
        soap
        sysvmsg
        sysvsem
        sysvshm
        all.zip
      ])
      ++ lib.optionals withSourceGuardian [ all.sourceguardian ];

    extraConfig = ''
      expose_php=Off
      output_buffering=Off
      file_uploads=On
      upload_max_filesize=50M
      post_max_size=55M
    '';
  };

  runtimePath = lib.makeBinPath [
    coreutils
    gnugrep
    gnutar
    zip
    unzip
    tnef
    pkgs."poppler-utils"
    php
  ];
in
assert lib.assertMsg (
  !(withSourceGuardian && !stdenv.hostPlatform.isLinux)
) "withSourceGuardian is only supported on Linux";
stdenv.mkDerivation (finalAttrs: {
  pname = "groupoffice";
  version = "26.0.6";

  src = fetchurl {
    url = "https://github.com/Intermesh/groupoffice/releases/download/v${finalAttrs.version}/groupoffice-${finalAttrs.version}.tar.gz";
    hash = "sha256-b+Q7g+Dh5pL1vmAfAqzx4qfXv+bx4uHMD97SeKklJ0g=";
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  postPatch = ''
    # Replace hardcoded FHS command paths with Nix store paths.
    substituteInPlace go/base/Config.php \
      --replace-fail "var \$cmd_zip = '/usr/bin/zip';" "var \$cmd_zip = '${lib.getExe zip}';" \
      --replace-fail "var \$cmd_unzip = '/usr/bin/unzip';" "var \$cmd_unzip = '${lib.getExe unzip}';" \
      --replace-fail "var \$cmd_tar = '/bin/tar';" "var \$cmd_tar = '${lib.getExe gnutar}';" \
      --replace-fail "var \$cmd_tnef = '/usr/bin/tnef';" "var \$cmd_tnef = '${lib.getExe tnef}';" \
      --replace-fail "var \$cmd_php = 'php';" "var \$cmd_php = '${php}/bin/php';"
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/share/groupoffice
    cp -r . $out/share/groupoffice

    makeWrapper ${php}/bin/php $out/bin/groupoffice-cli \
      --add-flags "$out/share/groupoffice/groupofficecli.php" \
      --prefix PATH : "${runtimePath}"

    makeWrapper ${php}/bin/php $out/bin/groupoffice-cron \
      --add-flags "$out/share/groupoffice/cron.php" \
      --prefix PATH : "${runtimePath}"

    makeWrapper ${php}/bin/php $out/bin/groupoffice \
      --add-flags "$out/share/groupoffice/groupofficecli.php" \
      --prefix PATH : "${runtimePath}"

    runHook postInstall
  '';

  passthru = {
    inherit php;
    tests = lib.optionalAttrs (nixosTests ? groupoffice) {
      inherit (nixosTests) groupoffice;
    };
  };

  meta = {
    description = "Groupware and CRM platform";
    homepage = "https://www.group-office.com/";
    changelog = "https://github.com/Intermesh/groupoffice/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ ThyMYthOS ];
    mainProgram = "groupoffice";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
