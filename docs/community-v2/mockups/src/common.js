// 커뮤니티 v2 목업 공용 — 상태바·탭바 주입. .app[data-tab] 이면 탭바를 붙인다(상세·글쓰기는 탭바 숨김).
const ICON = {
  search: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><circle cx="10.5" cy="10.5" r="6.5"/><path d="M20 20l-4.6-4.6"/></svg>',
  squad: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2l8 3v6c0 5-3.4 9.3-8 11-4.6-1.7-8-6-8-11V5l8-3z"/></svg>',
  rank: '<svg viewBox="0 0 24 24" fill="currentColor"><rect x="3" y="11" width="5" height="10" rx="1.5"/><rect x="9.5" y="6" width="5" height="15" rx="1.5"/><rect x="16" y="3" width="5" height="18" rx="1.5"/></svg>',
  comm: '<svg viewBox="0 0 24 24" fill="currentColor"><circle cx="8" cy="8" r="3.5"/><circle cx="16.5" cy="8" r="3.5"/><path d="M1.5 20c.5-4 3.3-6.5 6.5-6.5s6 2.5 6.5 6.5zM12.5 20c.3-2.4-.3-4.4-1.6-5.9 1.4-.9 3.1-1.1 5.6-1.1 3.2 0 6 2.5 6.5 7z"/></svg>',
  me: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 2a10 10 0 100 20 10 10 0 000-20zm0 4a3.5 3.5 0 110 7 3.5 3.5 0 010-7zm0 14c-2.7 0-5-1.3-6.4-3.3C7 15 9.3 14.2 12 14.2s5 .8 6.4 2.5A7.9 7.9 0 0112 20z"/></svg>',
};
document.querySelectorAll('.app').forEach(app => {
  app.insertAdjacentHTML('afterbegin', `<div class="status"><span>9:41</span><div class="island"></div><div class="icons"><span class="bar"><i style="height:4px"></i><i style="height:6px"></i><i style="height:8px"></i><i style="height:11px"></i></span><span class="batt"><i></i></span></div></div>`);
  const active = app.dataset.tab;
  if (active) {
    const tabs = [['search','전적'],['squad','스쿼드'],['rank','픽 랭킹'],['comm','커뮤니티'],['me','내 정보']];
    app.insertAdjacentHTML('beforeend', `<nav class="tabbar">${tabs.map(([k,l]) => `<div class="${k===active?'on':''}">${ICON[k]}${l}</div>`).join('')}</nav>`);
  }
});
