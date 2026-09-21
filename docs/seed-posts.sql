-- FC Scope 커뮤니티 첫 글 (운영자 계정으로 게시)
-- Supabase → SQL Editor 에서 실행. 'YOUR_EMAIL' 두 곳을 운영자 로그인 이메일로 바꾸세요.
-- 운영자 표시는 제목이 아니라 작성자 옆 '운영자' 배지로 자동 표시된다(ADMIN_EMAILS 계정). 제목엔 붙이지 않는다.

-- 0) 확인: 운영자 계정이 있고 커뮤니티 닉네임이 등록돼 있어야 글쓴이가 "알 수 없음"으로 안 뜬다
select u.id, u.email, p.nickname
from auth.users u
left join profiles p on p.id = u.id
where u.email = 'YOUR_EMAIL';

-- 1) 글 4개 (시간을 조금씩 벌려 최신순이 자연스럽게)
with me as (select id from auth.users where email = 'YOUR_EMAIL')
insert into community_posts (id, author_id, type, title, body, meta, created_at)
select substr(md5(random()::text || v.n::text), 1, 10), me.id, v.t, v.title, v.body, v.meta::jsonb,
       now() - make_interval(hours => v.n * 3)
from me, (values
  (4, 'squad_rate',
   '도르트문트 팀컬러 4-2-3-1 평가 부탁드려요',
   E'안녕하세요, FC Scope 운영자입니다. 제 공식경기 스쿼드 평가 부탁드려요.\n\n🎯 현재 등급: 챔피언스권\n⚽ 포메이션: 4-2-3-1 (도르트문트 팀컬러)\n🌟 핵심 카드: 브란트(CAM) · 기라시(ST) · 은메차(DM)\n😥 고민 포지션: 센터백 — 앱 스쿼드 클리닉에서 수비 라인 점수가 가장 낮게 나왔어요\n🙏 팀컬러를 유지하면서 센터백 교체 후보를 추천해 주세요!\n\n※ 전적 검색 → 선수 탭에서 선수별 평점과 랭커 비교를 볼 수 있어요.',
   '{"budget":"센터백 1명분"}'),
  (3, 'squad_make',
   '감독모드용 수비 탄탄한 3백 스쿼드 추천해 주세요',
   E'💰 예산: 중간\n⚽ 선호 포메이션: 3-4-2-1 또는 3-5-2\n❤️ 좋아하는 리그/선수: 분데스리가\n🎯 목표 등급: 감독모드 월드클래스\n📌 기타 조건: 역습 위주, 윙백 체력 좋은 카드\n\n스쿼드 빌더에서 만든 뒤 공유 링크로 달아 주시면 좋아요!',
   '{"budget":"중간"}'),
  (2, 'squad_make',
   '손흥민·이강인·김민재 넣은 국대 스쿼드, 나머지 자리 추천해 주세요',
   E'스쿼드 빌더 → 팀 프리셋 → 대한민국을 불러오면 2025-26 대표 선발이 바로 배치돼요.\n\n여기서 손흥민·이강인·김민재는 고정하고, 나머지 자리를 어떤 카드로 채우면 공식경기에서 제일 잘 먹힐까요?\n\n💰 예산: 자유\n⚽ 선호 포메이션: 4-2-3-1\n🎯 목표: 공식경기 챔피언스',
   '{"budget":"자유"}'),
  (1, 'squad_make',
   '입문자용 가성비 4-3-3 — 프리미어리그 위주로 추천해 주세요',
   E'FC온라인 막 시작한 친구에게 추천할 스쿼드를 찾고 있어요.\n\n💰 예산: 적음\n⚽ 선호 포메이션: 4-3-3\n❤️ 좋아하는 리그: 프리미어리그\n🎯 목표 등급: 월드클래스\n📌 기타 조건: 조작 쉬운 카드 위주\n\n여러분이라면 누구부터 사시겠어요?',
   '{"budget":"적음"}')
) as v(n, t, title, body, meta);

-- 2) 확인
select id, type, title, created_at from community_posts order by created_at desc limit 10;

-- 되돌리기(필요할 때만): 운영자가 SQL 로 넣은 글 삭제
-- delete from community_posts where author_id = (select id from auth.users where email = 'YOUR_EMAIL');

-- 이미 '[운영자] ' 접두어로 올린 글이 있으면 제목에서 떼어낸다(배지가 대신 표시됨)
-- update community_posts set title = regexp_replace(title, '^\[운영자\]\s*', '') where title like '[운영자]%';
