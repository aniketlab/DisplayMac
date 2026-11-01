const { app, BrowserWindow } = require('electron');
const fs = require('fs');
const path = require('path');

app.disableHardwareAcceleration();

const ASSETS_DIR = path.resolve(__dirname, '../assets/logo');
const ROOT_ASSETS_DIR = path.resolve(__dirname, '../assets');
const DESKTOP_DIR = path.resolve(process.env.USERPROFILE || 'C:\\Users\\sharm', 'Desktop/DisplayMac_Branding_Kit');

if (!fs.existsSync(ASSETS_DIR)) fs.mkdirSync(ASSETS_DIR, { recursive: true });
if (!fs.existsSync(ROOT_ASSETS_DIR)) fs.mkdirSync(ROOT_ASSETS_DIR, { recursive: true });
if (!fs.existsSync(DESKTOP_DIR)) fs.mkdirSync(DESKTOP_DIR, { recursive: true });

function buildIco(images) {
  const count = images.length;
  const headerSize = 6;
  const entrySize = 16;
  let offset = headerSize + (count * entrySize);

  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0); // reserved
  header.writeUInt16LE(1, 2); // type 1 = icon
  header.writeUInt16LE(count, 4); // number of images

  const entries = [];
  const datas = [];

  for (const img of images) {
    const entry = Buffer.alloc(entrySize);
    entry.writeUInt8(img.width >= 256 ? 0 : img.width, 0);
    entry.writeUInt8(img.height >= 256 ? 0 : img.height, 1);
    entry.writeUInt8(0, 2); // color count
    entry.writeUInt8(0, 3); // reserved
    entry.writeUInt16LE(1, 4); // planes
    entry.writeUInt16LE(32, 6); // bpp
    entry.writeUInt32LE(img.data.length, 8); // size
    entry.writeUInt32LE(offset, 12); // offset

    entries.push(entry);
    datas.push(img.data);
    offset += img.data.length;
  }

  return Buffer.concat([header, ...entries, ...datas]);
}

app.whenReady().then(async () => {
  let win = null;
  const tempHtmlPath = path.join(__dirname, 'temp_render.html');

  try {
    console.log('Generating Production-Level DisplayMac Logo Assets & Multi-Res Windows ICO...');

    win = new BrowserWindow({
      width: 2400,
      height: 750,
      useContentSize: true,
      show: false,
      frame: false,
      transparent: true,
      webPreferences: {
        offscreen: true
      }
    });

    // Vector graphic: Mac Desktop Monitor on left, Ultra-thin Tablet on right, 120Hz high-speed lightning bridge
    const iconSvgContent = `
      <rect x="2.5" y="4.5" width="16" height="12" rx="2" />
      <line x1="10.5" y1="16.5" x2="10.5" y2="21.5" />
      <line x1="6.5" y1="21.5" x2="14.5" y2="21.5" />
      <rect x="18" y="8" width="11.5" height="15" rx="2" />
      <circle cx="23.75" cy="20.5" r="0.65" fill="currentColor" stroke="none" />
      <path d="M15.5 5.5 L11.5 12.5 L15.5 12.5 L13.5 19 L19.5 11 L15.5 11 Z" fill="#00D2FF" stroke="#007AFF" stroke-width="0.8" stroke-linejoin="round" />
    `;

    const iconSquircleSvg = `
      <rect x="2.5" y="4.5" width="16" height="12" rx="2" />
      <line x1="10.5" y1="16.5" x2="10.5" y2="21.5" />
      <line x1="6.5" y1="21.5" x2="14.5" y2="21.5" />
      <rect x="18" y="8" width="11.5" height="15" rx="2" />
      <circle cx="23.75" cy="20.5" r="0.65" fill="#FFFFFF" stroke="none" />
      <path d="M15.5 5.5 L11.5 12.5 L15.5 12.5 L13.5 19 L19.5 11 L15.5 11 Z" fill="#38BDF8" stroke="#FFFFFF" stroke-width="0.8" stroke-linejoin="round" />
    `;

    const tasks = [
      {
        name: 'displaymac_logo_full.png',
        width: 2400,
        height: 600,
        html: `<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 2400px;
      height: 600px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: transparent;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    .container {
      display: flex;
      align-items: center;
      gap: 55px;
    }
    .icon {
      width: 330px;
      height: 330px;
      color: #007AFF;
    }
    .brand-text {
      font-size: 200px;
      font-weight: 850;
      letter-spacing: -2px;
      line-height: 1;
      text-transform: uppercase;
    }
    .blue { color: #007AFF; }
    .dark { color: #0f172a; margin-left: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <svg class="icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      ${iconSvgContent}
    </svg>
    <div class="brand-text">
      <span class="blue">DISPLAY</span><span class="dark">MAC</span>
    </div>
  </div>
</body>
</html>`
      },
      {
        name: 'displaymac_logo_with_tagline.png',
        width: 2400,
        height: 750,
        html: `<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 2400px;
      height: 750px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: transparent;
      font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    }
    .container {
      display: flex;
      align-items: center;
      gap: 60px;
    }
    .icon {
      width: 360px;
      height: 360px;
      color: #007AFF;
    }
    .text-col {
      display: flex;
      flex-direction: column;
      gap: 18px;
    }
    .brand-text {
      font-size: 200px;
      font-weight: 850;
      letter-spacing: -2px;
      line-height: 1;
      text-transform: uppercase;
    }
    .tagline {
      font-size: 54px;
      font-weight: 500;
      color: #64748b;
      letter-spacing: 0.5px;
    }
    .blue { color: #007AFF; }
    .dark { color: #0f172a; margin-left: 20px; }
  </style>
</head>
<body>
  <div class="container">
    <svg class="icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      ${iconSvgContent}
    </svg>
    <div class="text-col">
      <div class="brand-text">
        <span class="blue">DISPLAY</span><span class="dark">MAC</span>
      </div>
      <div class="tagline">Ultra-Low-Latency 120Hz Display for macOS</div>
    </div>
  </div>
</body>
</html>`
      },
      {
        name: 'displaymac_icon_1024.png',
        width: 1024,
        height: 1024,
        html: `<!DOCTYPE html>
<html>
<head>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      width: 1024px;
      height: 1024px;
      display: flex;
      align-items: center;
      justify-content: center;
      background: transparent;
    }
    .icon {
      width: 800px;
      height: 800px;
      color: #007AFF;
    }
  </style>
</head>
<body>
  <svg class="icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
    ${iconSvgContent}
  </svg>
</body>
</html>`
      },
      {
        name: 'displaymac_app_icon_squircle.png',
        width: 1024,
        height: 1024,
        html: `<!DOCTYPE html>
<html>
<head>
  <style>
    html, body {
      margin: 0;
      padding: 0;
      width: 1024px;
      height: 1024px;
      overflow: hidden;
      display: flex;
      align-items: center;
      justify-content: center;
      background: transparent;
    }
    .squircle {
      width: 840px;
      height: 840px;
      border-radius: 195px;
      background: linear-gradient(135deg, #0A84FF 0%, #0056D2 100%);
      box-shadow: 0 35px 80px rgba(0, 86, 210, 0.45);
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .icon {
      width: 530px;
      height: 530px;
      color: #ffffff;
    }
  </style>
</head>
<body>
  <div class="squircle">
    <svg class="icon" viewBox="0 0 32 32" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      ${iconSquircleSvg}
    </svg>
  </div>
</body>
</html>`
      }
    ];

    let squircleImage = null;

    for (const task of tasks) {
      win.setSize(task.width, task.height);
      fs.writeFileSync(tempHtmlPath, task.html, 'utf8');
      await win.loadFile(tempHtmlPath);
      await new Promise(r => setTimeout(r, 600));

      const img = await win.webContents.capturePage({ x: 0, y: 0, width: task.width, height: task.height });
      const buf = img.toPNG();

      fs.writeFileSync(path.join(ASSETS_DIR, task.name), buf);
      fs.writeFileSync(path.join(DESKTOP_DIR, task.name), buf);
      console.log(`Saved: ${task.name} (${task.width}x${task.height})`);

      if (task.name === 'displaymac_app_icon_squircle.png') {
        squircleImage = img;
        // Also save as primary app icon in assets/
        fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'icon.png'), buf);
        fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'icon-512.png'), img.resize({ width: 512, height: 512, quality: 'high' }).toPNG());
        fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'icon-256.png'), img.resize({ width: 256, height: 256, quality: 'high' }).toPNG());
      }
      if (task.name === 'displaymac_logo_with_tagline.png') {
        fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'logo.png'), buf);
      }
    }

    // Save Vector SVGs
    const logoSvgContent = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 880 220" fill="none">
  <g transform="translate(30, 35)">
    <svg width="150" height="150" viewBox="0 0 32 32" fill="none" stroke="#007AFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
      ${iconSvgContent}
    </svg>
  </g>
  <text x="210" y="145" font-family="-apple-system, BlinkMacSystemFont, Segoe UI, Roboto, Helvetica, Arial, sans-serif" font-size="95" font-weight="850" letter-spacing="-1">
    <tspan fill="#007AFF">DISPLAY</tspan>
    <tspan fill="#0f172a" dx="20">MAC</tspan>
  </text>
