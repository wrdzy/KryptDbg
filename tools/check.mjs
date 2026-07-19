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
  "src/features/Settings.lua",
];
const expectedAssets = [
  "assets/lucide-kryptdbg.png",
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

for (const relativePath of expectedAssets) {
  const absolutePath = path.join(root, relativePath);
  if (!fs.existsSync(absolutePath)) {
    console.error(`missing: ${relativePath}`);
    failed = true;
    continue;
  }

  const contents = fs.readFileSync(absolutePath);
  const pngSignature = "89504e470d0a1a0a";
  const width = contents.length >= 24 ? contents.readUInt32BE(16) : 0;
  const height = contents.length >= 24 ? contents.readUInt32BE(20) : 0;
  if (contents.length === 0
    || contents.subarray(0, 8).toString("hex") !== pngSignature
    || width !== 384
    || height !== 144
  ) {
    console.error(`asset: invalid PNG ${relativePath}`);
    failed = true;
  } else {
    console.log(`asset: pass ${relativePath}`);
  }
}

const uiSource = fs.readFileSync(path.join(root, "src/KryptUI.lua"), "utf8");
const iconTable = uiSource.match(/local LucideAssets = \{([\s\S]*?)\n\}/)?.[1] ?? "";
const availableIcons = new Set(
  [...iconTable.matchAll(/\["([^"]+)"\]\s*=/g)].map((match) => match[1]),
);
const requiredIcons = new Set([
  "ban",
  "chevron-down",
  "chevron-right",
  "circle-check",
  "pause",
  "play",
  "unplug",
]);
for (const relativePath of expectedModules.slice(1)) {
  const source = fs.readFileSync(path.join(root, relativePath), "utf8");
  for (const match of source.matchAll(/\b(?:Icon|icon)\s*=\s*"([^"]+)"/g)) {
    requiredIcons.add(match[1]);
  }
}
for (const icon of requiredIcons) {
  if (!availableIcons.has(icon)) {
    console.error(`icon: missing Lucide mapping ${icon}`);
    failed = true;
  }
}

const consoleSource = fs.readFileSync(path.join(root, "src/features/Console.lua"), "utf8");
const remotesSource = fs.readFileSync(path.join(root, "src/features/Remotes.lua"), "utf8");
const explorerSource = fs.readFileSync(path.join(root, "src/features/Explorer.lua"), "utf8");
if (consoleSource.includes("UI.clear(output)") || remotesSource.includes("UI.clear(list)")) {
  console.error("performance: pooled high-frequency lists must not be fully rebuilt");
  failed = true;
}
if (remotesSource.includes("task.defer(capture")) {
  console.error("performance: high-frequency remote capture task regression");
  failed = true;
}
if (explorerSource.includes("expanded[root] = true")
  || explorerSource.includes('Text = "Refresh"')
  || !explorerSource.includes("rowPool")
  || !explorerSource.includes("CanvasPosition")
  || !explorerSource.includes("AUTO_UPDATE_DELAY")
  || explorerSource.includes("task.delay(AUTO_UPDATE_DELAY")
  || !explorerSource.includes("game.DescendantAdded")
  || !explorerSource.includes("game.DescendantRemoving")
  || !explorerSource.includes("CLASS_ICON_ASSET")
  || !explorerSource.includes("Loading Explorer")
) {
  console.error("explorer: collapsed, live, icon-backed virtual tree contract is incomplete");
  failed = true;
}
if ((uiSource.match(/UserInputService\.InputChanged/g) ?? []).length !== 1) {
  console.error("performance: window should have one global input-change handler");
  failed = true;
}
if (!uiSource.includes("function KryptUI.loader")
  || !uiSource.includes("ActiveLoaders")
  || !uiSource.includes("task.wait(0.08)")
) {
  console.error("loader: shared non-blocking loader contract is incomplete");
  failed = true;
}

const manifest = fs.readFileSync(path.join(root, "src/Manifest.lua"), "utf8");
for (const relativePath of expectedModules.slice(2)) {
  if (!manifest.includes(relativePath) && relativePath !== "src/Runtime.lua") {
    console.error(`manifest: missing dependency ${relativePath}`);
    failed = true;
  }
}

const runtimeSource = fs.readFileSync(path.join(root, "src/Runtime.lua"), "utf8");
const settingsSource = fs.readFileSync(path.join(root, "src/features/Settings.lua"), "utf8");
if (!runtimeSource.includes("identifyexecutor")
  || !runtimeSource.includes("getexecutorname")
  || !runtimeSource.includes("Watermark")
  || !uiSource.includes('pcall(os.date, "%H:%M:%S")')
) {
  console.error("watermark: executor identity or live clock contract is incomplete");
  failed = true;
}
if (!runtimeSource.includes('dump = "KryptDbg/DUMP"')
  || !runtimeSource.includes("readablePath")
  || !runtimeSource.includes("getFeatureController")
  || !settingsSource.includes("instances.jsonl")
  || !settingsSource.includes("scripts/index.jsonl")
  || !settingsSource.includes("scripts/links.jsonl")
  || !settingsSource.includes("interactions.jsonl")
  || !settingsSource.includes("remotes/calls.jsonl")
  || !settingsSource.includes("remotes/generated")
  || !settingsSource.includes("MAX_INSTANCES_WITH_APPEND")
  || !settingsSource.includes("dumpScriptSources")
  || !settingsSource.includes('executorFunction("getproperties")')
) {
  console.error("settings: bounded AI debug dump contract is incomplete");
  failed = true;
}
if (!remotesSource.includes("getDumpSnapshot")
  || !remotesSource.includes("maxLogs = 2500")
) {
  console.error("remotes: dump snapshot contract is incomplete");
  failed = true;
}
if (!uiSource.includes("clampPosition")
  || !uiSource.includes("if minimized then")
  || !uiSource.includes("self.subtitle.Visible = false")
) {
  console.error("window: compact drag and minimize contract is incomplete");
  failed = true;
}

const bootstrap = fs.readFileSync(path.join(root, "init.lua"), "utf8");
if (!bootstrap.includes("KryptDbgBaseUrl")
  || !bootstrap.includes("manifest.core")
  || !bootstrap.includes("fetch = fetch")
  || !bootstrap.includes("createBootstrapLoader")
  || !bootstrap.includes("bootstrapLoader:fail")
) {
  console.error("bootstrap: lazy loader contract is incomplete");
  failed = true;
}

if (failed) {
  process.exit(1);
}

console.log(`validated ${expectedModules.length} Lua modules`);
