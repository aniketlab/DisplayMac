const { app, nativeImage } = require('electron');
const fs = require('fs');
const path = require('path');

app.disableHardwareAcceleration();

function buildIco(images) {
  const count = images.length;
  const headerSize = 6;
  const entrySize = 16;
  let offset = headerSize + (count * entrySize);

  const header = Buffer.alloc(headerSize);
  header.writeUInt16LE(0, 0);
  header.writeUInt16LE(1, 2);
  header.writeUInt16LE(count, 4);

  const entries = [];
  const datas = [];

  for (const img of images) {
    const entry = Buffer.alloc(entrySize);
    entry.writeUInt8(img.width >= 256 ? 0 : img.width, 0);
    entry.writeUInt8(img.height >= 256 ? 0 : img.height, 1);
    entry.writeUInt8(0, 2);
    entry.writeUInt8(0, 3);
    entry.writeUInt16LE(1, 4);
    entry.writeUInt16LE(32, 6);
    entry.writeUInt32LE(img.data.length, 8);
    entry.writeUInt32LE(offset, 12);

    entries.push(entry);
    datas.push(img.data);
    offset += img.data.length;
  }

  return Buffer.concat([header, ...entries, ...datas]);
}

app.whenReady().then(() => {
  const srcPath = path.resolve('assets/DisplayMac-Aurora-macOS-1024.png');
  const img = nativeImage.createFromPath(srcPath);

  const icoSizes = [16, 24, 32, 48, 64, 128, 256];
  const icoImages = [];

  for (const size of icoSizes) {
    const resized = img.resize({ width: size, height: size, quality: 'high' });
    icoImages.push({ width: size, height: size, data: resized.toPNG() });
  }

  const icoBuffer = buildIco(icoImages);
  fs.writeFileSync('assets/icon.ico', icoBuffer);
  fs.writeFileSync('assets/DisplayMac.ico', icoBuffer);
  
  const desktopIco = path.resolve(process.env.USERPROFILE || 'C:\\\\Users\\\\sharm', 'Desktop/DisplayMac.ico');
  fs.writeFileSync(desktopIco, icoBuffer);
  
  console.log('SUCCESS: Generated multi-resolution Windows ICO from DisplayMac-Aurora-macOS-1024.png');
  app.quit();
});
