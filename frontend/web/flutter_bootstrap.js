{{flutter_js}}
{{flutter_build_config}}

// Load without a service worker: the default one caches main.dart.js, so a
// freshly deployed build can be hidden behind an old cached copy (which may
// call a different API). Remove any worker left by earlier builds.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then((regs) => regs.forEach((r) => r.unregister()));
}

// Simple static servers send no cache headers, so browsers may keep reusing
// an old main.dart.js. In release builds, tag it with this build's hash: a
// new build means a new URL. Kept inside a template string so the file stays
// valid JavaScript even where Flutter leaves the placeholder unfilled
// (`flutter run` debug builds, which are left untouched).
const buildVersion = (`{{flutter_service_worker_version}}`.match(/\d+/) ?? [])[0];
for (const build of _flutter.buildConfig?.builds ?? []) {
  if (buildVersion && build.compileTarget === 'dart2js' && build.mainJsPath) {
    build.mainJsPath += `?v=${buildVersion}`;
  }
}
_flutter.loader.load();
