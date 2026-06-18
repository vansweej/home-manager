{ pkgs, ... }:
{
  # Local-disk compiler cache (no cloud). sccache defaults to local storage and
  # ~/.cache/sccache, so we set nothing else for storage.
  #
  # RUSTC_WRAPPER  — routes every `cargo build` (and Rust *-sys / cc-crate C
  #                  builds, which auto-detect sccache) through the cache.
  #                  Inherited into `nix develop` shells.
  # CARGO_INCREMENTAL=0 — sccache cannot cache incrementally-compiled crates, and
  #                  cargo enables incremental for debug builds by default. With
  #                  no Cargo.toml in this repo, this is set globally so DEBUG
  #                  builds are cacheable too (release is already non-incremental).
  home.packages = [ pkgs.sccache ];
  home.sessionVariables = {
    RUSTC_WRAPPER = "${pkgs.sccache}/bin/sccache";
    CARGO_INCREMENTAL = "0";
  };
}
