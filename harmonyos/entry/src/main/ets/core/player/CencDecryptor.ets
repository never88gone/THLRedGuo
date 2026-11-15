import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';
import { Mp4Box } from './Mp4Box';
import { CencRegion } from './CencRegion';
import { ChunkMapping } from './ChunkMapping';
import { AesCipher } from './AesCipher';

const TAG = 'CencDecryptor';
const DOMAIN = 0x0000;

function read32(data: Uint8Array, offset: number): number {
  return ((data[offset] << 24) | (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3]) >>> 0;
}

function read16(data: Uint8Array, offset: number): number {
  return (data[offset] << 8) | data[offset + 1];
}

function fourCC(data: Uint8Array, offset: number): string {
  let s = '';
  for (let i = 0; i < 4; i++) {
    s += String.fromCharCode(data[offset + i]);
  }
  return s;
}

function writeFourCC(data: Uint8Array, offset: number, cc: string): void {
  for (let i = 0; i < 4; i++) {
    data[offset + i] = cc.charCodeAt(i);
  }
}

function parseBoxes(data: Uint8Array, start: number, end: number): Mp4Box[] {
  const result: Mp4Box[] = [];
  let cursor = start;
  while (cursor < end) {
    if (cursor + 8 > end) break;
    const rawSize = read32(data, cursor);
    const header = rawSize === 1 ? 16 : 8;
    if (cursor + header > end) break;
    const size = rawSize === 1 ? read32(data, cursor + 12) : rawSize === 0 ? end - cursor : rawSize;
    if (size < header || cursor + size > end) break;
    const type = fourCC(data, cursor + 4);
    result.push(new Mp4Box(type, cursor, size, header, cursor + header, cursor + size));
    cursor += size;
  }
  return result;
}

function findBox(data: Uint8Array, parent: Mp4Box, type: string): Mp4Box | null {
  const boxes = parseBoxes(data, parent.payload, parent.end);
  for (let i = 0; i < boxes.length; i++) {
    if (boxes[i].type === type) return boxes[i];
  }
  return null;
}

