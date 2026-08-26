{ inputs, meta, ... }:

let
  argusPkg = inputs.argus.packages.${meta.system}.default;
in
{
  home.file.".local/bin/argus".source = "${argusPkg}/bin/argus";
}
