{haskell, lib
}:
{ pluginPackage #The package the plugin is from
, pluginName  #The module name of the plugin
 # Options to pass to the plugin, the first argument is the directoy the plugin
 # should place any files it creates.
, pluginOpts ? (out-path: [])
# Additional system dependencies to run the finalPhase
, pluginDepends ? []
# The script to run after the plugin has compiled
, finalPhase ? (out-path: [])
}:
pkg:
let
  hlib = haskell.lib;

  # The bash string which will expand to the output directory when
  # the builder runs.
  pluginOutputDir = "$" + pluginName;

  # Create a new output for the plugin to put files into.
  # For example, if the plugin is called `DumpCore` and we run
  # it on the `either` package then we can access its output at
  # the attribute `either.DumpCore`.
  addOutput = drv: drv.overrideAttrs(oldAttrs:
                  { outputs = (oldAttrs.outputs ++ [ pluginName ]); });

  phases = drv: hlib.overrideCabal drv (drv: {
                  # Make the output even if the plugin doesn't output
                  # anything.
                  postUnpack = ''
                    mkdir -p ${pluginOutputDir}
                    echo Plugin output directory: ${pluginOutputDir}'';
                  # Give the plugin some chance to collate the results.
                  postBuild  = finalPhase pluginOutputDir;
                });

  # Build the plugin options.
  string-opt = arg:  "-fplugin-opt=${pluginName}:${arg}";
  string-opts = lib.concatMapStrings string-opt (pluginOpts "${pluginOutputDir}");

  additionalDepends = [pluginPackage] ++ pluginDepends;
in
  with hlib;
  phases (
    addOutput (
    (addBuildDepends
    (appendBuildFlag pkg "--ghc-options=\"-fplugin=${pluginName} -plugin-package=${pluginPackage.pname} ${string-opts}\"") additionalDepends)))

