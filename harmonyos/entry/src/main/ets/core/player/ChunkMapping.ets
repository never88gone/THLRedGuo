export class ChunkMapping {
  chunk: number = 0;
  samples: number = 0;

  constructor(chunk: number, samples: number) {
    this.chunk = chunk;
    this.samples = samples;
  }
}
