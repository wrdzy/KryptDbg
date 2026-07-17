import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import luaparse from "luaparse";

const toolDirectory = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(toolDirectory, "..");
const expectedModules = [
  "init.lua",
  "src/Manifest.lua",
  "src/KryptUI.lua",
  "src/Runtime.lua",
  "src/features/Explorer.lua",
  "src/features/Remotes.lua",
  "src/features/Scripts.lua",
  "src/features/Console.lua",
  "src/features/Diagnostics.lua",
];

let failed = false;
for (const relativePath of expectedModules) {
  const absolutePath = path.join(root, relativePath);
  if (!fs.existsSync(absolutePath)) {
    console.error(`missing: ${relativePath}`);
    failed = true;
    continue;
  }

  const source = fs.readFileSync(absolutePath, "utf8");
  try {
    luaparse.parse(source, {
      comments: false,
      locations: true,
      luaVersion: "5.3",
    });
    console.log(`syntax: pass ${relativePath}`);
  } catch (error) {
    console.error(`syntax: fail ${relativePath}: ${error.message}`);
    failed = true;
  }
}

const manifest = fs.readFileSync(path.join(root, "src/Manifest.lua"), "utf8");
for (const relativePath of expectedModules.slice(2)) {
  if (!manifest.includes(relativePath) && relativePath !== "src/Runtime.lua") {
    console.error(`manifest: missing dependency ${relativePath}`);
    failed = true;
  }
}

const bootstrap = fs.readFileSync(path.join(root, "init.lua"), "utf8");
if (!bootstrap.includes("KryptDbgBaseUrl") || !bootstrap.includes("manifest.core")) {
  console.error("bootstrap: lazy loader contract is incomplete");
  failed = true;
}

if (failed) {
  process.exit(1);
}

console.log(`validated ${expectedModules.length} Lua modules`);
