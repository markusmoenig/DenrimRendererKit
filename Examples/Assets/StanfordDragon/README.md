# Stanford Dragon Asset

This folder is the persistent local home for the Stanford Dragon benchmark mesh used by the example SceneScript files.

The mesh is not vendored directly because the full archive is external benchmark data from the Stanford Computer Graphics Laboratory. Fetch it with:

```sh
./Examples/Tools/fetch-stanford-dragon.sh
```

The script downloads the official Stanford reconstruction archive and extracts the small interactive-resolution mesh to:

```text
Examples/Assets/StanfordDragon/Meshes/dragon_vrip_res4.ply
```

Source: https://graphics.stanford.edu/data/3Dscanrep/

