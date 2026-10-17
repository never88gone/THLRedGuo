import assert from 'node:assert/strict';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import vm from 'node:vm';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const report = { startedAt: new Date().toISOString(), mode: 'live-metadata-and-head', checks: [], requests: [] };
const context = vm.createContext({
  Buffer,
  console,
  fetch: async (url, options = {}) => {
    const target = new URL(url);
    assert(!/\.(jpg|jpeg|png|webp|gif|avif)(?:$|\?)/i.test(target.href), '禁止请求站源图片');
    if (/\.(mp4|m3u8)(?:$|\?)/i.test(target.href)) assert.equal(options.method, 'HEAD');
    const row = { method: options.method || 'GET', endpoint: target.origin + target.pathname };
    report.requests.push(row);
    try {
      const response = await fetch(url, { ...options, signal: AbortSignal.timeout(12000) });
      row.status = response.status;
      row.contentType = response.headers.get('content-type');
      return response;
    } catch (error) {
      row.error = error.message;
      throw error;
    }
  },
});
vm.runInContext(await readFile(path.join(root, 'assets/sources/hongguo.js'), 'utf8'), context);
const spider = context.spider;

async function check(name, operation) {
  try {
    const details = await operation();
    report.checks.push({ name, passed: true, details });
    console.log(`PASS ${name}`);
    return details;
  } catch (error) {
    report.checks.push({ name, passed: false, error: error.message });
    console.log(`FAIL ${name}: ${error.message}`);
    return null;
  }
}

const samples = new Map();
await check('home', async () => {
  const home = await spider.home(false);
  assert.equal(home.class.length, 3);
  return home.class.map(item => item.type_id);
});
for (const category of ['real-drama', 'comic-drama', 'ai-drama']) {
  await check(`category:${category}`, async () => {
    const result = await spider.category(category, 1, false, {});
    assert(result.list.length > 0, '分类为空');
    const first = result.list[0];
    samples.set(first.vod_id, first);
    return { count: result.list.length, sample: { id: first.vod_id, title: first.vod_name } };
  });
}
for (const query of ['万妖图录', '战神', '重生']) {
  await check(`search:${query}`, async () => {
    const result = await spider.search(query, false, 1);
    assert(result.list.length > 0, '搜索为空');
    const first = result.list[0];
    samples.set(first.vod_id, first);
    return { count: result.list.length, sample: { id: first.vod_id, title: first.vod_name } };
  });
}
for (const drama of samples.values()) {
  const detail = await check(`detail:${drama.vod_id}`, async () => {
    const result = await spider.detail(drama.vod_id);
    const vod = result.list?.[0];
    assert(vod?.vod_play_url, '缺少分集');
    return { id: vod.vod_id, title: vod.vod_name, episodes: vod.vod_play_url.split('#') };
  });
  if (!detail) continue;
  const indices = [...new Set([0, Math.floor(detail.episodes.length / 2), detail.episodes.length - 1])];
  for (const index of indices) {
    await check(`play:${drama.vod_id}:${index + 1}`, async () => {
      const episode = detail.episodes[index];
      const target = episode.slice(episode.indexOf('$') + 1);
      const result = await spider.play('', target, []);
      assert(result.url, '未取得当前分集的播放地址');
      const response = await context.fetch(result.url, { method: 'HEAD', headers: result.header });
      assert([200, 206].includes(response.status), `媒体 HTTP ${response.status}`);
      assert(/^video\//i.test(response.headers.get('content-type') || ''), '媒体类型不是视频');
      return { status: response.status, contentType: response.headers.get('content-type'), length: response.headers.get('content-length'), quality: result.quality || 0 };
    });
  }
}
report.finishedAt = new Date().toISOString();
report.passed = report.checks.filter(check => check.passed).length;
report.failed = report.checks.length - report.passed;
const output = path.resolve(process.argv[2] || path.join(root, 'build/verification/hongguo-live.json'));
await mkdir(path.dirname(output), { recursive: true });
await writeFile(output, JSON.stringify(report, null, 2));
console.log(`${report.passed} passed, ${report.failed} failed; ${output}`);
process.exitCode = report.failed > 0 ? 1 : 0;