export class CencDecryptor {
  /**
   * 解密内存中的 MP4 字节缓冲区 (CENC AES-128-CTR 原地解密)
   */
  public static async decryptBuffer(data: Uint8Array, keyHex: string): Promise<boolean> {
    if (!keyHex || keyHex.length !== 32) return false;
    const key = new Uint8Array(16);
    for (let i = 0; i < 16; i++) {
      key[i] = parseInt(keyHex.substring(i * 2, i * 2 + 2), 16);
    }
    const roundKeys = AesCipher.expandKey(key);

    const roots = parseBoxes(data, 0, data.length);
    let moov: Mp4Box | null = null;
    for (let i = 0; i < roots.length; i++) {
      if (roots[i].type === 'moov') {
        moov = roots[i];
        break;
      }
    }
    if (!moov) return false;

    const moovBoxes = parseBoxes(data, moov.payload, moov.end);
    const regions: CencRegion[] = [];

    for (let t = 0; t < moovBoxes.length; t++) {
      const track = moovBoxes[t];
      if (track.type !== 'trak') continue;

      const mdia = findBox(data, track, 'mdia');
      if (!mdia) continue;
      const minf = findBox(data, mdia, 'minf');
      if (!minf) continue;
      const stbl = findBox(data, minf, 'stbl');
      if (!stbl) continue;

      const stblBoxes = parseBoxes(data, stbl.payload, stbl.end);
      let stsd: Mp4Box | null = null;
      let stsz: Mp4Box | null = null;
      let stsc: Mp4Box | null = null;
      let offsetsBox: Mp4Box | null = null;
      let senc: Mp4Box | null = null;

      for (let i = 0; i < stblBoxes.length; i++) {
        const b = stblBoxes[i];
        if (b.type === 'stsd') stsd = b;
        else if (b.type === 'stsz') stsz = b;
        else if (b.type === 'stsc') stsc = b;
        else if (b.type === 'stco' || b.type === 'co64') offsetsBox = b;
        else if (b.type === 'senc') senc = b;
      }

      if (!stsd) continue;
      const descriptions = parseBoxes(data, stsd.payload + 8, stsd.end);
      if (descriptions.length === 0) continue;
      const entry = descriptions[0];
      if (entry.type !== 'encv' && entry.type !== 'enca') continue;

      const start = entry.start + (entry.type === 'encv' ? 86 : 36);
      const extensions = parseBoxes(data, start, entry.end);
      let sinf: Mp4Box | null = null;
      for (let i = 0; i < extensions.length; i++) {
        if (extensions[i].type === 'sinf') { sinf = extensions[i]; break; }
      }
      if (!sinf) continue;
      const frma = findBox(data, sinf, 'frma');
      if (!frma) continue;

      // 从 tenc (sinf -> schi -> tenc) 获取 default_Per_Sample_IV_Size (标准为 8 或 16 字节)
      let ivSize = 8;
      const schi = findBox(data, sinf, 'schi');
      if (schi) {
        const tenc = findBox(data, schi, 'tenc');
        if (tenc && tenc.payload + 7 < tenc.end) {
          ivSize = data[tenc.payload + 7];
          hilog.info(DOMAIN, TAG, 'Track %{public}d default_Per_Sample_IV_Size: %{public}d', t, ivSize);
        }
      }

      // 将 encv / enca 还原为原编码 (avc1 / hvc1)
      const origCodec = fourCC(data, frma.payload);
      writeFourCC(data, entry.start + 4, origCodec);
      // 清理 sinf
      writeFourCC(data, sinf.start + 4, 'free');

      if (!stsz || !stsc || !offsetsBox || !senc) continue;

      const uniform = read32(data, stsz.payload + 4);
      const sampleCount = read32(data, stsz.payload + 8);
      const sampleSizes: number[] = [];
      for (let i = 0; i < sampleCount; i++) {
        sampleSizes.push(uniform > 0 ? uniform : read32(data, stsz.payload + 12 + i * 4));
      }

      const mappingCount = read32(data, stsc.payload + 4);
      const mappings: ChunkMapping[] = [];
      for (let i = 0; i < mappingCount; i++) {
        const p = stsc.payload + 8 + i * 12;
        mappings.push(new ChunkMapping(read32(data, p), read32(data, p + 4)));
      }

      const is64 = offsetsBox.type === 'co64';
      const width = is64 ? 8 : 4;
      const chunks = read32(data, offsetsBox.payload + 4);
      const sampleOffsets: number[] = [];
      let mapIndex = 0;
      for (let chunk = 1; chunk <= chunks; chunk++) {
        while (mapIndex + 1 < mappings.length && mappings[mapIndex + 1].chunk <= chunk) {
          mapIndex++;
        }
        const p = offsetsBox.payload + 8 + (chunk - 1) * width;
        let offset = is64 ? read32(data, p + 4) : read32(data, p);
        for (let s = 0; s < mappings[mapIndex].samples; s++) {
          if (sampleOffsets.length >= sampleCount) break;
          sampleOffsets.push(offset);
          offset += sampleSizes[sampleOffsets.length - 1];
        }
      }

      const sencFlags = read32(data, senc.payload) & 0x00ffffff;
      let cursor = senc.payload + 4;
      if (sencFlags & 1) {
        cursor += 20;
      }
      cursor += 4; // skip sencCount

      for (let s = 0; s < sampleCount; s++) {
        const iv = new Uint8Array(16);
        for (let b = 0; b < ivSize && b < 16; b++) {
          iv[b] = data[cursor + b];
        }
        cursor += ivSize;

        if ((sencFlags & 2) === 0) {
          regions.push(new CencRegion(sampleOffsets[s], sampleSizes[s], iv, 0));
          continue;
        }

        const subsamples = read16(data, cursor);
        cursor += 2;
        let total = 0;
        let cipher = 0;
        for (let sub = 0; sub < subsamples; sub++) {
          const clear = read16(data, cursor);
          const encrypted = read32(data, cursor + 2);
          cursor += 6;
          total += clear;
          if (encrypted > 0) {
            regions.push(new CencRegion(sampleOffsets[s] + total, encrypted, iv, cipher));
            total += encrypted;
            cipher += encrypted;
          }
        }
      }

      // 将 senc, saio, saiz 标记为 free
      for (let i = 0; i < stblBoxes.length; i++) {
        const b = stblBoxes[i];
        if (b.type === 'senc' || b.type === 'saio' || b.type === 'saiz') {
          writeFourCC(data, b.start + 4, 'free');
        }
      }
    }

    hilog.info(DOMAIN, TAG, 'CENC decrypting %{public}d regions...', regions.length);
    const t0 = Date.now();

    // 原地 CTR 解密 (Zero-allocation 32-bit register T-table AES)
    const keystream = new Uint8Array(16);

    for (let r = 0; r < regions.length; r++) {
      if (r > 0 && r % 50 === 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 1));
      }
      const reg = regions[r];
      let w0 = read32(reg.iv, 0);
      let w1 = read32(reg.iv, 4);
      let w2 = read32(reg.iv, 8);
      let w3 = read32(reg.iv, 12);

