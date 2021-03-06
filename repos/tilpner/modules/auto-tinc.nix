{ config, pkgs, lib, ... }:

let
  inherit (builtins) hashString substring match all;
  inherit (lib) take drop length stringToCharacters concatStrings intersperse;

  listChunks =
    size: ls: if length ls <= size
                then [ ls ]
                else [ (take size ls) ] ++ (listChunks size (drop size ls));

  nameToIpv6Suffix = name:
    let hash = hashString "sha256" name;
        chunks = listChunks 4 (stringToCharacters (substring 0 16 hash));
    in concatStrings (intersperse ":" (map concatStrings chunks));

  cleanHost = lib.replaceChars ["." "-"] ["_" "_"];
  currentHost = cleanHost config.networking.hostName;

  ipv6 = netName: net: hostName: "${net.ipv6Prefix}${nameToIpv6Suffix "${netName}/${hostName}${net.salt}"}";
  subnets = netName: net: hostName: ''
    Subnet = ${ipv6 netName net hostName}/128
  '';

  tincNameRegex = "[A-Za-z0-9_]+";
  validTincName = name: (match tincNameRegex name) != null;

  cfg = config.services.auto-tinc;
in with lib; {
  options.services.auto-tinc.networks = mkOption {
    default = {};
    type = with types; attrsOf (submodule {
      options = {
        entry = mkOption { type = string; };
        trusted = mkOption { type = bool; default = false; };
        ipv6Prefix = mkOption { type = string; default = "fd7f:8482:73b2::"; };
        salt = mkOption { type = string; default = ""; };
        hosts = mkOption { type = attrsOf string; };
        package = mkOption { type = package; default = pkgs.tinc_pre; };
      };
    });
  };

  config = {
    assertions =
      let netNames = attrNames cfg.networks;
          hostNames = attrNames (zipAttrs (catAttrs "hosts" (attrValues cfg.networks)));
          ipv6sInNetwork = netName: net: mapAttrsToList (hostName: host: ipv6 netName net hostName) net.hosts;
          ipv6s = concatLists (mapAttrsToList ipv6sInNetwork cfg.networks);
      in [
      { assertion = all validTincName netNames;
        message = "A network name doesn't match ${tincNameRegex}"; }
      { assertion = all validTincName hostNames;
        message = "A host name doesn't match ${tincNameRegex}"; }
      { assertion = all (n: stringLength "tinc.${n}" <= 16) netNames;
        message = "Interface names must be <= 16 chars"; }
      { assertion = length ipv6s == length (unique ipv6s);
        message = "There are duplicate IPv6 addresses, try changing salts"; }
    ];

    networking.firewall.trustedInterfaces =
      let f = name: net: if net.trusted then [ "tinc.${name}" ] else [];
      in  concatLists (mapAttrsToList f cfg.networks);

    networking.hosts =
      let forNet = netName: net:
        let forHost = hostName: host:
              nameValuePair (ipv6 netName net hostName) "${hostName}.local";
        in  mapAttrs' forHost net.hosts;
      in  zipAttrs (mapAttrsToList forNet cfg.networks);

    services.tinc.networks =
      let forNet = netName: net: {
            ${netName} = {
              inherit (net) package;
              extraConfig = optionalString (net.entry != null) "ConnectTo = ${net.entry}";
              hosts = mapAttrs (hostName: host: host + (subnets netName net hostName)) net.hosts;
            };
          };
      in  mkMerge (mapAttrsToList forNet cfg.networks);

    environment.etc =
      let ip = "${pkgs.iproute}/bin/ip";
          forNet = netName: net: {
            "tinc/${netName}/tinc-up" = {
              mode = "0755";
              text = ''
                #!${pkgs.stdenv.shell}
                ${ip} link set $INTERFACE up
                ${ip} addr add ${ipv6 netName net currentHost}/64 dev $INTERFACE
              '';
            };

            "tinc/${netName}/tinc-down" = {
              mode = "0755";
              text = ''
                #!${pkgs.stdenv.shell}
                ${ip} link set $INTERFACE down
              '';
            };
          };
      in  mkMerge (mapAttrsToList forNet cfg.networks);
  };
}
