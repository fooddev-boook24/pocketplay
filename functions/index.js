const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const axios = require('axios');
const xml2js = require('xml2js');

admin.initializeApp();
const db = admin.firestore();

// BGGトークンはFirebase Secret Managerで管理
// デプロイ前に: firebase functions:secrets:set BGG_APP_TOKEN
const bggToken = defineSecret('BGG_APP_TOKEN');

const BGG_API = 'https://boardgamegeek.com/xmlapi2/thing';
const BATCH_SIZE = 20;
const BATCH_DELAY_MS = 1000;

// ─── ゲームIDリスト（FlutterアプリのkSeedGamesと同期）───────────────────────
const GAME_BGG_IDS = [
  { id: 'mysterium',    bggId: 181304 },
  { id: 'gloomhaven',   bggId: 174430 },
  { id: 'wingspan',     bggId: 266192 },
  { id: 'catan',        bggId: 13 },
  { id: 'arkham',       bggId: 257499 },
  { id: 'terraforming', bggId: 167791 },
  { id: '7wonders',     bggId: 68448 },
  { id: 'pandemic',     bggId: 30549 },
  { id: 'azul',         bggId: 230802 },
  { id: 'codenames',    bggId: 178900 },
  { id: 'dominion',     bggId: 36218 },
  { id: 'ticket_ride',  bggId: 9209 },
  { id: 'terraforming', bggId: 167791 },
  { id: 'concordia',    bggId: 124361 },
  { id: 'viticulture',  bggId: 128621 },
  { id: 'agricola',     bggId: 31260 },
  { id: 'kingdomino',   bggId: 204583 },
  { id: 'carcassonne',  bggId: 822 },
  { id: 'patchwork',    bggId: 163412 },
  { id: 'jaipur',       bggId: 54043 },
  { id: 'lost_cities',  bggId: 50 },
  { id: 'hive',         bggId: 2655 },
  { id: 'splendor',     bggId: 148228 },
  { id: 'dixit',        bggId: 39856 },
  { id: 'sushi_go',     bggId: 133473 },
  { id: 'skull',        bggId: 92415 },
  { id: 'coup',         bggId: 131357 },
  { id: 'hanabi',       bggId: 98778 },
  { id: 'no_thanks',    bggId: 12942 },
  { id: 'bohnanza',     bggId: 11 },
  { id: 'love_letter',  bggId: 129622 },
];

// ─── BGGからゲームデータを取得 ──────────────────────────────────────────────
async function fetchBggBatch(bggIds, token) {
  const ids = bggIds.join(',');
  const url = `${BGG_API}?id=${ids}&type=boardgame&stats=1`;

  let response = await axios.get(url, {
    headers: {
      'Authorization': `Bearer ${token}`,
      'User-Agent': 'PocketPlay/1.0 (board game discovery app)',
      'Accept': 'application/xml,text/xml,*/*',
    },
    timeout: 30000,
  });

  // 202 = BGGが処理中 → 4秒待ってリトライ
  if (response.status === 202) {
    await new Promise(r => setTimeout(r, 4000));
    response = await axios.get(url, {
      headers: { 'Authorization': `Bearer ${token}` },
      timeout: 30000,
    });
  }

  if (response.status !== 200) {
    throw new Error(`BGG API error: ${response.status}`);
  }

  return response.data;
}