</svg>`;

    const iconOnlySvg = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 32 32" fill="none" stroke="#007AFF" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
  ${iconSvgContent}
</svg>`;

    fs.writeFileSync(path.join(ASSETS_DIR, 'displaymac_logo.svg'), logoSvgContent, 'utf8');
    fs.writeFileSync(path.join(ASSETS_DIR, 'displaymac_icon.svg'), iconOnlySvg, 'utf8');
    fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'logo.svg'), logoSvgContent, 'utf8');
    fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'icon.svg'), iconOnlySvg, 'utf8');
    fs.writeFileSync(path.join(DESKTOP_DIR, 'displaymac_logo.svg'), logoSvgContent, 'utf8');
    fs.writeFileSync(path.join(DESKTOP_DIR, 'displaymac_icon.svg'), iconOnlySvg, 'utf8');
    console.log('Saved vector SVGs: displaymac_logo.svg, displaymac_icon.svg');

    // Generate multi-resolution Windows ICO (16, 24, 32, 48, 64, 128, 256)
    if (squircleImage) {
      const icoSizes = [16, 24, 32, 48, 64, 128, 256];
      const icoImages = [];

      for (const size of icoSizes) {
        const resized = squircleImage.resize({ width: size, height: size, quality: 'high' });
        icoImages.push({ width: size, height: size, data: resized.toPNG() });
      }

      const icoBuffer = buildIco(icoImages);
      fs.writeFileSync(path.join(ASSETS_DIR, 'icon.ico'), icoBuffer);
      fs.writeFileSync(path.join(ROOT_ASSETS_DIR, 'icon.ico'), icoBuffer);
      fs.writeFileSync(path.join(DESKTOP_DIR, 'icon.ico'), icoBuffer);
      console.log('Saved multi-resolution icon.ico (16, 24, 32, 48, 64, 128, 256)');
    }

    try { fs.unlinkSync(tempHtmlPath); } catch {}
    console.log('DisplayMac Production Brand Assets generated successfully!');
  } catch (err) {
    console.error('Error generating assets:', err);
  } finally {
    if (win) win.destroy();
    app.quit();
  }
});