      const blk = Math.floor(reg.cipherOffset / 16);
      if (blk > 0) {
        const sum3 = (w3 >>> 0) + (blk >>> 0);
        w3 = sum3 >>> 0;
        if (sum3 > 0xffffffff) {
          w2 = (w2 + 1) >>> 0;
        }
      }

      AesCipher.fastAesEncryptBlock(w0, w1, w2, w3, roundKeys, keystream, 0);
      let ksIdx = reg.cipherOffset % 16;
      const end = reg.offset + reg.count;

      for (let pos = reg.offset; pos < end; pos++) {
        if (ksIdx === 16) {
          w3 = (w3 + 1) >>> 0;
          if (w3 === 0) {
            w2 = (w2 + 1) >>> 0;
          }
          AesCipher.fastAesEncryptBlock(w0, w1, w2, w3, roundKeys, keystream, 0);
          ksIdx = 0;
        }
        data[pos] ^= keystream[ksIdx++];
      }
    }

    hilog.info(DOMAIN, TAG, 'CENC decrypted in %{public}d ms', Date.now() - t0);
    return true;
  }

  /**
   * 确保剧集视频在本地缓存中就绪并解密，返回本地文件路径
   */
  public static async prepareLocalMedia(
    context: common.UIAbilityContext,
    dramaId: string,
    episodeIndex: number,
    url: string,
    headers?: Record<string, string>,
    decryptionKey?: string
  ): Promise<string> {
    const cacheDir = context.cacheDir;
    const episodesDir = `${cacheDir}/episodes`;
    try {
      if (!fs.accessSync(episodesDir)) {
        fs.mkdirSync(episodesDir);
      }
    } catch (_) {}

    const cleanDramaId = dramaId.replace(/[^a-zA-Z0-9_]/g, '_');
    const targetPath = `${episodesDir}/${cleanDramaId}_${episodeIndex}.mp4`;

    // 检查缓存
    try {
      if (fs.accessSync(targetPath)) {
        const stat = fs.statSync(targetPath);
        if (stat.size > 1024 * 50) {
          hilog.info(DOMAIN, TAG, 'Cache hit for %{public}s, size: %{public}d', targetPath, stat.size);
          return targetPath;
        }
      }
    } catch (_) {}

    hilog.info(DOMAIN, TAG, 'Downloading media from network: %{public}s', url.slice(0, 80));
    const httpRequest = http.createHttp();
    const reqHeaders: Record<string, string> = {};
    reqHeaders['User-Agent'] = 'com.phoenix.read/71332';
    if (headers) {
      const keys = Object.keys(headers);
      for (let i = 0; i < keys.length; i++) {
        const k = keys[i];
        reqHeaders[k] = headers[k];
      }
    }

    const resp = await httpRequest.request(url, {
      method: http.RequestMethod.GET,
      header: reqHeaders,
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      readTimeout: 30000,
      connectTimeout: 15000
    });

    if (resp.responseCode !== 200 || !(resp.result instanceof ArrayBuffer)) {
      throw new Error(`Failed to download video, status=${resp.responseCode}`);
    }

    const arrayBuf = resp.result as ArrayBuffer;
    const data = new Uint8Array(arrayBuf);
    hilog.info(DOMAIN, TAG, 'Downloaded video bytes: %{public}d', data.length);

    if (decryptionKey) {
      hilog.info(DOMAIN, TAG, 'Decrypting video with key: %{public}s', decryptionKey);
      await CencDecryptor.decryptBuffer(data, decryptionKey);
    }

    // 写入本地缓存文件
    const file = fs.openSync(targetPath, fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE);
    fs.writeSync(file.fd, arrayBuf);
    fs.closeSync(file);
    hilog.info(DOMAIN, TAG, 'Media saved and ready: %{public}s', targetPath);

    return targetPath;
  }
}
