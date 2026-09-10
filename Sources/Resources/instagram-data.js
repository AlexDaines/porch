/* Runs in an empty local WebKit document with the existing Instagram cookie store.
   Only this bundled adapter executes; Instagram's application HTML/JS is not loaded. */
const cookie = name => document.cookie.split(';').map(s => s.trim()).find(s => s.startsWith(name + '='))?.slice(name.length + 1);
const headers = {'X-IG-App-ID': '936619743392459', 'X-Requested-With': 'XMLHttpRequest', 'X-IG-WWW-Claim': '0'};
const csrf = cookie('csrftoken');
if (csrf) headers['X-CSRFToken'] = csrf;
const state = globalThis.__porchDataState ||= {feedCursor: null, storyIDs: new Set(), threadIDs: new Set()};
const result = {posts: [], stories: [], threads: [], messages: [], hasMore: false, error: null, diagnostic: {}};
const safeURL = value => {
  try {
    const url = new URL(value);
    return url.protocol === 'https:' && !url.username && !url.password && (!url.port || url.port === '443') &&
      (url.hostname.endsWith('.cdninstagram.com') || url.hostname.endsWith('.fbcdn.net')) ? url.href : null;
  } catch { return null; }
};
const userID = user => String(user?.pk_id ?? user?.pk ?? user?.id ?? '');
const isAd = item => item?.ad_id != null || item?.is_ad === true || item?.is_sponsored === true || item?.is_paid_partnership === true;
async function request(path) {
  const response = await fetch(path, {method: 'GET', credentials: 'include', redirect: 'error', headers, signal: AbortSignal.timeout(15000)});
  result.diagnostic = {route: operation, http: String(response.status)};
  if (response.status === 429) throw new Error('rateLimited');
  if (response.status === 401 || response.status === 403) throw new Error('signIn');
  let data;
  try { data = await response.json(); } catch { throw new Error('unsupported'); }
  if (!response.ok || (data.status && data.status !== 'ok')) {
    throw new Error(data.message === 'login_required' ? 'signIn' : 'unavailable');
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
    video: video ? safeURL(video.url) : null, isVideo: item.media_type === 2};
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
  if (operation === 'feed' || operation === 'moreFeed') {
    if (operation === 'moreFeed' && !state.feedCursor) throw new Error('unavailable');
    const cursor = operation === 'moreFeed' ? '&max_id=' + encodeURIComponent(state.feedCursor) : '';
    const data = await request('/api/v1/feed/timeline/?count=12&pagination_source=following&reason=pull_to_refresh' + cursor);
    if (!Array.isArray(data.feed_items) || data.pagination_source !== 'following' || data.is_shell_response === true) throw new Error('unsupported');
    state.feedCursor = data.more_available && data.next_max_id ? String(data.next_max_id).slice(0, 2048) : null;
    result.hasMore = Boolean(state.feedCursor);
    // Suggested-user and recommendation modules are never passed to the renderer.
    result.posts = data.feed_items.filter(wrapper => !isAd(wrapper)).map(wrapper => post(wrapper.media_or_ad)).filter(Boolean);
    result.posts = [...new Map(result.posts.map(p => [p.id, p])).values()].sort((a,b) => b.timestamp-a.timestamp).slice(0, 18);
  } else if (operation === 'stories') {
    const data = await request('/api/v1/feed/reels_tray/');
    if (!Array.isArray(data.tray)) throw new Error('unsupported');
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
    result.posts = reel.items.filter(item => item.id && !isAd(item)).slice(0, 30).map(item => {
      const media = asset(item);
      return media ? {id: String(item.id), username: String(reel.user?.username || '').slice(0, 30), caption: '', timestamp: Number(item.taken_at) || 0, media: [media]} : null;
    }).filter(Boolean);
  } else if (operation === 'inbox') {
    const data = await request('/api/v1/direct_v2/inbox/?limit=20&thread_message_limit=1');
    if (!Array.isArray(data.inbox?.threads)) throw new Error('unsupported');
    state.threadIDs.clear();
    result.threads = data.inbox.threads.filter(thread => !thread.pending && /^\d+$/.test(String(thread.thread_id))).slice(0, 20).map(thread => {
      const id = String(thread.thread_id); state.threadIDs.add(id);
      return {id, title: String(thread.thread_title || thread.users?.map(u => u.username).join(', ') || 'Message').slice(0, 150),
        preview: String(thread.items?.[0]?.text || '').slice(0, 250)};
    });
  } else if (operation === 'thread') {
    if (!state.threadIDs.has(identifier) || !/^\d+$/.test(identifier)) throw new Error('unavailable');
    const data = await request(`/api/v1/direct_v2/threads/${identifier}/?limit=20`);
    if (!Array.isArray(data.thread?.items)) throw new Error('unsupported');
    const ownID = cookie('ds_user_id');
    result.messages = data.thread.items.filter(item => item.item_id).slice(0, 20).map(item => ({id: String(item.item_id),
      text: String(item.text || (item.item_type === 'text' ? '' : 'Attachment')).slice(0, 4000),
      mine: String(item.user_id) === ownID})).reverse();
  } else { throw new Error('unavailable'); }
} catch (error) {
  result.error = ['rateLimited', 'signIn', 'unsupported', 'unavailable'].includes(error.message) ? error.message : 'unavailable';
}
return JSON.stringify(result);