// ─── XMLパース ──────────────────────────────────────────────────────────────
async function parseBggXml(xml) {
  const parser = new xml2js.Parser({ explicitArray: true });
  const result = await parser.parseStringPromise(xml);
  const items = result?.items?.item || [];

  return items.map(item => {
    const id = item.$.id;
    const image = item.image?.[0]?.trim();
    const thumbnail = item.thumbnail?.[0]?.trim();

    // プライマリ名（英語）
    const names = item.name || [];
    const primaryName = names.find(n => n.$.type === 'primary')?.$.value || '';

    // 統計
    const stats = item.statistics?.[0]?.ratings?.[0];
    const rating = parseFloat(stats?.average?.[0]?.$.value || '0');
    const complexity = parseFloat(stats?.averageweight?.[0]?.$.value || '0');

    // プレイ人数・時間
    const minPlayers = parseInt(item.minplayers?.[0]?.$.value || '0');
    const maxPlayers = parseInt(item.maxplayers?.[0]?.$.value || '0');
    const minTime = parseInt(item.minplaytime?.[0]?.$.value || '0');
    const maxTime = parseInt(item.maxplaytime?.[0]?.$.value || '0');
    const playTime = maxTime || minTime;

    // カテゴリ・メカニクス
    const links = item.link || [];
    const categories = links
      .filter(l => l.$.type === 'boardgamecategory')
      .map(l => l.$.value);
    const mechanics = links
      .filter(l => l.$.type === 'boardgamemechanic')
      .map(l => l.$.value);
    const designers = links
      .filter(l => l.$.type === 'boardgamedesigner')
      .map(l => l.$.value)
      .filter(d => d !== '(Uncredited)');

    // 説明文（HTMLエンティティをデコード）
    let description = item.description?.[0] || '';
    description = description
      .replace(/&#10;/g, '\n')
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#039;/g, "'")
      .trim();

    return {
      bggId: parseInt(id),
      image: image?.startsWith('//') ? `https:${image}` : image,
      thumbnail: thumbnail?.startsWith('//') ? `https:${thumbnail}` : thumbnail,
      titleEn: primaryName,
      minPlayers,
      maxPlayers,
      playTimeMinutes: playTime,
      bggRating: Math.round(rating * 10) / 10,
      complexity: Math.round(complexity * 10) / 10,
      categories,
      mechanics,
      designers,
      description,
    };
  });
}

// ─── Firestoreに保存（既存データとマージ）──────────────────────────────────
async function saveToFirestore(gameId, bggData) {
  const ref = db.collection('games').doc(gameId);
  const existing = await ref.get();

  const update = {
    lastFetched: admin.firestore.FieldValue.serverTimestamp(),
  };

  // imageUrlは既存データを上書きしない（楽天画像が入っている可能性）
  if (bggData.image) update.imageUrl = bggData.image;
  if (bggData.thumbnail) update.thumbnailUrl = bggData.thumbnail;
  if (bggData.minPlayers) update.minPlayers = bggData.minPlayers;
  if (bggData.maxPlayers) update.maxPlayers = bggData.maxPlayers;
  if (bggData.playTimeMinutes) update.playTimeMinutes = bggData.playTimeMinutes;
  if (bggData.bggRating) update.bggRating = bggData.bggRating;
  if (bggData.complexity) update.complexity = bggData.complexity;
  if (bggData.categories?.length) update.categories = bggData.categories;
  if (bggData.mechanics?.length) update.mechanics = bggData.mechanics;
  if (bggData.designers?.length) update.designers = bggData.designers;
  // 説明文は英語のみ → 既存の日本語説明を上書きしない
  if (bggData.description && !existing.data()?.description) {
    update.description = bggData.description;
  }

  await ref.set(update, { merge: true });
}

// ─── メイン処理 ──────────────────────────────────────────────────────────────
async function runPipeline(token) {
  const unique = [...new Map(GAME_BGG_IDS.map(g => [g.bggId, g])).values()];
  console.log(`Processing ${unique.length} games...`);

  let success = 0;
  let failed = 0;

  for (let i = 0; i < unique.length; i += BATCH_SIZE) {
    const batch = unique.slice(i, i + BATCH_SIZE);
    const bggIds = batch.map(g => g.bggId);

    try {
      const xml = await fetchBggBatch(bggIds, token);
      const parsed = await parseBggXml(xml);

      for (const data of parsed) {
        const game = batch.find(g => g.bggId === data.bggId);
        if (!game) continue;
        await saveToFirestore(game.id, data);
        console.log(`✓ ${game.id}: image=${!!data.image} rating=${data.bggRating}`);
        success++;
      }
    } catch (err) {
      console.error(`Batch error: ${err.message}`);
      failed += batch.length;
    }

    if (i + BATCH_SIZE < unique.length) {
      await new Promise(r => setTimeout(r, BATCH_DELAY_MS));
    }
  }

  console.log(`Done: ${success} success, ${failed} failed`);
  return { success, failed };
}

// ─── Scheduled Function（毎日午前3時 JST）───────────────────────────────────
exports.dailyBggSync = onSchedule(
  {
    schedule: '0 18 * * *', // UTC 18:00 = JST 03:00
    timeZone: 'Asia/Tokyo',
    secrets: [bggToken],
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async () => {
    console.log('Starting daily BGG sync...');
    const token = bggToken.value();
    if (!token) {
      console.error('BGG_APP_TOKEN secret not set');
      return;
    }
    await runPipeline(token);
  }
);

// ─── HTTP Function（手動トリガー・デバッグ用）────────────────────────────────
exports.manualBggSync = onRequest(
  {
    secrets: [bggToken],
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async (req, res) => {
    // 簡易認証（本番では Firebase Auth に変更すること）
    const key = req.headers['x-admin-key'];
    if (key !== process.env.ADMIN_KEY) {
      res.status(403).send('Forbidden');
      return;
    }

    console.log('Starting manual BGG sync...');
    const token = bggToken.value();
    if (!token) {
      res.status(500).send('BGG_APP_TOKEN secret not set');
      return;
    }

    try {
      const result = await runPipeline(token);
      res.json({ ok: true, ...result });
    } catch (err) {
      res.status(500).json({ ok: false, error: err.message });
    }
  }
);
