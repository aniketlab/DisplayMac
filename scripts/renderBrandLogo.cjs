const { app, BrowserWindow } = require('electron');
const fs = require('fs');
const path = require('path');

app.disableHardwareAcceleration();

app.whenReady().then(async () => {
  const win = new BrowserWindow({
    width: 710,
    height: 460,
    useContentSize: true,
    show: false,
    frame: false,
    transparent: true,
    webPreferences: { offscreen: true }
  });

  const svg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="155 300 710 460" width="710" height="460" fill="none">
<defs>
<clipPath id="mac"><rect x="192" y="325" width="540" height="340" rx="22"/></clipPath>
<clipPath id="tab"><rect x="519" y="497" width="316" height="206" rx="19"/></clipPath>
</defs>
<!-- Mac display -->
<rect x="174" y="317" width="576" height="373" rx="37" fill="#1b2250" fill-opacity=".07"/>
<rect x="171" y="324" width="582" height="376" rx="40" fill="#1b2250" fill-opacity=".07"/>
<rect x="168" y="331" width="588" height="379" rx="43" fill="#1b2250" fill-opacity=".07"/>
<rect x="165" y="338" width="594" height="382" rx="46" fill="#1b2250" fill-opacity=".07"/>
<rect x="177" y="310" width="570" height="370" rx="34" fill="#2a2a2e" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>
<rect x="180" y="313" width="564" height="364" rx="31" fill="#050506" />
<g clip-path="url(#mac)">
<rect x="192" y="325" width="643" height="378" rx="0" fill="#3b4de0" />
<circle cx="320" cy="430" r="210" fill="#ff6ab5" fill-opacity="0.9"/>
<circle cx="690" cy="660" r="240" fill="#5ad1ff" fill-opacity="0.85"/>
<circle cx="600" cy="360" r="130" fill="#ffb86b" fill-opacity="0.7"/>
</g>
<rect x="236" y="385" width="230" height="150" rx="14" fill="#fff" fill-opacity=".14" stroke="#fff" stroke-opacity=".3" stroke-width="2"/>
<!-- Tablet (in front) -->
<rect x="504" y="492" width="346" height="233" rx="33" fill="#1b2250" fill-opacity=".07"/>
<rect x="501" y="499" width="352" height="236" rx="36" fill="#1b2250" fill-opacity=".07"/>
<rect x="498" y="506" width="358" height="239" rx="39" fill="#1b2250" fill-opacity=".07"/>
<rect x="495" y="513" width="364" height="242" rx="42" fill="#1b2250" fill-opacity=".07"/>
<rect x="507" y="485" width="340" height="230" rx="30" fill="#2a2a2e" stroke="#fff" stroke-opacity=".5" stroke-width="2"/>
<rect x="510" y="488" width="334" height="224" rx="27" fill="#050506" />
<g clip-path="url(#tab)">
<rect x="192" y="325" width="643" height="378" rx="0" fill="#3b4de0" />
<circle cx="320" cy="430" r="210" fill="#ff6ab5" fill-opacity="0.9"/>
<circle cx="690" cy="660" r="240" fill="#5ad1ff" fill-opacity="0.85"/>
<circle cx="600" cy="360" r="130" fill="#ffb86b" fill-opacity="0.7"/>
</g>
<rect x="560" y="530" width="150" height="100" rx="14" fill="#fff" fill-opacity=".14" stroke="#fff" stroke-opacity=".3" stroke-width="2"/>
</svg>`;

  const html = '<!DOCTYPE html><html><body style="margin:0;padding:0;background:transparent;overflow:hidden;">' + svg + '</body></html>';
  const tempPath = path.resolve(__dirname, 'temp_logo.html');
  fs.writeFileSync(tempPath, html);
  await win.loadFile(tempPath);
  await new Promise(r => setTimeout(r, 600));

  const img = await win.webContents.capturePage({ x: 0, y: 0, width: 710, height: 460 });
  const png = img.toPNG();

  // Save to drawable folders
  const resDir = path.resolve(__dirname, '../android-client/app/src/main/res');
  const drawableDir = path.join(resDir, 'drawable');
  fs.writeFileSync(path.join(drawableDir, 'brand_logo.png'), png);
  fs.writeFileSync(path.resolve(__dirname, '../assets/brand_logo.png'), png);

  const desktop = path.resolve(process.env.USERPROFILE || 'C:\\Users\\sharm', 'Desktop/DisplayMac_Brand_Logo.png');
  fs.writeFileSync(desktop, png);

  try { fs.unlinkSync(tempPath); } catch {}
  console.log('SUCCESS: Rendered original logo without background box as transparent PNG!');
  app.quit();
});
