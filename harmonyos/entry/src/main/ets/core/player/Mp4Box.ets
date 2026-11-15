export class Mp4Box {
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
