{ lib, stdenvNoCC, fetchurl, jre_headless, jq, moreutils, curl, cacert }:

let
  localPackwizModpack =
    { pname ? "packwiz-pack"
    , version ? ""
    , modpackPath
    , packHash ? ""
      # Either 'server' or 'both' (to get client mods as well)
    , side ? "server"
    , ...
    }@args:

    stdenvNoCC.mkDerivation (finalAttrs: rec {
      inherit pname version;

      packwizInstaller = fetchurl rec {
        pname = "packwiz-installer";
        version = "0.5.8";
        url = "https://github.com/packwiz/${pname}/releases/download/v${version}/${pname}.jar";
        hash = "sha256-+sFi4ODZoMQGsZ8xOGZRir3a0oQWXjmRTGlzcXO/gPc=";
      };

      packwizInstallerBootstrap = fetchurl rec {
        pname = "packwiz-installer-bootstrap";
        version = "0.0.3";
        url = "https://github.com/packwiz/${pname}/releases/download/v${version}/${pname}.jar";
        hash = "sha256-qPuyTcYEJ46X9GiOgtPZGjGLmO/AjV2/y8vKtkQ9EWw=";
      };

      packTomlPath = "${modpackPath}/pack.toml";

      dontUnpack = true;

      buildInputs = [ jre_headless jq moreutils curl cacert ];

      buildPhase = ''
        java -jar "$packwizInstallerBootstrap" \
          --bootstrap-main-jar "$packwizInstaller" \
          --bootstrap-no-update \
          --no-gui \
          --side "${side}" \
          "$packTomlPath"
      '';

      installPhase = ''
        runHook preInstall

        # Fix non-determinism
        rm env-vars -r
        jq -Sc '.' packwiz.json | sponge packwiz.json

        mkdir -p $out
        cp * -r $out/

        runHook postInstall
      '';

      passthru =
        let
          drv = localPackwizModpack args;
        in
        {
          # Pack manifest as a nix expression
          # If manifestHash is not null, then we can do this without IFD.
          # Otherwise, fallback to IFD.
          manifest = lib.importTOML packTomlPath;

          # Adds an attribute set of files to the derivation.
          # Useful to add server-specific mods not part of the pack.
          addFiles = files:
            stdenvNoCC.mkDerivation {
              inherit (drv) pname version;
              src = null;
              dontUnpack = true;
              dontConfig = true;
              dontBuild = true;
              dontFixup = true;

              installPhase = ''
                cp -as "${drv}" $out
                chmod u+w -R $out
              '' + lib.concatLines (lib.mapAttrsToList
                (name: file: ''
                  mkdir -p "$out/$(dirname "${name}")"
                  cp -as "${file}" "$out/${name}"
                '')
                files
              );

              passthru = { inherit (drv) manifest; };
              meta = drv.meta or { };
            };
        };

      dontFixup = true;

      outputHashMode = "recursive";
      outputHashAlgo = "sha256";
      outputHash = packHash;
    } // args);
in
localPackwizModpack
