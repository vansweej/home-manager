{ pkgs, ... }:

let
  # Fetch a single tree-sitter grammar .wasm file from the npm registry.
  #
  # The npm tarball unpacks with all files under a "package/" directory;
  # --strip-components 1 removes that prefix so the output directory contains
  # only tree-sitter-<name>.wasm.
  #
  # sha256 values were produced by:
  #   nix-prefetch-url https://registry.npmjs.org/tree-sitter-<name>/-/tree-sitter-<name>-<ver>.tgz
  fetchGrammar = { name, version, sha256 }:
    pkgs.runCommand "tree-sitter-${name}-grammar" {} ''
      mkdir -p "$out"
      ${pkgs.gnutar}/bin/tar \
        -xzf ${pkgs.fetchurl {
          url = "https://registry.npmjs.org/tree-sitter-${name}/-/tree-sitter-${name}-${version}.tgz";
          inherit sha256;
        }} \
        --strip-components 1 \
        -C "$out" \
        "package/tree-sitter-${name}.wasm"
    '';

  # Grammars to deploy.  Add new languages here and run home-manager switch.
  # To update a grammar: bump version, recompute sha256 with nix-prefetch-url.
  grammarDefs = [
    { name = "typescript"; version = "0.23.2"; sha256 = "18bqly5v0q4fpmaf9gxrkpaa57c7rdiywxax2j2mi9rhb71n7pqg"; }
    { name = "javascript"; version = "0.25.0"; sha256 = "14pvgx859jknwd9w7grd5jgrcp1nmxycmmpdm1dm5fiss0iww532"; }
    { name = "rust";       version = "0.24.0"; sha256 = "1fy5hsqbn7cvacrjfvsgyyyix79ap7kj4201xw9yq3x4kq5xlj22"; }
    { name = "c";          version = "0.24.1"; sha256 = "07j5ayvy2mi1kri58s8dhn2x5dw08cgvszy0nfhjypb6hxvcv7lf"; }
    { name = "cpp";        version = "0.23.4"; sha256 = "1g3nwwwr9zvgci2i8shv3k3hvi34qb0c74ssy7cbx9p7f0piapb1"; }
    { name = "python";     version = "0.25.0"; sha256 = "15k0s9ba8kwki4573ixz9m8cparb3srcvaylmagdf7qqm0znpdv3"; }
  ];

  # Convert one grammar definition into a home.file attrset entry.
  grammarEntry = { name, version, sha256 }:
    {
      name  = ".local/share/ai-coding/grammars/tree-sitter-${name}.wasm";
      value = {
        source = "${fetchGrammar { inherit name version sha256; }}/tree-sitter-${name}.wasm";
      };
    };

in
{
  # Deploy tree-sitter grammar .wasm files to the default grammars directory.
  #
  # These files are loaded lazily by ParserPool in @ai-coding/codebase when
  # chunkFile() processes a source file whose language has a grammar installed.
  #
  # Default path: ~/.local/share/ai-coding/grammars/
  # Override at runtime via: AI_CODING_GRAMMARS_DIR
  home.file = builtins.listToAttrs (map grammarEntry grammarDefs);
}
