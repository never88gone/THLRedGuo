import http from '@ohos.net.http';
import fs from '@ohos.file.fs';
import common from '@ohos.app.ability.common';
import hilog from '@ohos.hilog';

const TAG = 'CencDecryptor';
const DOMAIN = 0x0000;

// AES-128 S-box
const SBOX: Uint8Array = new Uint8Array([
  0x63,0x7c,0x77,0x7b,0xf2,0x6b,0x6f,0xc5,0x30,0x01,0x67,0x2b,0xfe,0xd7,0xab,0x76,
  0xca,0x82,0xc9,0x7d,0xfa,0x59,0x47,0xf0,0xad,0xd4,0xa2,0xaf,0x9c,0xa4,0x72,0xc0,
  0xb7,0xfd,0x93,0x26,0x36,0x3f,0xf7,0xcc,0x34,0xa5,0xe5,0xf1,0x71,0xd8,0x31,0x15,
  0x04,0xc7,0x23,0xc3,0x18,0x96,0x05,0x9a,0x07,0x12,0x80,0xe2,0xeb,0x27,0xb2,0x75,
  0x09,0x83,0x2c,0x1a,0x1b,0x6e,0x5a,0xa0,0x52,0x3b,0xd6,0xb3,0x29,0xe3,0x2f,0x84,
  0x53,0xd1,0x00,0xed,0x20,0xfc,0xb1,0x5b,0x6a,0xcb,0xbe,0x39,0x4a,0x4c,0x58,0xcf,
  0xd0,0xef,0xaa,0xfb,0x43,0x4d,0x33,0x85,0x45,0xf9,0x02,0x7f,0x50,0x3c,0x9f,0xa8,
  0x51,0xa3,0x40,0x8f,0x92,0x9d,0x38,0xf5,0xbc,0xb6,0xda,0x21,0x10,0xff,0xf3,0xd2,
  0xcd,0x0c,0x13,0xec,0x5f,0x97,0x44,0x17,0xc4,0xa7,0x7e,0x3d,0x64,0x5d,0x19,0x73,
  0x60,0x81,0x4f,0xdc,0x22,0x2a,0x90,0x88,0x46,0xee,0xb8,0x14,0xde,0x5e,0x0b,0xdb,
  0xe0,0x32,0x3a,0x0a,0x49,0x06,0x24,0x5c,0xc2,0xd3,0xac,0x62,0x91,0x95,0xe4,0x79,
  0xe7,0xc8,0x37,0x6d,0x8d,0xd5,0x4e,0xa9,0x6c,0x56,0xf4,0xea,0x65,0x7a,0xae,0x08,
  0xba,0x78,0x25,0x2e,0x1c,0xa6,0xb4,0xc6,0xe8,0xdd,0x74,0x1f,0x4b,0xbd,0x8b,0x8a,
  0x70,0x3e,0xb5,0x66,0x48,0x03,0xf6,0x0e,0x61,0x35,0x57,0xb9,0x86,0xc1,0x1d,0x9e,
  0xe1,0xf8,0x98,0x11,0x69,0xd9,0x8e,0x94,0x9b,0x1e,0x87,0xe9,0xce,0x55,0x28,0xdf,
  0x8c,0xa1,0x89,0x0d,0xbf,0xe6,0x42,0x68,0x41,0x99,0x2d,0x0f,0xb0,0x54,0xbb,0x16
]);

const RCON: Uint32Array = new Uint32Array([
  0x01000000, 0x02000000, 0x04000000, 0x08000000, 0x10000000,
  0x20000000, 0x40000000, 0x80000000, 0x1b000000, 0x36000000
]);

function xtime(x: number): number {
  return ((x << 1) ^ (((x >> 7) & 1) * 0x1b)) & 0xff;
}

const T0: Uint32Array = new Uint32Array(256);
const T1: Uint32Array = new Uint32Array(256);
const T2: Uint32Array = new Uint32Array(256);
const T3: Uint32Array = new Uint32Array(256);

function initTables(): void {
  for (let i = 0; i < 256; i++) {
    const s = SBOX[i];
    const s2 = xtime(s);
    const s3 = s2 ^ s;
    T0[i] = ((s2 << 24) | (s << 16) | (s << 8) | s3) >>> 0;
    T1[i] = ((s3 << 24) | (s2 << 16) | (s << 8) | s) >>> 0;
    T2[i] = ((s << 24) | (s3 << 16) | (s2 << 8) | s) >>> 0;
    T3[i] = ((s << 24) | (s << 16) | (s3 << 8) | s2) >>> 0;
  }
}
initTables();

function subWord(w: number): number {
  return (SBOX[w >>> 24] << 24) | (SBOX[(w >>> 16) & 0xff] << 16) | (SBOX[(w >>> 8) & 0xff] << 8) | SBOX[w & 0xff];
}

function rotWord(w: number): number {
  return ((w << 8) | (w >>> 24)) >>> 0;
}

function expandKey(key: Uint8Array): Uint32Array {
  const w = new Uint32Array(44);
  for (let i = 0; i < 4; i++) {
    w[i] = (key[i * 4] << 24) | (key[i * 4 + 1] << 16) | (key[i * 4 + 2] << 8) | key[i * 4 + 3];
  }
  for (let i = 4; i < 44; i++) {
    let temp = w[i - 1];
    if (i % 4 === 0) {
      temp = (subWord(rotWord(temp)) ^ RCON[(i / 4) - 1]) >>> 0;
    }
    w[i] = (w[i - 4] ^ temp) >>> 0;
  }
  return w;
}

