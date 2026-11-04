# NFT metadata

This directory will contain one JSON metadata file per minted license-plate NFT.

The collection image is the site's `logo.png`. It is not reused as the image of every NFT: each item must have its own plate image, rendered from that NFT's exact plate combination.

Expected off-chain JSON structure for each item:

```json
{
  "name": "TagitalSpace — [plate combination]",
  "description": "Digital license plate collectible from TagitalSpace.",
  "image": "https://zientres.github.io/inTAG/plates/[item-image].svg",
  "attributes": [
    { "trait_type": "Country", "value": "[country]" },
    { "trait_type": "Plate", "value": "[plate combination]" }
  ]
}
```

The NFT's individual content stored by the collection must be the corresponding JSON filename (for example, `0.json`). The collection's common content URL is concatenated with that filename.

Do not publish placeholder metadata as a real NFT. Before minting an item, publish its final JSON and its unique plate image, then use the matching JSON filename in the mint transaction.
