{ config, lib, pkgs, inputs, ... }:

let
  deployDir = "${config.home.homeDirectory}/.local/share/pavo";
  stateDir = "${config.home.homeDirectory}/.local/state/pavo";
  stampFile = "${stateDir}/source-stamp";
  pavoSrc = inputs.pavo;

  # pavo is DEPLOYED (copied) from the pinned `inputs.pavo` store path into a
  # writable dir — it is NOT a git checkout. Update path:
  #   nix flake update pavo && home-manager switch
  #
  # Two independent stamps, distinct roles, both required:
  #   activation stamp  ${stateDir}/source-stamp        — which source store path is DEPLOYED
  #   launcher stamp    ${deployDir}/.gem/.bootstrapped-src — which source store path has been BUNDLED
  # The activation stamp lives OUTSIDE the deploy dir so `rsync --delete` cannot
  # delete it (it does not exist in the source tree). The launcher stamp lives
  # INSIDE .gem/, which is rsync-excluded, so it survives re-syncs.
  pavoLauncher = pkgs.writeShellScriptBin "pavo" ''
    set -euo pipefail

    deploy="${deployDir}"
    stamp="$deploy/.gem/.bootstrapped-src"

    cd "$deploy"

    # Auto-bootstrap: .gem/ is the bootstrap sentinel. NEVER test -d db —
    # db/ is a tracked dir in pavo (db/migrate/...) so it is always present.
    # No "warn but continue" branch: bin/dev needs foreman/overmind (a Gemfile
    # gem absent from the devShell buildInputs), so continuing without a bundle
    # yields a confusing missing-executable crash.
    if [ ! -f "$stamp" ] || [ "$(${pkgs.coreutils}/bin/cat "$stamp")" != "${pavoSrc}" ]; then
      echo "pavo: bootstrapping (first run or pavo updated) — fetching the nixos-24.11 toolchain and installing gems." >&2
      echo "pavo: this can take 5-15 minutes and only happens once per pavo source change." >&2
      nix develop . --command bin/setup
      # Write the launcher stamp ONLY after bin/setup succeeds, so an interrupted
      # setup leaves no stamp and the next run correctly re-triggers setup.
      printf '%s\n' "${pavoSrc}" > "$stamp"
    fi

    echo "pavo: starting development server — dashboard will be at http://localhost:3000" >&2
    exec nix develop . --command bin/dev
  '';
in
{
  home.file.".local/bin/pavo".source = "${pavoLauncher}/bin/pavo";

  home.activation.deployPavo = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${deployDir}"
    $DRY_RUN_CMD ${pkgs.coreutils}/bin/mkdir -p "${stateDir}"

    currentSrc="${pavoSrc}"
    deployedSrc=""
    if [ -f "${stampFile}" ]; then
      deployedSrc="$(${pkgs.coreutils}/bin/cat "${stampFile}")"
    fi

    if [ "$deployedSrc" != "$currentSrc" ]; then
      # rsync --delete removes receiver-side files absent from the source, EXCEPT
      # paths matched by --exclude (that would need --delete-excluded, which must
      # NEVER be added). This is exactly why .gem/, db/*.sqlite3, log/ and tmp/
      # survive a re-sync. vendor/ is tracked in pavo and is NOT excluded, so it
      # syncs normally. log/ and tmp/ excludes are largely cosmetic (Rails
      # gitignores their contents; source holds at most .keep files) but kept.
      # --chmod=Du+rwx,Fu+rw restores owner write + directory traversability on
      # the read-only store-sourced files.
      $DRY_RUN_CMD ${pkgs.rsync}/bin/rsync -a --delete \
        --chmod=Du+rwx,Fu+rw \
        --exclude='.gem/' \
        --exclude='db/*.sqlite3' \
        --exclude='log/' \
        --exclude='tmp/' \
        "${pavoSrc}/" "${deployDir}/"
      $DRY_RUN_CMD ${pkgs.coreutils}/bin/cp /dev/stdin "${stampFile}" <<< "$currentSrc"
    fi
  '';
}
