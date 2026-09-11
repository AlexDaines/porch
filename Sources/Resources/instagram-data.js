/* Runs in an empty local WebKit document with the existing Instagram cookie store.
   Only this bundled adapter executes; Instagram's application HTML/JS is not loaded. */
const cookie = name => document.cookie.split(';').map(s => s.trim()).find(s => s.startsWith(name + '='))?.slice(name.length + 1);
const headers = {'X-IG-App-ID': '936619743392459', 'X-Requested-With': 'XMLHttpRequest', 'X-IG-WWW-Claim': '0'};
const csrf = cookie('csrftoken');
if (csrf) headers['X-CSRFToken'] = csrf;
const state = globalThis.__porchDataState ||= {feedCursor: null, storyIDs: new Set(), threadIDs: new Set(), openedThreads: new Set(), sentContexts: new Map(), inboxCursor: null, threadCursors: new Map()};
const result = {posts: [], stories: [], threads: [], messages: [], hasMore: false, error: null,
  diagnostic: {operation, origin: 'instagram_web', csrf_present: String(Boolean(csrf)), viewer_present: String(Boolean(cookie('ds_user_id')))}, retryAfterSeconds: null, sentItemID: null};
const startedAt = performance.now();
function trace(stage) {
  // The isolated app content world is the only place this handler exists. Trace
  // delivery must never change the request's result or trigger another request.
  try {
    if (typeof requestTraceID === 'string') globalThis.webkit?.messageHandlers?.porchDiagnostics?.postMessage({
      trace: requestTraceID, fields: {...result.diagnostic, stage}
    });
  } catch {}
}
function responseShape(data) {
  const paths = ['status','message','error_type','payload','payload.item_id','payload.thread_id','payload.client_context','payload.message',
    'challenge','two_factor_info','feedback_message','feedback_title','inbox','inbox.threads','thread','thread.items',
    'feed_items','tray','reels','reels_media','pagination_source','has_older','oldest_cursor'];
  const shape = [];
  for (const path of paths) {
    let value = data;
    for (const part of path.split('.')) value = value && typeof value === 'object' ? value[part] : undefined;
    if (value !== undefined) shape.push(path + '=' + (value === null ? 'null' : Array.isArray(value) ? 'array' : typeof value));
  }
  result.diagnostic.response_shape = shape.join(';');
  result.diagnostic.schema_unknown_keys = String(data && typeof data === 'object' ? Object.keys(data).filter(k => !paths.includes(k)).length : 0);
}
async function errorFingerprint(data) {
  try {
    if (typeof diagnosticKey !== 'string' || !/^[a-f0-9]{64}$/.test(diagnosticKey)) return;
    const values = [data?.message, data?.error_type, data?.payload?.message].map(v => typeof v === 'string' ? v.slice(0, 2048) : '');
    if (!values.some(Boolean)) return;
    const bytes = new Uint8Array(diagnosticKey.match(/../g).map(value => parseInt(value, 16)));
    const key = await crypto.subtle.importKey('raw', bytes, {name:'HMAC', hash:'SHA-256'}, false, ['sign']);
    const digest = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(JSON.stringify(values)));
    result.diagnostic.server_fingerprint = [...new Uint8Array(digest)].map(v => v.toString(16).padStart(2, '0')).join('');
  } catch {} // Unknown errors remain groupable when crypto is available; never expose raw strings.
}
const safeURL = value => {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443') &&
      (url.hostname.endsWith('.cdninstagram.com') || url.hostname.endsWith('.fbcdn.net')) ? url.href : null;
  } catch { return null; }
};
const userID = user => String(user?.pk_id ?? user?.pk ?? user?.id ?? '');
const isAd = item => item?.ad_id != null || item?.is_ad === true || item?.is_sponsored === true || item?.is_paid_partnership === true;
async function request(path, body = null) {
  let response;
  const fetchStarted = performance.now();
  result.diagnostic.method = body ? 'POST' : 'GET';
  if (body) result.diagnostic.request_bytes = String(new TextEncoder().encode(body.toString()).length);
  trace('fetch_started');
  try {
    response = await fetch(path, {method: body ? 'POST' : 'GET', credentials: 'include', redirect: 'error',
      headers: body ? {...headers, 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8'} : headers,
      ...(body ? {body: body.toString()} : {}), signal: AbortSignal.timeout(15000)});
  } catch (error) {
    result.diagnostic.fetch_ms = String(Math.round(performance.now() - fetchStarted));
    result.diagnostic.fetch_error = ['TimeoutError','AbortError','TypeError'].includes(error.name) ? error.name : 'other';
    result.diagnostic.reason = ['TimeoutError','AbortError'].includes(error.name) ? 'timeout' : 'transport_error';
    if (body) throw new Error('sendUnconfirmed');
    throw new Error(error.name === 'TimeoutError' || error.name === 'AbortError' ? 'timedOut' : 'offline');
  }
  result.diagnostic.http = String(response.status);
  result.diagnostic.fetch_ms = String(Math.round(performance.now() - fetchStarted));
  const contentType = response.headers?.get?.('Content-Type') || '';
  result.diagnostic.content_type = !contentType ? 'missing' : contentType.includes('json') ? 'json' : contentType.includes('html') ? 'html' : contentType.startsWith('text/') ? 'text' : 'other';
  const contentLength = response.headers?.get?.('Content-Length');
  if (/^\d{1,12}$/.test(contentLength || '')) result.diagnostic.response_bytes = contentLength;
  trace('http_received');
  // Error envelopes carry the recovery action even when HTTP itself is 400/403.
  // Keep only recognized categories; never return server text or account details.
  let data;
  const decodeStarted = performance.now();
  try { data = await response.json(); } catch { data = null; }
  result.diagnostic.decode_ms = String(Math.round(performance.now() - decodeStarted));
  try { result.diagnostic.response_chars = String(JSON.stringify(data).length); responseShape(data); } catch {}
  if (!response.ok || data?.status === 'fail') await errorFingerprint(data);
  const serverReason = [data?.message, data?.error_type].find(value =>
    ['login_required', 'challenge_required', 'checkpoint_required', 'two_factor_required',
      'feedback_required', 'sentry_block', 'rate_limit_error'].includes(value));
  const validEnvelope = data && typeof data === 'object' && !Array.isArray(data);
  result.diagnostic.reason = serverReason || (!validEnvelope ? 'invalid_response' :
    response.ok && (!data.status || data.status === 'ok') ? 'none' : 'unclassified');
  trace('decoded');
  if (response.status === 429 || serverReason === 'rate_limit_error') {
    const retry = response.headers?.get?.('Retry-After');
    const seconds = /^\d+$/.test(retry || '') ? Number(retry) : Math.ceil((Date.parse(retry) - Date.now()) / 1000);
    result.retryAfterSeconds = Math.max(60, Math.min(Number.isFinite(seconds) ? seconds : 60, 86400));
    throw new Error('rateLimited');
  }
  if (['login_required', 'challenge_required', 'checkpoint_required', 'two_factor_required'].includes(serverReason)) throw new Error('signIn');
  if (serverReason === 'feedback_required' || serverReason === 'sentry_block') throw new Error('actionBlocked');
  if (response.status === 401 || response.status === 403) throw new Error('signIn');
  if (body && [400, 404, 422].includes(response.status)) throw new Error('sendRejected');
  if (!validEnvelope) throw new Error(body ? 'sendUnconfirmed' : 'unsupported');
  if (!response.ok || (data.status && data.status !== 'ok')) {
    throw new Error(body ? 'sendUnconfirmed' : 'unavailable');
  }
  return data;
}
function asset(item) {
  if (![1, 2].includes(item.media_type)) return null;
  const choices = (item.image_versions2?.candidates || []).filter(c => safeURL(c.url));
  const image = choices.find(c => c.width >= 800 && c.width <= 1440) || choices[0];
  if (!image) return null;
  const video = item.media_type === 2 ? (item.video_versions || []).find(v => safeURL(v.url)) : null;
  return {url: safeURL(image.url), width: Math.max(1, Number(image.width) || 1), height: Math.max(1, Number(image.height) || 1),
    video: video ? safeURL(video.url) : null, isVideo: item.media_type === 2, alt: String(item.accessibility_caption || '').slice(0, 1000)};
}
function post(item) {
  if (!item || isAd(item) || item.product_type === 'clips' || ![1, 2, 8].includes(item.media_type)) return null;
  if (item.user?.friendship_status?.following !== true || !item.user?.username || !item.id) return null;
  const media = (item.carousel_media || [item]).filter(m => !isAd(m) && m.product_type !== 'clips').map(asset).filter(Boolean).slice(0, 20);
  if (!media.length) return null;
  return {id: String(item.id), username: String(item.user.username).slice(0, 30),
    caption: String(item.caption?.text || '').slice(0, 2200), timestamp: Number(item.taken_at) || 0, media};
}
try {
  if (operation === 'sessionHint') {
    // A local hint for the entry label, never proof of authentication. No request.
    result.diagnostic.savedSession = /^\d+$/.test(cookie('ds_user_id') || '') ? 'present' : 'absent';
  } else if (operation === 'session') {
    const ownID = cookie('ds_user_id');
    if (!/^\d+$/.test(ownID || '')) throw new Error('signIn');
    const data = await request('/api/v1/direct_v2/inbox/?limit=1&thread_message_limit=1');
    if (!Array.isArray(data.inbox?.threads)) throw new Error('unsupported');
    // Only authenticated success crosses to native code. No conversation content.
  } else if (operation === 'feed' || operation === 'moreFeed') {
    if (operation === 'moreFeed' && !state.feedCursor) throw new Error('unavailable');
    const cursor = operation === 'moreFeed' ? '&max_id=' + encodeURIComponent(state.feedCursor) : '';
    const data = await request('/api/v1/feed/timeline/?count=12&pagination_source=following&reason=pull_to_refresh' + cursor);
    if (!Array.isArray(data.feed_items) || data.pagination_source !== 'following' || data.is_shell_response === true) throw new Error('unsupported');
    result.diagnostic.raw_count = String(data.feed_items.length);
    const nextCursor = data.more_available && data.next_max_id ? String(data.next_max_id).slice(0, 2048) : null;
    if (operation === 'moreFeed' && nextCursor === state.feedCursor) throw new Error('unsupported');
    state.feedCursor = nextCursor;
    result.hasMore = Boolean(state.feedCursor);
    // Suggested-user and recommendation modules are never passed to the renderer.
    result.posts = data.feed_items.filter(wrapper => !isAd(wrapper)).map(wrapper => post(wrapper.media_or_ad)).filter(Boolean);
    result.posts = [...new Map(result.posts.map(p => [p.id, p])).values()].sort((a,b) => b.timestamp-a.timestamp).slice(0, 18);
  } else if (operation === 'stories') {
    const data = await request('/api/v1/feed/reels_tray/');
    if (!Array.isArray(data.tray)) throw new Error('unsupported');
    result.diagnostic.raw_count = String(data.tray.length);
    state.storyIDs.clear();
    result.stories = data.tray.filter(row => row.user?.username && !isAd(row) && row.user?.friendship_status?.following === true)
      .filter(row => /^\d+$/.test(userID(row.user))).slice(0, 50).map(row => {
        const id = userID(row.user); state.storyIDs.add(id);
        return {id, username: String(row.user.username).slice(0, 30), avatar: safeURL(row.user.profile_pic_url)};
      });
    result.stories = [...new Map(result.stories.map(p => [p.id, p])).values()];
  } else if (operation === 'story') {
    if (!state.storyIDs.has(identifier) || !/^\d+$/.test(identifier)) throw new Error('unavailable');
    const data = await request(`/api/v1/feed/reels_media/?reel_ids=${identifier}`);
    const reel = data.reels?.[identifier] || data.reels_media?.find(row => userID(row.user) === identifier);
    if (!reel || !Array.isArray(reel.items)) throw new Error('unsupported');
    result.diagnostic.raw_count = String(reel.items.length);
    result.posts = reel.items.filter(item => item.id && !isAd(item)).slice(0, 30).map(item => {
      const media = asset(item);
      return media ? {id: String(item.id), username: String(reel.user?.username || '').slice(0, 30), caption: '', timestamp: Number(item.taken_at) || 0, media: [media]} : null;
    }).filter(Boolean);
  } else if (operation === 'inbox' || operation === 'moreInbox') {
    if (operation === 'moreInbox' && !state.inboxCursor) throw new Error('unavailable');
    const cursor = operation === 'moreInbox' ? '&direction=older&cursor=' + encodeURIComponent(state.inboxCursor) : '';
    const data = await request('/api/v1/direct_v2/inbox/?limit=20&thread_message_limit=1' + cursor);
    if (!Array.isArray(data.inbox?.threads)) throw new Error('unsupported');
    result.diagnostic.raw_count = String(data.inbox.threads.length);
    const nextCursor = data.inbox.has_older !== false && data.inbox.oldest_cursor ? String(data.inbox.oldest_cursor).slice(0,2048) : null;
    if (operation === 'moreInbox' && nextCursor === state.inboxCursor) throw new Error('unsupported');
    state.inboxCursor = nextCursor;
    result.hasMore = Boolean(nextCursor);
    if (operation === 'inbox') { state.threadIDs.clear(); state.openedThreads.clear(); state.threadCursors.clear(); }
    result.threads = data.inbox.threads.filter(thread => !thread.pending && /^\d+$/.test(String(thread.thread_id))).slice(0, 20).map(thread => {
      const id = String(thread.thread_id); state.threadIDs.add(id);
      return {id, title: String(thread.thread_title || thread.users?.map(u => u.username).join(', ') || 'Message').slice(0, 150),
        preview: String(thread.items?.[0]?.text || '').slice(0, 250)};
    });
  } else if (operation === 'thread' || operation === 'olderMessages') {
    if (!state.threadIDs.has(identifier) || !/^\d+$/.test(identifier)) throw new Error('unavailable');
    const previous = state.threadCursors.get(identifier);
    if (operation === 'olderMessages' && !previous) throw new Error('unavailable');
    const cursor = operation === 'olderMessages' ? '&direction=older&cursor=' + encodeURIComponent(previous) : '';
    const data = await request(`/api/v1/direct_v2/threads/${identifier}/?limit=20` + cursor);
    if (!Array.isArray(data.thread?.items)) throw new Error('unsupported');
    result.diagnostic.raw_count = String(data.thread.items.length);
    if (data.thread.pending) throw new Error('unavailable');
    const nextCursor = data.thread.has_older !== false && data.thread.oldest_cursor ? String(data.thread.oldest_cursor).slice(0,2048) : null;
    if (operation === 'olderMessages' && nextCursor === previous) throw new Error('unsupported');
    state.threadCursors.set(identifier,nextCursor); result.hasMore = Boolean(nextCursor);
    state.openedThreads.add(identifier);
    const ownID = cookie('ds_user_id');
    const names = new Map((data.thread.users || []).map(user => [userID(user),String(user.username || '').slice(0,30)]));
    result.messages = data.thread.items.filter(item => item.item_id).slice(0, 20).map(item => ({id: String(item.item_id),
      text: String(item.text || ({media:'Photo or video',voice_media:'Voice message',media_share:'Shared post',clip:'Shared Reel',link:item.link?.text || 'Shared link',like:'Heart'}[item.item_type]) || (item.item_type === 'text' ? '' : 'Unsupported attachment')).slice(0, 4000),
      sender: names.get(String(item.user_id)) || null,
      mine: String(item.user_id) === ownID, context: item.client_context ? String(item.client_context) : null})).reverse();
  } else if (operation === 'sendText') {
    result.diagnostic.thread_allowed = String(state.threadIDs.has(identifier));
    result.diagnostic.thread_opened = String(state.openedThreads.has(identifier));
    result.diagnostic.message_utf16 = String(typeof messageText === 'string' ? messageText.length : 0);
    result.diagnostic.context_valid = String(/^\d{16,22}$/.test(clientContext || ''));
    trace('validation');
    if (!state.threadIDs.has(identifier) || !state.openedThreads.has(identifier) || !/^\d+$/.test(identifier)) { result.diagnostic.reason = 'invalid_recipient'; throw new Error('invalidMessage'); }
    if (typeof messageText !== 'string' || !messageText.trim()) { result.diagnostic.reason = 'empty_message'; throw new Error('invalidMessage'); }
    if (messageText.length > 1000) { result.diagnostic.reason = 'message_too_long'; throw new Error('invalidMessage'); }
    if (!/^\d{16,22}$/.test(clientContext || '')) { result.diagnostic.reason = 'invalid_context'; throw new Error('invalidMessage'); }
    if (!csrf) { result.diagnostic.reason = 'missing_csrf'; throw new Error('signIn'); }
    if (state.sentContexts.has(clientContext)) {
      result.sentItemID = state.sentContexts.get(clientContext);
    } else {
      const body = new URLSearchParams({action: 'send_item', thread_ids: '[' + identifier + ']', text: messageText,
        client_context: clientContext, mutation_token: clientContext, offline_threading_id: clientContext});
      const data = await request('/api/v1/direct_v2/threads/broadcast/text/', body);
      const itemID = data.payload?.item_id;
      result.diagnostic.receipt_present = String(itemID != null);
      result.diagnostic.receipt_thread_matches = String(!data.payload?.thread_id || String(data.payload.thread_id) === identifier);
      result.diagnostic.receipt_context_matches = String(!data.payload?.client_context || String(data.payload.client_context) === clientContext);
      trace('receipt');
      if (data.status !== 'ok' || !['string','number'].includes(typeof itemID) || !/^[A-Za-z0-9_-]{1,128}$/.test(String(itemID))) {
        result.diagnostic.reason = 'missing_receipt'; throw new Error('sendUnconfirmed');
      }
      if ((data.payload.thread_id && String(data.payload.thread_id) !== identifier) ||
          (data.payload.client_context && String(data.payload.client_context) !== clientContext)) {
        result.diagnostic.reason = 'receipt_mismatch'; throw new Error('sendUnconfirmed');
      }
      result.sentItemID = String(itemID);
      state.sentContexts.set(clientContext, result.sentItemID);
      if (state.sentContexts.size > 100) state.sentContexts.delete(state.sentContexts.keys().next().value);
    }
  } else { throw new Error('unavailable'); }
} catch (error) {
  result.error = ['rateLimited', 'signIn', 'actionBlocked', 'unsupported', 'unavailable', 'offline', 'timedOut', 'invalidMessage', 'sendRejected', 'sendUnconfirmed'].includes(error.message) ? error.message : 'unavailable';
}
result.diagnostic.duration_ms = String(Math.round(performance.now() - startedAt));
result.diagnostic.result = result.error || 'none';
if (result.diagnostic.raw_count != null) result.diagnostic.filtered_count = String(Math.max(0, Number(result.diagnostic.raw_count) - result.posts.length - result.stories.length - result.threads.length - result.messages.length));
trace('completed');
return JSON.stringify(result);
