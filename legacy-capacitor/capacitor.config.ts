import type { CapacitorConfig } from '@capacitor/cli';

/**
 * FC Scope iOS 셸 설정.
 *
 * - 앱은 원격 웹(https://www.fcscope.xyz)을 그대로 띄운다(Next.js SSR/API 라우트 때문에 정적 내보내기 불가).
 * - 로컬 개발: `CAP_SERVER_URL=http://<맥 LAN IP>:3000 npx cap sync ios` (cleartext 자동 허용).
 * - UA 토큰 `FCScopeApp/<버전>` 으로 웹이 앱 모드를 감지한다(lib/client/native.ts).
 *   버전은 package.json version — Xcode MARKETING_VERSION 과 함께 올릴 것.
 */
// CLI가 CJS로 트랜스파일하므로 require 사용
// eslint-disable-next-line @typescript-eslint/no-require-imports
const pkg = require('./package.json') as { version: string };
const serverUrl = process.env.CAP_SERVER_URL ?? 'https://www.fcscope.xyz';
const BG = '#0a1119';

const config: CapacitorConfig = {
  appId: 'xyz.fcscope.app',
  appName: 'FC Scope',
  webDir: 'www',
  backgroundColor: BG,
  server: {
    url: serverUrl,
    cleartext: serverUrl.startsWith('http://'),
    // 네트워크 실패 시 www/error.html (오프라인 안내 + 재시도)
    errorPath: 'error.html',
  },
  ios: {
    contentInset: 'never',
    scrollEnabled: true,
    backgroundColor: BG,
    appendUserAgent: `FCScopeApp/${pkg.version}`,
    preferredContentMode: 'mobile',
    // 스와이프로 뒤로가기 — 웹뷰 히스토리 기반. 네이티브 감각의 핵심.
    allowsLinkPreview: false,
  },
  plugins: {
    SplashScreen: {
      launchAutoHide: true,
      launchShowDuration: 800,
      launchFadeOutDuration: 200,
      backgroundColor: BG,
      showSpinner: false,
    },
    StatusBar: {
      style: 'DARK',
      overlaysWebView: true,
    },
  },
};

export default config;
