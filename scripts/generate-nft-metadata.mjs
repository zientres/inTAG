#!/usr/bin/env node
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

function readOption(name) {
  const index = process.argv.indexOf(`--${name}`);
  return index === -1 ? null : process.argv[index + 1] ?? null;
}

function required(name) {
  const value = readOption(name);
  if (!value || value.startsWith("--")) {
    throw new Error(`Missing required option --${name}`);
  }
  return value.trim();
}

function escapeXml(value) {
  return value.replaceAll("&", "&amp;").replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;").replaceAll('"', "&quot;")
    .replaceAll("'", "&apos;");
}

const indexText = required("index");
if (!/^\d+$/.test(indexText)) throw new Error("--index must be a non-negative integer");
const index = Number(indexText);
if (!Number.isSafeInteger(index)) throw new Error("--index is too large");

const plate = required("plate");
const country = required("country");
const countryCode = required("country-code").toUpperCase();
if (!/^[A-Z0-9]{2,4}$/.test(countryCode)) {
  throw new Error("--country-code must contain 2–4 Latin letters or digits");
}

const description = readOption("description") ??
  `Digital license plate collectible from TagitalSpace. ${country}: ${plate}.`;
const root = process.cwd();
const metadataDir = resolve(root, "metadata");
const platesDir = resolve(root, "plates");
const metadataPath = resolve(metadataDir, `${index}.json`);
const imagePath = resolve(platesDir, `${index}.svg`);

if (existsSync(metadataPath) || existsSync(imagePath)) {
  throw new Error(`NFT index ${index} already has metadata or an image. Choose another index.`);
}

const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="1200" height="720" viewBox="0 0 1200 720">
  <defs>
    <linearGradient id="background" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#101d36"/>
      <stop offset="1" stop-color="#07101f"/>
    </linearGradient>
    <linearGradient id="plate" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#ffffff"/>
      <stop offset="1" stop-color="#e8edf4"/>
    </linearGradient>
  </defs>
  <rect width="1200" height="720" fill="url(#background)"/>
  <text x="600" y="130" fill="#aab8ce" font-family="Arial, sans-serif" font-size="28" letter-spacing="8" text-anchor="middle">TAGITALSPACE</text>
  <rect x="105" y="225" width="990" height="270" rx="26" fill="#020713" opacity=".55"/>
  <rect x="120" y="210" width="960" height="270" rx="20" fill="url(#plate)" stroke="#cbd5e1" stroke-width="5"/>
  <text x="600" y="385" fill="#101827" font-family="Arial, sans-serif" font-size="108" font-weight="700" letter-spacing="4" text-anchor="middle">${escapeXml(plate)}</text>
  <rect x="895" y="210" width="185" height="270" rx="0 20 20 0" fill="#dce4ef"/>
  <text x="987" y="330" fill="#14243d" font-family="Arial, sans-serif" font-size="43" font-weight="700" text-anchor="middle">${escapeXml(countryCode)}</text>
  <text x="987" y="390" fill="#52627a" font-family="Arial, sans-serif" font-size="22" text-anchor="middle">${escapeXml(country)}</text>
  <text x="600" y="590" fill="#71829c" font-family="Arial, sans-serif" font-size="22" letter-spacing="4" text-anchor="middle">DIGITAL COLLECTIBLE • #${index}</text>
</svg>
`;

const metadata = {
  name: `TagitalSpace — ${plate}`,
  description,
  image: `https://zientres.github.io/inTAG/plates/${index}.svg`,
  attributes: [
    { trait_type: "Country", value: country },
    { trait_type: "Country code", value: countryCode },
    { trait_type: "Plate", value: plate },
    { trait_type: "Item index", value: index }
  ]
};

mkdirSync(metadataDir, { recursive: true });
mkdirSync(platesDir, { recursive: true });
writeFileSync(imagePath, `${svg}\n`, { flag: "wx" });
try {
  writeFileSync(metadataPath, `${JSON.stringify(metadata, null, 2)}\n`, { flag: "wx" });
} catch (error) {
  // Avoid leaving an image behind if writing the matching JSON fails.
  const { unlinkSync } = await import("node:fs");
  unlinkSync(imagePath);
  throw error;
}

console.log(`Created metadata/${index}.json and plates/${index}.svg`);
console.log(`NFT content filename: ${index}.json`);
