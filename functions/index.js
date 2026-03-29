const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onRequest } = require('firebase-functions/v2/https');
const { defineSecret } = require('firebase-functions/params');
const admin = require('firebase-admin');
const axios = require('axios');
const xml2js = require('xml2js');

admin.initializeApp();
const db = admin.firestore();

const bggToken = defineSecret('BGG_APP_TOKEN');
const adminKey = defineSecret('ADMIN_KEY');

const BGG_API = 'https://boardgamegeek.com/xmlapi2/thing';
const BATCH_SIZE = 20;
const BATCH_DELAY_MS = 1000;
const REFRESH_DAYS = 7;      // 最終取得から7日以上経過したゲームを更新対象とする
const MAX_PER_RUN = 200;     // 1回のFunction実行で更新する上限件数（タイムアウト対策）

// ─── BGGからゲームデータを取得 ──────────────────────────────────────────────
async function fetchBggBatch(bggIds, token) {
  const ids = bggIds.join(',');
  const url = `${BGG_API}?id=${ids}&type=boardgame&stats=1`;

  const reqHeaders = {
    'Authorization': `Bearer ${token}`,
    'User-Agent': 'PocketPlay/1.0 (board game discovery app)',
    'Accept': 'application/xml,text/xml,*/*',
  };

  let response = await axios.get(url, { headers: reqHeaders, timeout: 30000 });

  // 202 = BGGがキューイング中 → 最大3回リトライ
  let retries = 0;
  while (response.status === 202 && retries < 3) {
    await new Promise(r => setTimeout(r, 4000));
    response = await axios.get(url, { headers: reqHeaders, timeout: 30000 });
    retries++;
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

    const names = item.name || [];
    const primaryName = names.find(n => n.$.type === 'primary')?.$.value || '';

    const stats = item.statistics?.[0]?.ratings?.[0];
    const rating = parseFloat(stats?.average?.[0]?.$.value || '0');
    const complexity = parseFloat(stats?.averageweight?.[0]?.$.value || '0');

    const minPlayers = parseInt(item.minplayers?.[0]?.$.value || '0');
    const maxPlayers = parseInt(item.maxplayers?.[0]?.$.value || '0');
    const minTime = parseInt(item.minplaytime?.[0]?.$.value || '0');
    const maxTime = parseInt(item.maxplaytime?.[0]?.$.value || '0');
    const playTime = maxTime || minTime;

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
async function saveToFirestore(docId, bggData) {
  const ref = db.collection('games').doc(docId);
  const existing = await ref.get();

  const update = {
    lastFetched: admin.firestore.FieldValue.serverTimestamp(),
  };

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
  // 説明文は既存の日本語説明を上書きしない
  if (bggData.description && !existing.data()?.description) {
    update.description = bggData.description;
  }

  await ref.set(update, { merge: true });
}

// ─── 更新対象ゲームをFirestoreから取得 ──────────────────────────────────────
// 優先順位:
//   1. lastFetched が null（新規追加ゲーム）
//   2. lastFetched が REFRESH_DAYS 日以上前（古いゲーム）
// 上限 MAX_PER_RUN 件まで
async function fetchStaleGames() {
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - REFRESH_DAYS);

  // 未取得ゲーム（lastFetchedなし）を優先取得
  const newGamesSnap = await db.collection('games')
    .where('lastFetched', '==', null)
    .limit(MAX_PER_RUN)
    .get();

  const results = [];
  newGamesSnap.forEach(doc => {
    const data = doc.data();
    if (data.bggId) results.push({ docId: doc.id, bggId: data.bggId });
  });

  // 残り枠を古いゲームで埋める
  const remaining = MAX_PER_RUN - results.length;
  if (remaining > 0) {
    const staleSnap = await db.collection('games')
      .where('lastFetched', '<', admin.firestore.Timestamp.fromDate(cutoff))
      .orderBy('lastFetched', 'asc')   // 最も古いものから優先
      .limit(remaining)
      .get();

    staleSnap.forEach(doc => {
      const data = doc.data();
      if (data.bggId) results.push({ docId: doc.id, bggId: data.bggId });
    });
  }

  return results;
}

// ─── メイン処理 ──────────────────────────────────────────────────────────────
async function runPipeline(token) {
  const targets = await fetchStaleGames();
  console.log(`Update targets: ${targets.length} games (stale or new)`);

  if (targets.length === 0) {
    console.log('All games are up to date.');
    return { success: 0, failed: 0, skipped: 0 };
  }

  // bggId → docId のマップ
  const bggIdToDocId = new Map(targets.map(t => [t.bggId, t.docId]));
  const bggIds = targets.map(t => t.bggId);

  let success = 0;
  let failed = 0;

  for (let i = 0; i < bggIds.length; i += BATCH_SIZE) {
    const batchIds = bggIds.slice(i, i + BATCH_SIZE);

    try {
      const xml = await fetchBggBatch(batchIds, token);
      const parsed = await parseBggXml(xml);

      for (const data of parsed) {
        const docId = bggIdToDocId.get(data.bggId);
        if (!docId) continue;
        await saveToFirestore(docId, data);
        console.log(`✓ ${docId} (bggId:${data.bggId}): rating=${data.bggRating}`);
        success++;
      }
    } catch (err) {
      console.error(`Batch error (ids=${batchIds.slice(0, 3)}...): ${err.message}`);
      failed += batchIds.length;
    }

    if (i + BATCH_SIZE < bggIds.length) {
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
    secrets: [bggToken, adminKey],
    memory: '256MiB',
    timeoutSeconds: 300,
  },
  async (req, res) => {
    const key = req.headers['x-admin-key'];
    if (key !== adminKey.value()) {
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
