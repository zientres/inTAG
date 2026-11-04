# NFT metadata

This directory stores one JSON metadata file per NFT. Each file is named by the NFT item index, for example `0.json`.

The collection image is the site's `logo.png`. It is not reused as the image of every NFT: each item has its own SVG plate image in the root `plates/` directory, rendered with that NFT's exact plate combination.

## Generate metadata for an awarded plate

From the repository root, run:

```sh
node scripts/generate-nft-metadata.mjs --index 0 --plate "A777AA 77" --country "Russia" --country-code RUS
```

The command creates:
- `metadata/0.json` — TEP-64 off-chain metadata;
- `plates/0.svg` — individual plate artwork.

Use the JSON filename (for example, `0.json`) as the NFT item's individual content when calling the collection contract. The collection prepends its common content URL, currently `https://zientres.github.io/inTAG/metadata/`.

The item JSON points to its unique image at `https://zientres.github.io/inTAG/plates/0.svg`.

The `--index` must be the next available NFT index returned by the collection contract. The generator refuses to overwrite existing files. Generate and publish the final JSON and SVG before sending the mint transaction.

The generator creates a generic plate visual. Country-specific plate layouts and typography can be refined later without changing the NFT contract interface.
