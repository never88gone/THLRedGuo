export class CencRegion {
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
