{
  stdenv,
  lib,
  fetchFromGitHub,
  kernel,
  kernelModuleMakeFlags,
}:

stdenv.mkDerivation rec {
  pname = "pivccu";
  version = "1.0.85";

  src = fetchFromGitHub {
    owner = "alexreinert";
    repo = "piVCCU";
    rev = "master";
    sha256 = lib.fakeSha256; # Bitte mit echtem Wert ersetzen
    fetchSubmodules = false;
  };

  nativeBuildInputs = kernel.moduleBuildDependencies;
  makeFlags = kernelModuleMakeFlags ++ [
    "KERNELRELEASE=${kernel.modDirVersion}"
    "KSRC=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
  ];

  enableParallelBuilding = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/pivccu"
    install -p -m 644 *.ko "$out/lib/modules/${kernel.modDirVersion}/kernel/drivers/pivccu"
    runHook postInstall
  '';

  meta = with lib; {
    description = "piVCCU Kernel Modules";
    homepage = "https://github.com/alexreinert/piVCCU";
    license = licenses.gpl2Plus;
    maintainers = with maintainers; [ thymythos ];
    platforms = platforms.linux;
  };
}