function fastAesEncryptBlock(
  b0: number,
  b1: number,
  b2: number,
  b3: number,
  rk: Uint32Array,
  outUint8: Uint8Array,
  outOff: number
): void {
  let s0 = (b0 ^ rk[0]) >>> 0;
  let s1 = (b1 ^ rk[1]) >>> 0;
  let s2 = (b2 ^ rk[2]) >>> 0;
  let s3 = (b3 ^ rk[3]) >>> 0;

  for (let r = 1; r < 10; r++) {
    const base = r * 4;
    const t0 = (T0[s0 >>> 24] ^ T1[(s1 >>> 16) & 0xff] ^ T2[(s2 >>> 8) & 0xff] ^ T3[s3 & 0xff] ^ rk[base]) >>> 0;
    const t1 = (T0[s1 >>> 24] ^ T1[(s2 >>> 16) & 0xff] ^ T2[(s3 >>> 8) & 0xff] ^ T3[s0 & 0xff] ^ rk[base + 1]) >>> 0;
    const t2 = (T0[s2 >>> 24] ^ T1[(s3 >>> 16) & 0xff] ^ T2[(s0 >>> 8) & 0xff] ^ T3[s1 & 0xff] ^ rk[base + 2]) >>> 0;
    const t3 = (T0[s3 >>> 24] ^ T1[(s0 >>> 16) & 0xff] ^ T2[(s1 >>> 8) & 0xff] ^ T3[s2 & 0xff] ^ rk[base + 3]) >>> 0;
    s0 = t0; s1 = t1; s2 = t2; s3 = t3;
  }

  const rk40 = rk[40];
  const rk41 = rk[41];
  const rk42 = rk[42];
  const rk43 = rk[43];
  const o0 = (((SBOX[s0 >>> 24] << 24) | (SBOX[(s1 >>> 16) & 0xff] << 16) | (SBOX[(s2 >>> 8) & 0xff] << 8) | SBOX[s3 & 0xff]) ^ rk40) >>> 0;
  const o1 = (((SBOX[s1 >>> 24] << 24) | (SBOX[(s2 >>> 16) & 0xff] << 16) | (SBOX[(s3 >>> 8) & 0xff] << 8) | SBOX[s0 & 0xff]) ^ rk41) >>> 0;
  const o2 = (((SBOX[s2 >>> 24] << 24) | (SBOX[(s3 >>> 16) & 0xff] << 16) | (SBOX[(s0 >>> 8) & 0xff] << 8) | SBOX[s1 & 0xff]) ^ rk42) >>> 0;
  const o3 = (((SBOX[s3 >>> 24] << 24) | (SBOX[(s0 >>> 16) & 0xff] << 16) | (SBOX[(s1 >>> 8) & 0xff] << 8) | SBOX[s2 & 0xff]) ^ rk43) >>> 0;

  outUint8[outOff] = (o0 >>> 24) & 0xff;
  outUint8[outOff + 1] = (o0 >>> 16) & 0xff;
  outUint8[outOff + 2] = (o0 >>> 8) & 0xff;
  outUint8[outOff + 3] = o0 & 0xff;

  outUint8[outOff + 4] = (o1 >>> 24) & 0xff;
  outUint8[outOff + 5] = (o1 >>> 16) & 0xff;
  outUint8[outOff + 6] = (o1 >>> 8) & 0xff;
  outUint8[outOff + 7] = o1 & 0xff;

  outUint8[outOff + 8] = (o2 >>> 24) & 0xff;
  outUint8[outOff + 9] = (o2 >>> 16) & 0xff;
  outUint8[outOff + 10] = (o2 >>> 8) & 0xff;
  outUint8[outOff + 11] = o2 & 0xff;

  outUint8[outOff + 12] = (o3 >>> 24) & 0xff;
  outUint8[outOff + 13] = (o3 >>> 16) & 0xff;
  outUint8[outOff + 14] = (o3 >>> 8) & 0xff;
  outUint8[outOff + 15] = o3 & 0xff;
}

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

class Mp4Box {
  type: string = '';
  start: number = 0;
  size: number = 0;
  header: number = 0;
  payload: number = 0;
  end: number = 0;

  constructor(type: string, start: number, size: number, header: number, payload: number, end: number) {
    this.type = type;
    this.start = start;
    this.size = size;
    this.header = header;
    this.payload = payload;
    this.end = end;
  }
}

class CencRegion {
  offset: number = 0;
  count: number = 0;
  iv: Uint8Array = new Uint8Array(16);
  cipherOffset: number = 0;

  constructor(offset: number, count: number, iv: Uint8Array, cipherOffset: number) {
    this.offset = offset;
    this.count = count;
    this.iv = iv;
    this.cipherOffset = cipherOffset;
  }
}

class ChunkMapping {
  chunk: number = 0;
  samples: number = 0;

  constructor(chunk: number, samples: number) {
    this.chunk = chunk;
    this.samples = samples;
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
    const roundKeys = expandKey(key);

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
      if (r > 0 && r % 1000 === 0) {
        await new Promise<void>((resolve) => setTimeout(resolve, 0));
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

      fastAesEncryptBlock(w0, w1, w2, w3, roundKeys, keystream, 0);
      let ksIdx = reg.cipherOffset % 16;
      const end = reg.offset + reg.count;

      for (let pos = reg.offset; pos < end; pos++) {
        if (ksIdx === 16) {
          w3 = (w3 + 1) >>> 0;
          if (w3 === 0) {
            w2 = (w2 + 1) >>> 0;
          }
          fastAesEncryptBlock(w0, w1, w2, w3, roundKeys, keystream, 0);
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
